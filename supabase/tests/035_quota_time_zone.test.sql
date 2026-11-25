-- Daily allowances count the day in a time zone kept per user (audit D39): switching zones per request cannot reset them.
begin;
select plan(10);
select tests.create_two_users();

select tests.authenticate_as(tests.user_a());
select throws_ok($$ select public.quota_time_zone(tests.user_a(), 'UTC') $$, '42501', null,
  'users cannot call quota_time_zone');
select tests.clear_authentication();

-- Free coach: 5 a day; per-minute limit raised so the daily limit is what stops the 6th.
update public.coach_limits set requests_per_minute = 50 where tier = 'free';
set local role service_role;

select is(
  (select array_agg((public.coach_consume_quota(tests.user_a(), 'Pacific/Kiritimati') ->> 'allowed')::boolean order by i)
     from generate_series(1, 5) i),
  array[true, true, true, true, true], 'five free messages in the first zone');
select is((select time_zone from public.coach_quota where user_id = tests.user_a()), 'Pacific/Kiritimati',
  'the first zone is kept');
select is(public.coach_consume_quota(tests.user_a(), 'Etc/GMT+12') ->> 'reason', 'daily',
  'a zone 26 hours away does not reset the day');
select is((select time_zone from public.coach_quota where user_id = tests.user_a()), 'Pacific/Kiritimati',
  'the kept zone stays within 24 hours');

-- Travel: a day after the last change, the new zone is taken (its date differs, so the counter starts over).
reset role;
update public.coach_quota set time_zone_changed_at = now() - interval '25 hours' where user_id = tests.user_a();
set local role service_role;
select is((public.coach_consume_quota(tests.user_a(), 'Etc/GMT+12') ->> 'allowed')::boolean, true,
  'a new zone is accepted after 24 hours');
select is((select time_zone from public.coach_quota where user_id = tests.user_a()), 'Etc/GMT+12',
  'the new zone is kept');

-- Food: free 3 a day, counted in the kept zone.
select is(
  (select array_agg((public.food_consume(tests.user_b(), 'photo', 'Pacific/Kiritimati') ->> 'allowed')::boolean order by i)
     from generate_series(1, 3) i),
  array[true, true, true], 'three free analyses');
select is(public.food_consume(tests.user_b(), 'photo', 'Etc/GMT+12') ->> 'reason', 'daily',
  'another zone does not open a new food day');

-- Unknown zones count as UTC and are kept as such.
delete from public.coach_quota where user_id = tests.user_b();
select is(public.quota_time_zone(tests.user_b(), 'Mars/Olympus'), 'UTC', 'unknown zone falls back to UTC');
reset role;

select * from finish();
rollback;
