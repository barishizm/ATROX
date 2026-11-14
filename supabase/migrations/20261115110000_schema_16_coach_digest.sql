-- P083 · Proactive coach content (docs/04-AI-KOC.md §11): post-workout comment and weekly summary comment.
--   coach_digests            generated comments, one per (user, kind, locale, input hash): the cache for "same input,
--                            same answer" and the source of the separate daily count. The owner reads, only the
--                            service role writes.
--   coach_digest_allowance() Pro check and the per-day allowance of one kind (counted on generated rows, so cache hits
--                            are free). Separate from the chat quota (coach_quota).

create table public.coach_digests (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references auth.users (id) on delete cascade,
  created_at  timestamptz not null default now(),
  kind        text not null,
  locale      text not null,
  input_hash  text not null,
  body        text not null,

  constraint coach_digests_kind_check check (kind in ('workout', 'weekly')),
  constraint coach_digests_body_check check (char_length(body) between 1 and 800),
  constraint coach_digests_unique unique (user_id, kind, locale, input_hash)
);
create index coach_digests_user_kind_created_idx on public.coach_digests (user_id, kind, created_at desc);

alter table public.coach_digests enable row level security;
revoke all on public.coach_digests from anon, authenticated;
grant select on public.coach_digests to authenticated;
create policy coach_digests_select_own on public.coach_digests
  for select to authenticated using (user_id = (select auth.uid()));

-- {tier, allowed, reason: null | 'not_pro' | 'daily', used, limit}. Free users never get proactive comments.
create function public.coach_digest_allowance(p_user uuid, p_kind text, p_time_zone text default 'UTC')
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tz    text := case when exists (select 1 from pg_catalog.pg_timezone_names where name = p_time_zone)
                       then p_time_zone else 'UTC' end;
  v_start timestamptz := date_trunc('day', now() at time zone v_tz) at time zone v_tz;
  v_tier  text;
  v_limit integer := case p_kind when 'workout' then 10 when 'weekly' then 3 else 0 end;
  v_used  integer;
begin
  select coalesce((select e.tier from public.entitlements e
                    where e.user_id = p_user and (e.expires_at is null or e.expires_at > now())), 'free')
    into v_tier;
  select count(*) into v_used from public.coach_digests d
   where d.user_id = p_user and d.kind = p_kind and d.created_at >= v_start;
  if v_tier <> 'pro' then
    return jsonb_build_object('tier', v_tier, 'allowed', false, 'reason', 'not_pro', 'used', v_used, 'limit', v_limit);
  end if;
  if v_used >= v_limit then
    return jsonb_build_object('tier', v_tier, 'allowed', false, 'reason', 'daily', 'used', v_used, 'limit', v_limit);
  end if;
  return jsonb_build_object('tier', v_tier, 'allowed', true, 'reason', null, 'used', v_used, 'limit', v_limit);
end
$$;

revoke all on function public.coach_digest_allowance(uuid, text, text) from public, anon, authenticated;
grant execute on function public.coach_digest_allowance(uuid, text, text) to service_role;
