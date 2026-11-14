-- P100 · Operations dashboards and alert checks over coach_usage / coach_quota. Service role only: these views
-- aggregate every user, so nothing here is granted to anon or authenticated. They read no message content.

-- Daily active coach users, cost per message, provider error rate, quota-hit rate.
create view public.ops_coach_daily
with (security_invoker = true) as
select
  (created_at at time zone 'UTC')::date                                         as day,
  count(distinct user_id)                                                       as active_users,
  count(*)                                                                      as requests,
  count(*) filter (where status = 'ok')                                         as ok_requests,
  coalesce(sum(cost_usd), 0)                                                    as cost_usd,
  coalesce(sum(cost_usd) filter (where status = 'ok'), 0)
    / nullif(count(*) filter (where status = 'ok'), 0)                          as cost_usd_per_message,
  count(*) filter (where status in ('error', 'timeout'))::numeric
    / nullif(count(*), 0)                                                       as provider_error_rate,
  count(*) filter (where status = 'rate_limited')::numeric
    / nullif(count(*), 0)                                                       as quota_hit_rate,
  percentile_cont(0.95) within group (order by latency_ms)                      as p95_latency_ms
from public.coach_usage
group by 1;

-- Which provider/model served how much (model version distribution).
create view public.ops_coach_model_mix
with (security_invoker = true) as
select
  (created_at at time zone 'UTC')::date as day,
  provider,
  model,
  count(*)                              as requests,
  coalesce(sum(cost_usd), 0)            as cost_usd
from public.coach_usage
group by 1, 2, 3;

revoke all on public.ops_coach_daily, public.ops_coach_model_mix from anon, authenticated;

-- Thresholds the scheduled check compares against. Edit the rows to tune; no redeploy needed.
create table public.ops_alert_thresholds (
  name       text primary key,
  threshold  numeric not null,
  note       text not null default '',
  constraint ops_alert_thresholds_value_check check (threshold >= 0)
);
insert into public.ops_alert_thresholds (name, threshold, note) values
  ('daily_cost_usd', 25,        'LLM spend per UTC day'),
  ('error_rate_1h',  0.15,      'share of coach requests that errored or timed out in the last hour'),
  ('error_rate_min_requests', 20, 'ignore the error rate below this many requests in the hour');
alter table public.ops_alert_thresholds enable row level security;
revoke all on public.ops_alert_thresholds from anon, authenticated;
-- Explicit deny-all so the RLS audit (001_rls_audit) sees a stated intent; clients have no grants anyway.
create policy ops_alert_thresholds_no_client_access on public.ops_alert_thresholds
  for select to authenticated using (false);

-- Returns one row per breached alert (empty = healthy). Schedule it with pg_cron / a scheduled Edge Function and
-- notify when it returns rows (docs/ANALITIK.md).
create function public.ops_alerts()
returns table (alert text, value numeric, threshold numeric)
language sql
stable
security invoker
set search_path = ''
as $$
  with cost as (
    select coalesce(sum(cost_usd), 0) as v
    from public.coach_usage
    where created_at >= date_trunc('day', now() at time zone 'UTC') at time zone 'UTC'
  ), errors as (
    select count(*) as total,
           count(*) filter (where status in ('error', 'timeout')) as failed
    from public.coach_usage
    where created_at >= now() - interval '1 hour'
  )
  select 'daily_cost_usd', cost.v, t.threshold
  from cost join public.ops_alert_thresholds t on t.name = 'daily_cost_usd'
  where cost.v > t.threshold
  union all
  select 'error_rate_1h', errors.failed::numeric / errors.total, t.threshold
  from errors
  join public.ops_alert_thresholds t on t.name = 'error_rate_1h'
  join public.ops_alert_thresholds m on m.name = 'error_rate_min_requests'
  where errors.total >= m.threshold and errors.failed::numeric / errors.total > t.threshold;
$$;
revoke all on function public.ops_alerts() from public, anon, authenticated;
grant execute on function public.ops_alerts() to service_role;
