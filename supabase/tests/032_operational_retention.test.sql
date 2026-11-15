-- D243(2) · purge_operational_logs removes old reports / App Store events / rate-limit windows and keeps recent ones.
begin;
select plan(6);

select tests.create_two_users();

insert into public.reports (reporter_id, reported_id, reason, created_at) values
  (tests.user_a(), tests.user_b(), 'spam', now() - interval '400 days'),
  (tests.user_a(), tests.user_b(), 'spam', now() - interval '10 days');
insert into billing.app_store_events (source, matched, received_at) values
  ('notification', false, now() - interval '800 days'),
  ('notification', false, now() - interval '5 days');
insert into public.social_rate_limits (user_id, bucket, window_start) values
  (tests.user_a(), 'search', now() - interval '3 days'),
  (tests.user_b(), 'search', now());

select * from public.purge_operational_logs();

select is((select count(*)::int from public.reports where reporter_id = tests.user_a()), 1, 'old report purged, recent kept');
select is((select count(*)::int from billing.app_store_events), 1, 'old App Store event purged, recent kept');
select is((select count(*)::int from public.social_rate_limits where bucket = 'search'), 1, 'stale rate-limit window purged');
select ok(not has_function_privilege('authenticated', 'public.purge_operational_logs()', 'execute'), 'clients cannot run the purge');
select ok(has_function_privilege('service_role', 'public.purge_operational_logs()', 'execute'), 'service role can run the purge');
select throws_ok($$ insert into public.coach_usage (user_id, provider, model) values (tests.user_a(), 'openrouter', 'x') $$,
  '23514', null, 'openrouter is no longer an accepted provider');

select * from finish();
rollback;
