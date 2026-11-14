-- P093 · ml_contributions: anonymous (no user column), invisible and unwritable for client roles.
begin;
select plan(11);

select tests.create_two_users();

select is((select count(*)::int from information_schema.columns
  where table_schema = 'public' and table_name = 'ml_contributions' and column_name ilike '%user%'), 0,
  'no user column on ml_contributions');
select is((select count(*)::int from pg_constraint c where c.conrelid = 'public.ml_contributions'::regclass and c.contype = 'f'), 0,
  'no foreign key links the table to any other');

insert into public.ml_contributions (contribution_key, sex, age_band, bodyweight_kg, height_band, experience_band, frequency_band,
  month, exercise_id, best_e1rm_kg, best_set_reps, sessions_in_month, model_version)
values ('0b6f1c1e-5d3a-4f7e-9a41-6c1d2e3f4a5b', 'female', 30, 64, 165, 'two_to_5_years', '3-4', '2026-11', 'barbell-bench-press', 62.5, 5, 6, 'v1');

select throws_ok($$ insert into public.ml_contributions (contribution_key, sex, age_band, bodyweight_kg, height_band, experience_band,
  frequency_band, month, exercise_id, best_e1rm_kg, best_set_reps, sessions_in_month, model_version)
  values ('0b6f1c1e-5d3a-4f7e-9a41-6c1d2e3f4a5b', 'female', 30, 64, 165, 'two_to_5_years', '3-4', '2026-11', 'barbell-bench-press', 63, 5, 6, 'v1') $$,
  '23505', null, 'one row per (key, month, exercise)');
select throws_ok($$ insert into public.ml_contributions (contribution_key, sex, age_band, bodyweight_kg, height_band, experience_band,
  frequency_band, month, exercise_id, best_e1rm_kg, best_set_reps, sessions_in_month, model_version)
  values (gen_random_uuid(), 'female', 33, 64, 165, 'two_to_5_years', '3-4', '2026-11', 'x', 63, 5, 6, 'v1') $$,
  '23514', null, 'age must be a 5-year band');
select throws_ok($$ insert into public.ml_contributions (contribution_key, sex, age_band, bodyweight_kg, height_band, experience_band,
  frequency_band, month, exercise_id, best_e1rm_kg, best_set_reps, sessions_in_month, model_version)
  values (gen_random_uuid(), 'female', 30, 64, 165, 'two_to_5_years', '3-4', '2026-11', 'x', 5000, 5, 6, 'v1') $$,
  '23514', null, 'e1RM is bounded');

select tests.authenticate_as(tests.user_a());
select throws_ok($$ select * from public.ml_contributions $$, '42501', null, 'authenticated cannot read');
select throws_ok($$ insert into public.ml_contributions (contribution_key, sex, age_band, bodyweight_kg, height_band, experience_band,
  frequency_band, month, exercise_id, best_e1rm_kg, best_set_reps, sessions_in_month, model_version)
  values (gen_random_uuid(), 'female', 30, 64, 165, 'two_to_5_years', '3-4', '2026-11', 'y', 60, 5, 6, 'v1') $$,
  '42501', null, 'authenticated cannot write');
reset role;

set local role anon;
select throws_ok($$ select * from public.ml_contributions $$, '42501', null, 'anon cannot read');
reset role;

select is((select count(*)::int from public.ml_contributions), 1, 'the service side sees the row');
select is((with d as (delete from public.ml_contributions where contribution_key = '0b6f1c1e-5d3a-4f7e-9a41-6c1d2e3f4a5b' returning 1)
  select count(*)::int from d), 1, 'delete by key removes the rows');

select * from finish();
rollback;
