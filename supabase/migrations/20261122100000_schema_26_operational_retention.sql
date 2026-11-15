-- D243(2): retention for operational records that no user owns a copy of, and D178: the coach provider list.
-- Decision (owner delegated, 2026-11-15): moderation reports are kept 365 days, App Store event logs 730 days
-- (billing audit trail), social rate-limit windows 2 days. Nothing here touches user-owned tables.

create or replace function public.purge_operational_logs()
returns table (table_name text, rows_deleted bigint)
language plpgsql
set search_path = ''
as $$
declare
  n bigint;
begin
  with d as (delete from public.reports where created_at < now() - interval '365 days' returning 1)
    select count(*) into n from d;
  table_name := 'reports'; rows_deleted := n; return next;

  with d as (delete from billing.app_store_events where received_at < now() - interval '730 days' returning 1)
    select count(*) into n from d;
  table_name := 'app_store_events'; rows_deleted := n; return next;

  with d as (delete from public.social_rate_limits where window_start < now() - interval '2 days' returning 1)
    select count(*) into n from d;
  table_name := 'social_rate_limits'; rows_deleted := n; return next;
end;
$$;

revoke all on function public.purge_operational_logs() from public, anon, authenticated;
grant execute on function public.purge_operational_logs() to service_role;

do $cron$
begin
  if exists (select 1 from pg_available_extensions where name = 'pg_cron') then
    create extension if not exists pg_cron;
    perform cron.unschedule(jobid) from cron.job where jobname = 'purge-operational-logs';
    perform cron.schedule('purge-operational-logs', '45 3 * * *', 'select public.purge_operational_logs()');
  end if;
end
$cron$;

-- D178: OpenRouter was removed (decision #9); only the official DeepSeek API (and the test double) remain.
-- NOT VALID keeps any historical row while enforcing the list for every new one.
alter table public.coach_usage drop constraint coach_usage_provider_check;
alter table public.coach_usage add constraint coach_usage_provider_check check (provider in ('deepseek', 'fake')) not valid;
