-- schema_27: give a coach message back when the turn produced nothing (provider error, timeout, dropped connection).
-- Only the daily count is lowered; the per-minute counter stays, so retries cannot be used to dodge the rate limit.
-- The day must still be the one the message was counted on, so a refund never reaches into a later day.

create or replace function public.coach_refund_quota(p_user uuid, p_time_zone text default 'UTC')
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_tz    text := case when exists (select 1 from pg_catalog.pg_timezone_names where name = p_time_zone)
                       then p_time_zone else 'UTC' end;
  v_today date := (now() at time zone v_tz)::date;
begin
  update public.coach_quota
     set messages = greatest(messages - 1, 0), updated_at = now()
   where user_id = p_user and day = v_today and messages > 0;
end
$$;

revoke all on function public.coach_refund_quota(uuid, text) from public, anon, authenticated;
grant execute on function public.coach_refund_quota(uuid, text) to service_role;
