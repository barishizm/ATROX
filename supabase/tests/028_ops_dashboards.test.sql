-- P100 · ops dashboards: invisible to client roles, correct aggregates, alerts fire on thresholds.
begin;
select plan(9);

select tests.create_two_users();

insert into public.coach_usage (user_id, provider, model, cost_usd, latency_ms, status, created_at) values
  (tests.user_a(), 'deepseek', 'deepseek-flash', 0.010, 800,  'ok',           now()),
  (tests.user_a(), 'deepseek', 'deepseek-flash', 0.030, 1200, 'ok',           now()),
  (tests.user_b(), 'deepseek', 'deepseek-flash', 0.000, 100,  'error',        now()),
  (tests.user_b(), 'deepseek', 'deepseek-flash', 0.000, 5,    'rate_limited', now());

select is((select active_users from public.ops_coach_daily where day = (now() at time zone 'UTC')::date), 2::bigint,
  'daily: two distinct coach users');
select is((select requests from public.ops_coach_daily where day = (now() at time zone 'UTC')::date), 4::bigint,
  'daily: four requests');
select is((select round(cost_usd_per_message, 3) from public.ops_coach_daily where day = (now() at time zone 'UTC')::date), 0.020,
  'daily: cost per successful message');
select is((select provider_error_rate from public.ops_coach_daily where day = (now() at time zone 'UTC')::date), 0.25,
  'daily: provider error rate');
select is((select quota_hit_rate from public.ops_coach_daily where day = (now() at time zone 'UTC')::date), 0.25,
  'daily: quota hit rate');
select is((select requests from public.ops_coach_model_mix where model = 'deepseek-flash' limit 1), 4::bigint,
  'model mix: counts per model');

-- Alerts: spend under the threshold and too few requests for the error rate stay quiet.
select is((select count(*) from public.ops_alerts()), 0::bigint, 'alerts: healthy by default');
update public.ops_alert_thresholds set threshold = 0.01 where name = 'daily_cost_usd';
select is((select alert from public.ops_alerts()), 'daily_cost_usd', 'alerts: spend over the threshold fires');

select tests.authenticate_as(tests.user_a());
select throws_ok($$ select * from public.ops_coach_daily $$, '42501', null, 'client roles cannot read the dashboards');
select tests.clear_authentication();

select * from finish();
rollback;
