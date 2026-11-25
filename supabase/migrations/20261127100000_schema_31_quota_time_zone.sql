-- Pins the time zone that decides when a user's daily coach and food allowances reset (audit D39).
-- The zone came straight from each request body, so alternating two far-apart zones (UTC+14 / UTC-12) reset the coach
-- counter on every message, and picking the zone whose midnight just passed shrank the food window to about an hour.
-- Now the first valid zone is kept on the user's coach_quota row; another zone is accepted at most once per 24 hours
-- (travel), otherwise the kept one is used. coach_digest_allowance (Pro only, small caps, STABLE) is left as it is.

alter table public.coach_quota
  add column time_zone text,
  add column time_zone_changed_at timestamptz;

-- The zone to count the user's day in: the requested one when valid and either nothing is kept yet, it is the kept
-- one, or the kept one is at least 24 hours old; the kept one otherwise. Unknown zones count as 'UTC'.
create function public.quota_time_zone(p_user uuid, p_requested text)
returns text
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_requested text := case when exists (select 1 from pg_catalog.pg_timezone_names where name = p_requested)
                           then p_requested else 'UTC' end;
  v_row       public.coach_quota;
begin
  insert into public.coach_quota (user_id, day) values (p_user, (now() at time zone v_requested)::date)
  on conflict (user_id) do nothing;
  select * into v_row from public.coach_quota where user_id = p_user for update;
  if v_row.time_zone = v_requested then
    return v_requested;
  end if;
  if v_row.time_zone is null or v_row.time_zone_changed_at is null
     or v_row.time_zone_changed_at <= now() - interval '24 hours' then
    update public.coach_quota set time_zone = v_requested, time_zone_changed_at = now(), updated_at = now()
     where user_id = p_user;
    return v_requested;
  end if;
  return v_row.time_zone;
end
$$;

revoke all on function public.quota_time_zone(uuid, text) from public, anon, authenticated;
grant execute on function public.quota_time_zone(uuid, text) to service_role;

-- Same bodies as schema_20 / schema_27 / schema_28; only the time zone now comes from quota_time_zone().
create or replace function public.coach_consume_quota(p_user uuid, p_time_zone text default 'UTC')
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_tz      text := public.quota_time_zone(p_user, p_time_zone);
  v_today   date := (now() at time zone v_tz)::date;
  v_tier    text;
  v_limits  public.coach_limits;
  v_quota   public.coach_quota;
begin
  v_tier := public.entitlement_tier(p_user);
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

create or replace function public.coach_refund_quota(p_user uuid, p_time_zone text default 'UTC')
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_tz    text := public.quota_time_zone(p_user, p_time_zone);
  v_today date := (now() at time zone v_tz)::date;
begin
  update public.coach_quota
     set messages = greatest(messages - 1, 0), updated_at = now()
   where user_id = p_user and day = v_today and messages > 0;
end
$$;

create or replace function public.food_consume(p_user uuid, p_kind text, p_time_zone text default 'UTC')
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tz     text;
  v_start  timestamptz;
  v_tier   text;
  v_limit  integer;
  v_used   integer;
  v_recent integer;
  v_id     uuid;
begin
  perform pg_advisory_xact_lock(hashtextextended('food_consume:' || p_user::text, 0));
  v_tz := public.quota_time_zone(p_user, p_time_zone);
  v_start := date_trunc('day', now() at time zone v_tz) at time zone v_tz;
  select coalesce((select e.tier from public.entitlements e
                    where e.user_id = p_user and (e.expires_at is null or e.expires_at > now())), 'free')
    into v_tier;
  v_limit := case v_tier when 'pro' then 60 else 3 end;
  select count(*) into v_used from public.food_analyses a where a.user_id = p_user and a.created_at >= v_start;
  select count(*) into v_recent from public.food_analyses a
   where a.user_id = p_user and a.created_at > now() - interval '1 minute';
  if v_recent >= 6 then
    return jsonb_build_object('allowed', false, 'reason', 'rate', 'tier', v_tier, 'used', v_used, 'limit', v_limit);
  end if;
  if v_used >= v_limit then
    return jsonb_build_object('allowed', false, 'reason', 'daily', 'tier', v_tier, 'used', v_used, 'limit', v_limit);
  end if;
  insert into public.food_analyses (user_id, kind) values (p_user, p_kind) returning id into v_id;
  return jsonb_build_object('allowed', true, 'reason', null, 'id', v_id, 'tier', v_tier, 'used', v_used + 1, 'limit', v_limit);
end
$$;
