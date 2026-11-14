-- P074 · coach_user_context(): the facts behind the coach's user summary (docs/04-AI-KOC.md §4).
--
-- SECURITY INVOKER: the coach-chat function calls it with the user's own JWT, so RLS limits every read to the caller.
-- Deliberately left out: first/last name, e-mail, user id, birth date (only the age in whole years), friends.
-- Free text the user typed (routine names, the limitation note, memory notes) is returned as is; the Edge Function
-- wraps it in data delimiters before it reaches the model.
create function public.coach_user_context(p_locale text default 'en')
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  with me as (
    select (select auth.uid()) as uid
  ),
  settings as (
    select coalesce((select s.reference_group from public.user_settings s
                      where s.user_id = (select uid from me) and s.deleted_at is null limit 1), 'gym') as reference_group
  ),
  profile as (
    select extract(year from age(current_date, p.birth_date))::int as age,
           p.sex, p.height_cm, p.experience, p.goal, p.weekly_frequency, p.equipment_access, p.limitations
    from public.profiles p
    where p.user_id = (select uid from me) and p.deleted_at is null
    limit 1
  ),
  weight as (
    select b.weight_kg, b.date
    from public.body_measurements b
    where b.user_id = (select uid from me) and b.deleted_at is null
    order by b.date desc, b.updated_at desc
    limit 1
  ),
  latest_scores as (
    select distinct on (s.scope, s.key) s.scope, s.key, s.score, s.confidence, s.date
    from public.score_snapshots s
    where s.user_id = (select uid from me) and s.deleted_at is null
      and s.reference_group = (select reference_group from settings)
    order by s.scope, s.key, s.date desc, s.updated_at desc
  ),
  exercise_scores as (
    select ls.key, ls.score, ls.confidence,
           coalesce(tl.name, ten.name, ls.key) as name
    from latest_scores ls
    left join public.exercise_translations tl on tl.exercise_id = ls.key and tl.locale = p_locale
    left join public.exercise_translations ten on ten.exercise_id = ls.key and ten.locale = 'en'
    where ls.scope = 'exercise'
  ),
  last_workout as (
    select w.started_at, w.routine_id
    from public.workouts w
    where w.user_id = (select uid from me) and w.deleted_at is null
    order by w.started_at desc
    limit 1
  ),
  active_routine as (
    select r.id, r.name
    from public.routines r
    where r.user_id = (select uid from me) and r.deleted_at is null
    order by (r.id = (select lw.routine_id from last_workout lw)) desc nulls last, r.updated_at desc
    limit 1
  ),
  routine_days as (
    select d.position, d.name,
           (select count(*) from public.routine_exercises e
             where e.routine_day_id = d.id and e.deleted_at is null)::int as exercise_count
    from public.routine_days d
    where d.routine_id = (select id from active_routine) and d.deleted_at is null
  ),
  week as (
    select w.id
    from public.workouts w
    where w.user_id = (select uid from me) and w.deleted_at is null
      and w.started_at >= now() - interval '7 days'
  ),
  week_sets as (
    select s.weight_kg, s.reps
    from public.sets s
    join public.workout_exercises we on we.id = s.workout_exercise_id and we.deleted_at is null
    where we.workout_id in (select id from week) and s.deleted_at is null
      and s.is_completed and s.set_type <> 'warmup'
  ),
  memory as (
    select m.note, m.created_at
    from public.coach_memory m
    where m.user_id = (select uid from me) and m.deleted_at is null
    order by m.created_at, m.id
    limit 20
  )
  select jsonb_build_object(
    'profile', (select to_jsonb(profile) from profile),
    'weight', (select jsonb_build_object('kg', round(weight_kg, 1), 'date', date) from weight),
    'reference_group', (select reference_group from settings),
    'scores_as_of', (select max(date) from latest_scores),
    'overall', (select jsonb_build_object('score', round(score), 'confidence', confidence)
                  from latest_scores where scope = 'overall' limit 1),
    'muscles', coalesce((select jsonb_agg(jsonb_build_object('key', key, 'score', round(score)) order by key)
                           from latest_scores where scope = 'muscle'), '[]'::jsonb),
    'strongest', coalesce((select jsonb_agg(jsonb_build_object('name', name, 'score', round(score)))
                             from (select * from exercise_scores order by score desc, key limit 3) t), '[]'::jsonb),
    'weakest', coalesce((select jsonb_agg(jsonb_build_object('name', name, 'score', round(score)))
                           from (select * from exercise_scores order by score asc, key limit 3) t), '[]'::jsonb),
    'routine', (select jsonb_build_object(
                  'name', ar.name,
                  'days', coalesce((select jsonb_agg(jsonb_build_object('name', d.name, 'exercises', d.exercise_count)
                                               order by d.position) from routine_days d), '[]'::jsonb))
                from active_routine ar),
    'last_7_days', jsonb_build_object(
      'workouts', (select count(*) from week)::int,
      'sets', (select count(*) from week_sets)::int,
      'volume_kg', (select coalesce(round(sum(weight_kg * reps)), 0) from week_sets)),
    'last_workout_at', (select started_at from last_workout),
    'memory', coalesce((select jsonb_agg(note order by created_at) from memory), '[]'::jsonb)
  );
$$;

revoke all on function public.coach_user_context(text) from public, anon;
grant execute on function public.coach_user_context(text) to authenticated;
