-- P012 · Routines, workouts, sets, personal records: RLS, constraints, tree integrity, tombstone purge.
begin;
create extension if not exists pgtap with schema extensions;
select plan(69);

-- Fixtures (inserted as the superuser, i.e. like the service role).
insert into auth.users (id, instance_id, aud, role, email)
values
  ('00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'a@example.test'),
  ('00000000-0000-0000-0000-0000000000b2', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'b@example.test');

insert into public.exercises (id, level, category, primary_muscles)
values ('barbell_bench_press', 'beginner', 'strength', '{chest}'),
       ('pull_up', 'intermediate', 'strength', '{lats}');

-- Structure
select has_table('public', 'routines', 'routines exists');
select has_table('public', 'routine_days', 'routine_days exists');
select has_table('public', 'routine_exercises', 'routine_exercises exists');
select has_table('public', 'workouts', 'workouts exists');
select has_table('public', 'workout_exercises', 'workout_exercises exists');
select has_table('public', 'sets', 'sets exists');
select has_table('public', 'personal_records', 'personal_records exists');
select is((select count(*)::int from pg_class
           where oid in ('public.routines'::regclass, 'public.routine_days'::regclass, 'public.routine_exercises'::regclass,
                         'public.workouts'::regclass, 'public.workout_exercises'::regclass, 'public.sets'::regclass,
                         'public.personal_records'::regclass)
             and relrowsecurity), 7, 'RLS enabled on all 7 tables');
select has_index('public', 'workouts', 'workouts_user_id_started_at_idx', 'workouts: (user_id, started_at desc) index');
select has_index('public', 'sets', 'sets_workout_exercise_id_position_idx', 'sets: (workout_exercise_id, position) index');
select has_index('public', 'sets', 'sets_user_id_updated_at_idx', 'sets: (user_id, updated_at) index');
select col_type_is('public', 'sets', 'weight_kg', 'numeric(6,2)', 'sets.weight_kg is numeric(6,2)');

-- A full tree as user A.
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000a1","role":"authenticated"}', true);

select lives_ok($$
  insert into public.custom_exercises (id, user_id, name, primary_muscles)
  values ('50000000-0000-0000-0000-00000000000a', '00000000-0000-0000-0000-0000000000a1', 'My Curl', '{biceps}')
$$, 'owner can insert a custom exercise');
select lives_ok($$
  insert into public.routines (id, user_id, name) values
    ('60000000-0000-0000-0000-00000000000a', '00000000-0000-0000-0000-0000000000a1', 'Push Pull Legs')
$$, 'owner can insert a routine');
select lives_ok($$
  insert into public.routine_days (id, user_id, routine_id, position, name) values
    ('61000000-0000-0000-0000-00000000000a', '00000000-0000-0000-0000-0000000000a1', '60000000-0000-0000-0000-00000000000a', 0, 'Push')
$$, 'owner can insert a routine day');
select lives_ok($$
  insert into public.routine_exercises (id, user_id, routine_day_id, position, exercise_id, target_sets, target_reps_min, target_reps_max, target_rir, superset_group, rest_seconds) values
    ('62000000-0000-0000-0000-00000000000a', '00000000-0000-0000-0000-0000000000a1', '61000000-0000-0000-0000-00000000000a', 0, 'barbell_bench_press', 4, 6, 10, 2, null, 120),
    ('62000000-0000-0000-0000-00000000000b', '00000000-0000-0000-0000-0000000000a1', '61000000-0000-0000-0000-00000000000a', 1, 'pull_up', 3, 8, 12, 1, 1, 90)
$$, 'owner can insert routine exercises');

select lives_ok($$
  insert into public.workouts (id, user_id, routine_id, routine_day_id, name, started_at, ended_at, notes) values
    ('70000000-0000-0000-0000-00000000000a', '00000000-0000-0000-0000-0000000000a1', '60000000-0000-0000-0000-00000000000a',
     '61000000-0000-0000-0000-00000000000a', 'Push', '2026-11-10 18:00+00', '2026-11-10 19:05+00', 'felt strong')
$$, 'owner can insert a workout');
select lives_ok($$
  insert into public.workout_exercises (id, user_id, workout_id, position, exercise_id) values
    ('71000000-0000-0000-0000-00000000000a', '00000000-0000-0000-0000-0000000000a1', '70000000-0000-0000-0000-00000000000a', 0, 'barbell_bench_press'),
    ('71000000-0000-0000-0000-00000000000b', '00000000-0000-0000-0000-0000000000a1', '70000000-0000-0000-0000-00000000000a', 1, 'pull_up')
$$, 'owner can insert workout exercises');
select lives_ok($$
  insert into public.sets (id, user_id, workout_exercise_id, position, weight_kg, reps, rpe, rir, set_type, is_completed) values
    ('72000000-0000-0000-0000-00000000000a', '00000000-0000-0000-0000-0000000000a1', '71000000-0000-0000-0000-00000000000a', 0, 60, 10, null, null, 'warmup', true),
    ('72000000-0000-0000-0000-00000000000b', '00000000-0000-0000-0000-0000000000a1', '71000000-0000-0000-0000-00000000000a', 1, 100.25, 5, 8.5, 2, 'working', true),
    ('72000000-0000-0000-0000-00000000000c', '00000000-0000-0000-0000-0000000000a1', '71000000-0000-0000-0000-00000000000b', 0, 0, 12, 9, 1, 'failure', true)
$$, 'owner can insert sets');
select lives_ok($$
  insert into public.personal_records (id, user_id, exercise_id, kind, value, set_id, date) values
    ('73000000-0000-0000-0000-00000000000a', '00000000-0000-0000-0000-0000000000a1', 'barbell_bench_press', 'weight', 100.25, '72000000-0000-0000-0000-00000000000b', '2026-11-10'),
    ('73000000-0000-0000-0000-00000000000b', '00000000-0000-0000-0000-0000000000a1', 'barbell_bench_press', 'volume', 12345.5, null, '2026-11-10')
$$, 'owner can insert personal records');

select lives_ok($$
  insert into public.routine_exercises (id, user_id, routine_day_id, position, custom_exercise_id) values
    ('62000000-0000-0000-0000-00000000000c', '00000000-0000-0000-0000-0000000000a1', '61000000-0000-0000-0000-00000000000a', 2, '50000000-0000-0000-0000-00000000000a')
$$, 'routine exercise can reference a custom exercise');

-- The whole tree reads back in order.
select is((select string_agg(s.weight_kg::text || 'x' || s.reps, ',' order by we.position, s.position)
           from public.workouts w
           join public.workout_exercises we on we.workout_id = w.id
           join public.sets s on s.workout_exercise_id = we.id
           where w.id = '70000000-0000-0000-0000-00000000000a'),
          '60.00x10,100.25x5,0.00x12', 'workout tree reads back in position order');
select is((select count(*)::int from public.routine_exercises where routine_day_id = '61000000-0000-0000-0000-00000000000a'), 3,
          'routine tree reads back');
select is((select updated_at > created_at - interval '1 second' from public.sets where id = '72000000-0000-0000-0000-00000000000a'), true,
          'updated_at is maintained by trigger');

-- exercise_ref: exactly one of the two
select throws_ok($$
  insert into public.workout_exercises (id, user_id, workout_id, position, exercise_id, custom_exercise_id) values
    ('71000000-0000-0000-0000-0000000000f1', '00000000-0000-0000-0000-0000000000a1', '70000000-0000-0000-0000-00000000000a', 5,
     'pull_up', '50000000-0000-0000-0000-00000000000a')
$$, '23514', null, 'workout_exercises: both exercise refs rejected');
select throws_ok($$
  insert into public.workout_exercises (id, user_id, workout_id, position) values
    ('71000000-0000-0000-0000-0000000000f2', '00000000-0000-0000-0000-0000000000a1', '70000000-0000-0000-0000-00000000000a', 5)
$$, '23514', null, 'workout_exercises: no exercise ref rejected');
select throws_ok($$
  insert into public.routine_exercises (id, user_id, routine_day_id, position) values
    ('62000000-0000-0000-0000-0000000000f1', '00000000-0000-0000-0000-0000000000a1', '61000000-0000-0000-0000-00000000000a', 9)
$$, '23514', null, 'routine_exercises: no exercise ref rejected');
select throws_ok($$
  insert into public.personal_records (id, user_id, kind, value, date) values
    ('73000000-0000-0000-0000-0000000000f1', '00000000-0000-0000-0000-0000000000a1', 'weight', 10, '2026-11-10')
$$, '23514', null, 'personal_records: no exercise ref rejected');
select throws_ok($$
  insert into public.workout_exercises (id, user_id, workout_id, position, exercise_id) values
    ('71000000-0000-0000-0000-0000000000f3', '00000000-0000-0000-0000-0000000000a1', '70000000-0000-0000-0000-00000000000a', 5, 'no_such_exercise')
$$, '23503', null, 'workout_exercises: unknown catalog exercise rejected');

-- CHECK constraints on sets
select throws_ok($$ update public.sets set reps = 101 where id = '72000000-0000-0000-0000-00000000000a' $$,
  '23514', null, 'sets: reps > 100 rejected');
select throws_ok($$ update public.sets set reps = -1 where id = '72000000-0000-0000-0000-00000000000a' $$,
  '23514', null, 'sets: reps < 0 rejected');
select throws_ok($$ update public.sets set weight_kg = 1000.01 where id = '72000000-0000-0000-0000-00000000000a' $$,
  '23514', null, 'sets: weight > 1000 rejected');
select throws_ok($$ update public.sets set weight_kg = -1 where id = '72000000-0000-0000-0000-00000000000a' $$,
  '23514', null, 'sets: negative weight rejected');
select throws_ok($$ update public.sets set rpe = 0.5 where id = '72000000-0000-0000-0000-00000000000a' $$,
  '23514', null, 'sets: rpe < 1 rejected');
select throws_ok($$ update public.sets set rpe = 10.5 where id = '72000000-0000-0000-0000-00000000000a' $$,
  '23514', null, 'sets: rpe > 10 rejected');
select throws_ok($$ update public.sets set rir = 11 where id = '72000000-0000-0000-0000-00000000000a' $$,
  '23514', null, 'sets: rir > 10 rejected');
select throws_ok($$ update public.sets set rir = -1 where id = '72000000-0000-0000-0000-00000000000a' $$,
  '23514', null, 'sets: negative rir rejected');
select throws_ok($$ update public.sets set set_type = 'super' where id = '72000000-0000-0000-0000-00000000000a' $$,
  '23514', null, 'sets: unknown set_type rejected');
select lives_ok($$ update public.sets set weight_kg = 1000, reps = 100, rpe = 10, rir = 0 where id = '72000000-0000-0000-0000-00000000000a' $$,
  'sets: boundary values accepted');
select throws_ok($$ update public.workouts set ended_at = '2026-11-10 17:00+00' where id = '70000000-0000-0000-0000-00000000000a' $$,
  '23514', null, 'workouts: ended_at before started_at rejected');
select throws_ok($$ update public.routine_exercises set target_reps_min = 12, target_reps_max = 8 where id = '62000000-0000-0000-0000-00000000000a' $$,
  '23514', null, 'routine_exercises: inverted rep range rejected');
select throws_ok($$ update public.routine_exercises set target_rir = 11 where id = '62000000-0000-0000-0000-00000000000a' $$,
  '23514', null, 'routine_exercises: target_rir > 10 rejected');
select throws_ok($$ update public.personal_records set kind = 'speed' where id = '73000000-0000-0000-0000-00000000000a' $$,
  '23514', null, 'personal_records: unknown kind rejected');

-- Spoofing and cross-user references
select throws_ok($$
  insert into public.routines (id, user_id, name) values
    ('60000000-0000-0000-0000-0000000000ff', '00000000-0000-0000-0000-0000000000b2', 'Spoof')
$$, '42501', null, 'cannot insert a routine for another user');
select throws_ok($$
  update public.sets set user_id = '00000000-0000-0000-0000-0000000000b2' where id = '72000000-0000-0000-0000-00000000000a'
$$, '42501', null, 'cannot hand a set over to another user');

-- Hard delete is not permitted.
select throws_ok($$ delete from public.sets $$, '42501', null, 'sets: delete denied');
select throws_ok($$ delete from public.workouts $$, '42501', null, 'workouts: delete denied');

-- Soft delete is an update.
select lives_ok($$ update public.sets set deleted_at = now() where id = '72000000-0000-0000-0000-00000000000c' $$,
  'owner can soft-delete a set');
select is((select count(*)::int from public.sets where deleted_at is not null), 1, 'tombstones stay visible for sync');

-- User B: sees nothing, writes nothing, cannot attach children to A's parents.
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000b2","role":"authenticated"}', true);
select is((select count(*)::int from public.routines), 0, 'B cannot see routines');
select is((select count(*)::int from public.workouts), 0, 'B cannot see workouts');
select is((select count(*)::int from public.sets), 0, 'B cannot see sets');
select is((select count(*)::int from public.personal_records), 0, 'B cannot see personal records');
select lives_ok($$ update public.workouts set name = 'hacked' $$, 'B''s update of A''s workouts is a silent no-op');
select throws_ok($$
  insert into public.sets (id, user_id, workout_exercise_id, position) values
    ('72000000-0000-0000-0000-0000000000f1', '00000000-0000-0000-0000-0000000000b2', '71000000-0000-0000-0000-00000000000a', 9)
$$, '23503', null, 'B cannot attach a set to A''s workout exercise (composite FK)');
select throws_ok($$
  insert into public.workout_exercises (id, user_id, workout_id, position, custom_exercise_id) values
    ('71000000-0000-0000-0000-0000000000f4', '00000000-0000-0000-0000-0000000000b2', null, 0, '50000000-0000-0000-0000-00000000000a')
$$, '23502', null, 'workout_exercises: workout_id is required');

-- Anonymous
set local role anon;
select throws_ok($$ select * from public.workouts $$, '42501', null, 'anon cannot read workouts');
select throws_ok($$ select * from public.sets $$, '42501', null, 'anon cannot read sets');

-- Purge: callable by the service role only.
set local role authenticated;
select throws_ok($$ select * from public.purge_soft_deleted() $$, '42501', null, 'authenticated cannot call purge_soft_deleted');
reset role;
select is((select name from public.workouts where id = '70000000-0000-0000-0000-00000000000a'), 'Push', 'A''s workout was not modified by B');

-- Tombstones: one old set, one old workout with a child set, one recent set, one old but still-referenced custom exercise.
update public.sets set deleted_at = now() - interval '91 days' where id = '72000000-0000-0000-0000-00000000000c';
update public.sets set deleted_at = now() - interval '10 days' where id = '72000000-0000-0000-0000-00000000000a';
update public.workouts set deleted_at = now() - interval '120 days' where id = '70000000-0000-0000-0000-00000000000a';
update public.custom_exercises set deleted_at = now() - interval '200 days' where id = '50000000-0000-0000-0000-00000000000a';

set local role service_role;
select throws_ok($$ select * from public.purge_soft_deleted(interval '0 days') $$, '22023', null, 'purge rejects a retention under one day');
select is((select rows_deleted from public.purge_soft_deleted(interval '365 days') where table_name = 'workouts'), 0::bigint,
  'purge with a long retention deletes nothing');
select is((select rows_deleted from public.purge_soft_deleted() where table_name = 'sets'), 1::bigint, 'purge deletes the 91-day-old set');
reset role;
select is((select count(*)::int from public.workouts), 0, 'purge deleted the 120-day-old workout');
select is((select count(*)::int from public.workout_exercises), 0, 'purging a workout cascades to its exercises');
select is((select count(*)::int from public.sets), 0, 'purging a workout cascades to its sets (incl. recent tombstone)');
select is((select count(*)::int from public.personal_records where set_id is not null), 0, 'personal records survive with set_id cleared');
select is((select count(*)::int from public.personal_records), 2, 'personal records are kept');
select is((select count(*)::int from public.custom_exercises), 1, 'a custom exercise still referenced by a routine is not purged');

select * from finish();
rollback;
