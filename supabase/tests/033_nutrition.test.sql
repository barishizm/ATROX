-- Food tracking: constraints, consent function, daily allowance.
begin;
select plan(21);
select tests.create_two_users();

select tests.authenticate_as(tests.user_a());
select lives_ok(
  $$insert into public.food_entries (id, user_id, eaten_at, meal, name, calories, protein_g, carbs_g, fat_g, source)
    values (gen_random_uuid(), tests.user_a(), now(), 'lunch', 'Lentil soup', 220.5, 12, 30, 5, 'photo')$$,
  'owner can log a food entry');
select throws_ok(
  $$insert into public.food_entries (id, user_id, eaten_at, meal, name, calories, source)
    values (gen_random_uuid(), tests.user_a(), now(), 'brunch', 'x', 1, 'photo')$$,
  '23514', null, 'unknown meal rejected');
select throws_ok(
  $$insert into public.food_entries (id, user_id, eaten_at, meal, name, calories, source)
    values (gen_random_uuid(), tests.user_a(), now(), 'lunch', 'x', -1, 'photo')$$,
  '23514', null, 'negative calories rejected');
select throws_ok(
  $$insert into public.food_entries (id, user_id, eaten_at, meal, name, calories, source, items)
    values (gen_random_uuid(), tests.user_a(), now(), 'lunch', 'x', 1, 'photo', '{"a":1}')$$,
  '23514', null, 'items must be a JSON array');
select lives_ok(
  $$insert into public.nutrition_targets (id, user_id, mode, calories, protein_g, carbs_g, fat_g)
    values (gen_random_uuid(), tests.user_a(), 'auto', 2400, 160, 280, 70)$$,
  'owner can set a target');
select throws_ok(
  $$insert into public.nutrition_targets (id, user_id, mode, calories, protein_g, carbs_g, fat_g)
    values (gen_random_uuid(), tests.user_a(), 'manual', 2000, 100, 200, 60)$$,
  '23505', null, 'one target row per user');
select throws_ok(
  $$update public.nutrition_targets set calories = 300 where user_id = tests.user_a()$$,
  '23514', null, 'a target below 800 kcal is rejected');
select tests.clear_authentication();

-- Consent function.
select tests.authenticate_as(tests.user_a());
select is(public.food_has_consent('2026-11'), false, 'no consent by default');
insert into public.consents (id, user_id, kind, version, granted)
  values (gen_random_uuid(), tests.user_a(), 'food_ai_sharing', '2026-11', true);
select is(public.food_has_consent('2026-11'), true, 'granted consent for the current version');
select is(public.food_has_consent('2027-01'), false, 'other version needs a new consent');
select tests.clear_authentication();

-- Consuming the allowance: free 3/day, 6/minute, refunds, Pro 60/day.
select is((public.food_consume(tests.user_a(), 'photo', 'UTC') ->> 'allowed')::boolean, true, 'first analysis allowed');
select is((public.food_consume(tests.user_a(), 'photo', 'UTC') ->> 'used')::int, 2, 'second one counts');
select is(public.food_consume(tests.user_a(), 'text', 'UTC') ->> 'limit', '3', 'free limit is 3');
select is(public.food_consume(tests.user_a(), 'photo', 'UTC') ->> 'reason', 'daily', 'a 4th free analysis is stopped');
select lives_ok(
  $$select public.food_refund((select id from public.food_analyses where user_id = tests.user_a() limit 1))$$,
  'a refund removes one row');
select is((public.food_consume(tests.user_a(), 'photo', 'UTC') ->> 'allowed')::boolean, true, 'refunded analysis can be used again');
insert into public.entitlements (user_id, tier) values (tests.user_a(), 'pro');
delete from public.food_analyses where user_id = tests.user_a();
insert into public.food_analyses (user_id, kind) select tests.user_a(), 'photo' from generate_series(1, 6);
select is(public.food_consume(tests.user_a(), 'photo', 'UTC') ->> 'reason', 'rate', 'more than 6 in a minute is a rate limit, even for Pro');
update public.food_analyses set created_at = now() - interval '5 minutes' where user_id = tests.user_a();
select is(public.food_consume(tests.user_a(), 'photo', 'UTC') ->> 'limit', '60', 'pro limit is 60');

-- Coach summary: own rows only, grouped per day, entry names not exposed.
select tests.authenticate_as(tests.user_a());
select is(jsonb_array_length(public.coach_nutrition_summary(7, 'UTC') -> 'days'), 1, 'summary has today only');
select is((public.coach_nutrition_summary(7, 'UTC') -> 'days' -> 0 ->> 'calories')::int, 221, 'summary sums the day (220.5 rounds to 221)');
select is(public.coach_nutrition_summary(7, 'UTC') -> 'target' ->> 'calories', '2400', 'summary carries the target');
select tests.clear_authentication();

select * from finish();
rollback;
