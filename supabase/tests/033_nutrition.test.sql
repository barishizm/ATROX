-- Food tracking: constraints, consent function, daily allowance.
begin;
select plan(16);
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

-- Allowance: free 3/day.
select is((public.food_allowance(tests.user_a(), 'UTC') ->> 'limit')::int, 3, 'free limit is 3');
insert into public.food_analyses (user_id, kind) select tests.user_a(), 'photo' from generate_series(1, 3);
select is((public.food_allowance(tests.user_a(), 'UTC') ->> 'allowed')::boolean, false, 'free user is stopped after 3');
insert into public.entitlements (user_id, tier) values (tests.user_a(), 'pro');
select is((public.food_allowance(tests.user_a(), 'UTC') ->> 'limit')::int, 60, 'pro limit is 60');

-- Coach summary: own rows only, grouped per day, entry names not exposed.
select tests.authenticate_as(tests.user_a());
select is(jsonb_array_length(public.coach_nutrition_summary(7, 'UTC') -> 'days'), 1, 'summary has today only');
select is((public.coach_nutrition_summary(7, 'UTC') -> 'days' -> 0 ->> 'calories')::int, 221, 'summary sums the day (220.5 rounds to 221)');
select is(public.coach_nutrition_summary(7, 'UTC') -> 'target' ->> 'calories', '2400', 'summary carries the target');
select tests.clear_authentication();

select * from finish();
rollback;
