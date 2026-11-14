-- P083 · coach_digests (owner-readable, service-written) and coach_digest_allowance (Pro only, per-kind daily count).
begin;
select plan(11);

select tests.create_two_users();

insert into public.coach_digests (user_id, kind, locale, input_hash, body)
values (tests.user_a(), 'weekly', 'en', 'h1', 'Nice week.'),
       (tests.user_b(), 'weekly', 'en', 'h1', 'Other user.');

select tests.authenticate_as(tests.user_a());
select is((select count(*) from public.coach_digests), 1::bigint, 'digests: the owner sees only their own');
select tests.clear_authentication();

select throws_ok(
  $$insert into public.coach_digests (user_id, kind, locale, input_hash, body)
    values ('00000000-0000-0000-0000-00000000000f', 'workout', 'en', 'x', 'dup')$$,
  '23503', null, 'digests: needs a real user');
select throws_ok(
  $$insert into public.coach_digests (user_id, kind, locale, input_hash, body)
    select tests.user_a(), 'weekly', 'en', 'h1', 'same input again'$$,
  '23505', null, 'digests: one comment per (user, kind, locale, input)');
select throws_ok(
  $$insert into public.coach_digests (user_id, kind, locale, input_hash, body)
    select tests.user_a(), 'monthly', 'en', 'h2', 'bad kind'$$,
  '23514', null, 'digests: unknown kind is rejected');

-- Allowance (service role only).
select is(public.coach_digest_allowance(tests.user_a(), 'workout', 'UTC') ->> 'reason', 'not_pro',
  'allowance: free users get no proactive comments');
insert into public.entitlements (user_id, tier, source) values (tests.user_a(), 'pro', 'manual');
select is((public.coach_digest_allowance(tests.user_a(), 'workout', 'Europe/Istanbul') ->> 'allowed')::boolean, true,
  'allowance: Pro may generate');
insert into public.coach_digests (user_id, kind, locale, input_hash, body)
select tests.user_a(), 'workout', 'en', 'w' || g, 'c' from generate_series(1, 10) g;
select is(public.coach_digest_allowance(tests.user_a(), 'workout', 'UTC') ->> 'reason', 'daily',
  'allowance: 10 workout comments a day, then stop');
select is((public.coach_digest_allowance(tests.user_a(), 'weekly', 'UTC') ->> 'allowed')::boolean, true,
  'allowance: the weekly kind is counted separately');
select is(public.coach_digest_allowance(tests.user_b(), 'workout', 'UTC') ->> 'reason', 'not_pro',
  'allowance: another user is unaffected');
select is(public.coach_digest_allowance(tests.user_a(), 'workout', 'Not/AZone') ->> 'tier', 'pro',
  'allowance: an unknown time zone falls back to UTC');

select tests.authenticate_as(tests.user_a());
select throws_ok($$select public.coach_digest_allowance(tests.user_a(), 'workout', 'UTC')$$, '42501', null,
  'allowance: the app cannot call it');
select * from finish();
rollback;
