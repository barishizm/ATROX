-- P077 · Coach quota, entitlement and abuse protection (docs/04-AI-KOC.md §7).
--   entitlements          Pro status per user. Filled by the subscription work (P090); no row = free.
--                         The owner reads it; only the service role writes it.
--   coach_limits          per-tier limits (daily messages, requests per minute, agent steps, output tokens per turn,
--                         thinking mode). Public reference data, edited by the service role.
--   coach_quota           one counter row per user: messages in the user's local day + requests in the current minute.
--                         The owner reads it (quota indicator); only coach_consume_quota() writes it.
--   coach_consume_quota() atomic check-and-count (row lock), day boundary in the user's time zone. Service role only.
--   coach_spend_today()   total coach_usage.cost_usd since UTC midnight, for the global circuit breaker. Service role only.
--   coach_has_ai_consent() whether the caller's latest ai_sharing consent is granted for the given version.

create table public.entitlements (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null unique references auth.users (id) on delete cascade,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  tier        text not null default 'free',
  source      text not null default 'none',
  expires_at  timestamptz,

  constraint entitlements_tier_check check (tier in ('free', 'pro')),
  constraint entitlements_source_check check (source in ('none', 'app_store', 'promo', 'manual'))
);
create trigger entitlements_set_updated_at before insert or update on public.entitlements
  for each row execute function public.set_updated_at();

create table public.coach_limits (
  tier                     text primary key,
  daily_messages           integer not null,
  requests_per_minute      integer not null,
  max_agent_steps          integer not null,
  max_output_tokens_turn   integer not null,
  thinking                 boolean not null default false,
  updated_at               timestamptz not null default now(),

  constraint coach_limits_tier_check check (tier in ('free', 'pro')),
  constraint coach_limits_numbers_check check (
    daily_messages >= 0 and requests_per_minute >= 1 and max_agent_steps between 1 and 10
    and max_output_tokens_turn between 100 and 32000)
);
insert into public.coach_limits (tier, daily_messages, requests_per_minute, max_agent_steps, max_output_tokens_turn, thinking)
values ('free', 5, 6, 5, 3000, false),
       ('pro', 100, 6, 5, 8000, true);

create table public.coach_quota (
  user_id       uuid primary key references auth.users (id) on delete cascade,
  day           date not null,
  messages      integer not null default 0,
  minute_start  timestamptz not null default now(),
  minute_count  integer not null default 0,
  updated_at    timestamptz not null default now(),

  constraint coach_quota_counts_check check (messages >= 0 and minute_count >= 0)
);

alter table public.entitlements enable row level security;
alter table public.coach_limits enable row level security;
alter table public.coach_quota enable row level security;
revoke all on public.entitlements, public.coach_limits, public.coach_quota from anon, authenticated;
grant select on public.entitlements, public.coach_quota to authenticated;
grant select on public.coach_limits to anon, authenticated;

create policy entitlements_select_own on public.entitlements
  for select to authenticated using (user_id = (select auth.uid()));
create policy coach_quota_select_own on public.coach_quota
  for select to authenticated using (user_id = (select auth.uid()));
create policy coach_limits_select_all on public.coach_limits
  for select to anon, authenticated using (true);

-- Returns the decision and the limits of the user's tier. Counts the request only when it is allowed.
--   reason: null (allowed) | 'rate_minute' | 'daily'
create function public.coach_consume_quota(p_user uuid, p_time_zone text default 'UTC')
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_tz      text := case when exists (select 1 from pg_catalog.pg_timezone_names where name = p_time_zone)
                         then p_time_zone else 'UTC' end;
  v_today   date := (now() at time zone v_tz)::date;
  v_tier    text;
  v_limits  public.coach_limits;
  v_quota   public.coach_quota;
begin
  select coalesce((select e.tier from public.entitlements e
                    where e.user_id = p_user and (e.expires_at is null or e.expires_at > now())), 'free')
    into v_tier;
  select * into v_limits from public.coach_limits where tier = v_tier;
  if not found then
    raise exception 'coach_limits row missing for tier %', v_tier;
  end if;

  insert into public.coach_quota (user_id, day) values (p_user, v_today) on conflict (user_id) do nothing;
  -- The row lock serialises concurrent requests of the same user: check and increment happen as one step.
  select * into v_quota from public.coach_quota where user_id = p_user for update;

  if v_quota.day <> v_today then
    v_quota.day := v_today;
    v_quota.messages := 0;
  end if;
  if v_quota.minute_start <= now() - interval '1 minute' then
    v_quota.minute_start := now();
    v_quota.minute_count := 0;
  end if;

  if v_quota.minute_count >= v_limits.requests_per_minute then
    update public.coach_quota set day = v_quota.day, messages = v_quota.messages, updated_at = now()
     where user_id = p_user;
    return jsonb_build_object('allowed', false, 'reason', 'rate_minute', 'tier', v_tier,
      'remaining', greatest(v_limits.daily_messages - v_quota.messages, 0),
      'reset_at', v_quota.minute_start + interval '1 minute', 'limits', to_jsonb(v_limits) - 'updated_at');
  end if;
  if v_quota.messages >= v_limits.daily_messages then
    update public.coach_quota set day = v_quota.day, messages = v_quota.messages,
           minute_start = v_quota.minute_start, minute_count = v_quota.minute_count, updated_at = now()
     where user_id = p_user;
    return jsonb_build_object('allowed', false, 'reason', 'daily', 'tier', v_tier, 'remaining', 0,
      'reset_at', ((v_today + 1)::timestamp at time zone v_tz), 'limits', to_jsonb(v_limits) - 'updated_at');
  end if;

  update public.coach_quota
     set day = v_quota.day, messages = v_quota.messages + 1,
         minute_start = v_quota.minute_start, minute_count = v_quota.minute_count + 1, updated_at = now()
   where user_id = p_user;
  return jsonb_build_object('allowed', true, 'reason', null, 'tier', v_tier,
    'remaining', v_limits.daily_messages - v_quota.messages - 1,
    'reset_at', ((v_today + 1)::timestamp at time zone v_tz), 'limits', to_jsonb(v_limits) - 'updated_at');
end
$$;

create function public.coach_spend_today()
returns numeric
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(sum(u.cost_usd), 0) from public.coach_usage u
  where u.created_at >= date_trunc('day', now() at time zone 'UTC') at time zone 'UTC';
$$;

create function public.coach_has_ai_consent(p_version text)
returns boolean
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce((
    select c.granted and c.version = p_version
    from public.consents c
    where c.user_id = (select auth.uid()) and c.kind = 'ai_sharing'
    order by c.created_at desc, c.id desc
    limit 1), false);
$$;

revoke all on function public.coach_consume_quota(uuid, text) from public, anon, authenticated;
revoke all on function public.coach_spend_today() from public, anon, authenticated;
grant execute on function public.coach_consume_quota(uuid, text) to service_role;
grant execute on function public.coach_spend_today() to service_role;
revoke all on function public.coach_has_ai_consent(text) from public, anon;
grant execute on function public.coach_has_ai_consent(text) to authenticated;
