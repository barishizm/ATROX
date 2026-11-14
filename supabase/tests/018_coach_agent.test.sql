-- P074–P077 · coach SQL: user context without identifiers, read tools under RLS, proposals' lookups, memory limit,
-- turn persistence, consent, atomic quota and the spend circuit breaker.
begin;
select plan(37);

select tests.create_two_users();

-- ===== Seed (superuser) =====
insert into public.exercises (id, equipment, level, category, primary_muscles, movement_pattern)
values ('barbell-bench-press', 'barbell', 'beginner', 'strength', '{chest}', 'horizontal_push'),
       ('goblet-squat', 'dumbbell', 'beginner', 'strength', '{quadriceps}', 'squat');
insert into public.exercise_translations (exercise_id, locale, name)
values ('barbell-bench-press', 'en', 'Barbell Bench Press'), ('barbell-bench-press', 'tr', 'Barbell Bench Press TR'),
       ('goblet-squat', 'en', 'Goblet Squat');

insert into public.profiles (id, user_id, first_name, last_name, birth_date, height_cm, experience, goal, weekly_frequency,
                             equipment_access, limitations)
values ('78000000-0000-0000-0000-00000000000a', tests.user_a(), 'Zeynep', 'Kaplanoglu', '1996-03-14', 168,
        'two_to_5_years', 'strength', 3, 'home_dumbbell', '{knee}');
insert into public.body_measurements (id, user_id, date, weight_kg)
values ('78000000-0000-0000-0000-00000000000b', tests.user_a(), current_date - 2, 61.5);
insert into public.routines (id, user_id, name) values ('78000000-0000-0000-0000-000000000100', tests.user_a(), 'Full body');
insert into public.routine_days (id, user_id, routine_id, position, name)
values ('78000000-0000-0000-0000-000000000101', tests.user_a(), '78000000-0000-0000-0000-000000000100', 0, 'A');
insert into public.routine_exercises (id, user_id, routine_day_id, position, exercise_id, target_sets, target_reps_min, target_reps_max)
values ('78000000-0000-0000-0000-000000000102', tests.user_a(), '78000000-0000-0000-0000-000000000101', 0, 'goblet-squat', 3, 8, 12);
insert into public.workouts (id, user_id, routine_id, started_at, ended_at)
values ('78000000-0000-0000-0000-000000000200', tests.user_a(), '78000000-0000-0000-0000-000000000100',
        now() - interval '1 day', now() - interval '1 day' + interval '50 minutes');
insert into public.workout_exercises (id, user_id, workout_id, position, exercise_id)
values ('78000000-0000-0000-0000-000000000201', tests.user_a(), '78000000-0000-0000-0000-000000000200', 0, 'barbell-bench-press');
insert into public.sets (id, user_id, workout_exercise_id, position, weight_kg, reps, set_type, is_completed)
values ('78000000-0000-0000-0000-000000000202', tests.user_a(), '78000000-0000-0000-0000-000000000201', 0, 20, 10, 'warmup', true),
       ('78000000-0000-0000-0000-000000000203', tests.user_a(), '78000000-0000-0000-0000-000000000201', 1, 50, 8, 'working', true),
       ('78000000-0000-0000-0000-000000000204', tests.user_a(), '78000000-0000-0000-0000-000000000201', 2, 52.5, 6, 'working', true);
insert into public.score_snapshots (id, user_id, scope, key, score, z, confidence, model_version, date)
values ('78000000-0000-0000-0000-000000000300', tests.user_a(), 'overall', 'overall', 63.6, 0.35, 'medium', 'v1', current_date - 3),
       ('78000000-0000-0000-0000-000000000301', tests.user_a(), 'exercise', 'barbell-bench-press', 58.2, 0.2, 'high', 'v1', current_date - 3);
insert into public.insights (id, user_id, kind, subject, severity, priority, action, payload, detected_at)
values ('78000000-0000-0000-0000-000000000400', tests.user_a(), 'plateau', 'barbell-bench-press', 'mild', 5, 'ask_coach',
        '{"weeks":4}', now());
insert into public.coach_memory (id, user_id, note) values ('78000000-0000-0000-0000-000000000500', tests.user_a(), 'Trains at home');

-- ===== P074 context =====
select tests.authenticate_as(tests.user_a());
select is((public.coach_user_context('en') -> 'profile' ->> 'age')::int,
  extract(year from age(current_date, '1996-03-14'::date))::int, 'context: age in whole years');
select ok(public.coach_user_context('en')::text !~* '(zeynep|kaplan|1996-03-14|example\.test|0000000000a1)',
  'context: no name, birth date, e-mail or user id');
select is(public.coach_user_context('en') -> 'overall' ->> 'score', '64', 'context: rounded overall score');
select is(public.coach_user_context('en') -> 'routine' ->> 'name', 'Full body', 'context: active routine = routine of the latest workout');
select is((public.coach_user_context('en') -> 'last_7_days' ->> 'sets')::int, 2, 'context: warm-ups are not counted');
select is(public.coach_user_context('en') -> 'memory', '["Trains at home"]'::jsonb, 'context: memory notes');

-- ===== P075 read tools =====
select is(jsonb_array_length(public.coach_recent_workouts(5, null, 'en')), 1, 'recent workouts: one workout');
select is(public.coach_recent_workouts(5, null, 'en') -> 0 ->> 'volume_kg', '715', 'recent workouts: working volume in kg');
select is(public.coach_recent_workouts(5, null, 'en') -> 0 ->> 'duration_min', '50', 'recent workouts: duration in minutes');
select is(public.coach_exercise_history('barbell-bench-press', 8, 'tr') -> 'exercise' ->> 'name', 'Barbell Bench Press TR',
  'history: localized name');
select is(public.coach_exercise_history('barbell-bench-press', 8, 'en') -> 'sessions' -> 0 -> 'top_set',
  '{"kg": 52.5, "reps": 6}'::jsonb, 'history: heaviest working set per session');
select is(public.coach_exercise_history('no-such-lift', 8, 'en'), null, 'history: unknown exercise → null');
select is(public.coach_scores('all', 'en') ->> 'stale', 'true', 'scores: older than the latest workout → stale');
select is(jsonb_array_length(public.coach_scores('exercise', 'en') -> 'items'), 1, 'scores: scope filter');
select is(public.coach_insights() -> 0 ->> 'kind', 'plateau', 'insights: active insight');
select is(public.coach_routine(null, 'en') -> 'days' -> 0 -> 'exercises' -> 0 ->> 'reps', '8-12', 'routine: rep range');
select is(public.coach_weekly_volume(4) -> 0 -> 'sets' ->> 'chest', '2', 'weekly volume: sets per primary muscle');

select tests.authenticate_as(tests.user_b());
select is(public.coach_user_context('en') -> 'profile', 'null'::jsonb, 'B: no profile of A in the context');
select is(public.coach_recent_workouts(5, null, 'en'), '[]'::jsonb, 'B: no workouts of A');
select is(public.coach_scores('all', 'en') -> 'items', '[]'::jsonb, 'B: no scores of A');
select is(public.coach_insights(), '[]'::jsonb, 'B: no insights of A');
select is(public.coach_routine('78000000-0000-0000-0000-000000000100', 'en'), null, 'B: cannot read A''s routine by id');
select is(public.coach_weekly_volume(4), '[]'::jsonb, 'B: no volume of A');

-- ===== P076 lookups, memory, turns =====
select tests.authenticate_as(tests.user_a());
select is(jsonb_array_length(public.coach_lookup_exercises(array['goblet-squat', 'nope'], 'en')), 1,
  'lookup: only existing exercises come back');
select lives_ok($$ select public.coach_save_memory('78000000-0000-0000-0000-000000000501', '  Left knee: no deep squats ') $$,
  'save_memory: stores a trimmed note');
insert into public.coach_memory (id, user_id, note)
select ('78000000-0000-0000-0000-0000000006' || lpad(i::text, 2, '0'))::uuid, tests.user_a(), 'note ' || i
from generate_series(1, 18) i;
select throws_ok($$ select public.coach_save_memory('78000000-0000-0000-0000-000000000599', 'one too many') $$,
  'P0001', 'coach_memory_full', 'save_memory: at most 20 notes');
select lives_ok($$ select public.coach_save_turn('78000000-0000-0000-0000-000000000700', 'Bench', '[
  {"id":"78000000-0000-0000-0000-000000000701","role":"user","content":"How is my bench?"},
  {"id":"78000000-0000-0000-0000-000000000702","role":"assistant","content":"","tool_calls":[{"id":"c1","type":"function","function":{"name":"get_exercise_history","arguments":"{}"}}]},
  {"id":"78000000-0000-0000-0000-000000000703","role":"tool","content":"{}"},
  {"id":"78000000-0000-0000-0000-000000000704","role":"assistant","content":"Up 5 kg.","prompt_tokens":10,"completion_tokens":4}
]'::jsonb) $$, 'save_turn: thread and messages in one call');
select is(public.coach_thread_history('78000000-0000-0000-0000-000000000700', 12) -> 'messages',
  '[{"role":"user","content":"How is my bench?"},{"role":"assistant","content":"Up 5 kg."}]'::jsonb,
  'history: user/assistant messages in order, tool traces left out');
select is(public.coach_thread_history('78000000-0000-0000-0000-000000000700', 12) ->> 'last_turn_complete', 'true',
  'history: last turn complete');
select tests.authenticate_as(tests.user_b());
select is(public.coach_thread_history('78000000-0000-0000-0000-000000000700', 12) -> 'messages', '[]'::jsonb,
  'B: cannot read A''s thread');

-- ===== P077 consent, quota, circuit breaker =====
select is(public.coach_has_ai_consent('2026-11'), false, 'consent: none → false');
insert into public.consents (id, user_id, kind, version, granted)
values ('78000000-0000-0000-0000-000000000800', tests.user_b(), 'ai_sharing', '2026-11', true);
select is(public.coach_has_ai_consent('2026-11'), true, 'consent: granted for the current version');
select throws_ok($$ select public.coach_consume_quota(tests.user_b(), 'UTC') $$, '42501', null,
  'quota: users cannot call the counter');

select tests.clear_authentication();
-- free tier: 5 messages a day; requests per minute raised so the daily limit is what stops the 6th
update public.coach_limits set requests_per_minute = 50 where tier = 'free';
update public.coach_limits set requests_per_minute = 2 where tier = 'pro';
insert into public.entitlements (user_id, tier, source) values (tests.user_a(), 'pro', 'manual');
insert into public.coach_usage (user_id, provider, model, cost_usd) values (tests.user_a(), 'fake', 'm', 1.5);
set local role service_role;
select is(
  (select array_agg((public.coach_consume_quota(tests.user_b(), 'Europe/Istanbul') ->> 'allowed')::boolean order by i)
     from generate_series(1, 6) i),
  array[true, true, true, true, true, false], 'quota: the sixth free message of the day is refused');
select is(
  (select array_agg(public.coach_consume_quota(tests.user_a(), 'Not/AZone') ->> 'reason' order by i)
     from generate_series(1, 3) i),
  array[null, null, 'rate_minute'], 'quota: per-minute limit, unknown time zone falls back to UTC');
select is(public.coach_consume_quota(tests.user_a(), 'UTC') ->> 'tier', 'pro', 'quota: entitlement gives the pro tier');
select is(public.coach_spend_today(), 1.5::numeric, 'circuit breaker: today''s total spend');
reset role;

select * from finish();
rollback;
