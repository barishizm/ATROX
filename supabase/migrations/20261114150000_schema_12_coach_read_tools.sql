-- P075 · Read tools of the AI coach (docs/04-AI-KOC.md §5).
--
-- Every function is SECURITY INVOKER and is called by coach-chat with the user's own JWT, so RLS limits each read to
-- the caller; nothing here runs with the service role. The output is compact jsonb: few fields, rounded numbers,
-- weights in kg. Scores and insights are read from the rows the app computed and synced; the server computes none.
-- search_exercises (P011/P028) is reused as is.

-- Display name of a catalog or custom exercise.
create function public.coach_exercise_name(p_exercise_id text, p_custom_exercise_id uuid, p_locale text)
returns text
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(
    (select c.name from public.custom_exercises c where c.id = p_custom_exercise_id),
    (select t.name from public.exercise_translations t where t.exercise_id = p_exercise_id and t.locale = p_locale),
    (select t.name from public.exercise_translations t where t.exercise_id = p_exercise_id and t.locale = 'en'),
    p_exercise_id);
$$;

------------------------------------------------------------------------------
-- get_recent_workouts(limit, since)
------------------------------------------------------------------------------
create function public.coach_recent_workouts(p_limit integer default 5, p_since date default null, p_locale text default 'en')
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  with w as (
    select w.id, w.started_at, w.ended_at, w.name
    from public.workouts w
    where w.user_id = (select auth.uid()) and w.deleted_at is null
      and (p_since is null or w.started_at >= p_since)
    order by w.started_at desc
    limit greatest(least(coalesce(p_limit, 5), 20), 1)
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'date', (w.started_at at time zone 'UTC')::date,
    'name', w.name,
    'duration_min', case when w.ended_at is null then null
                         else round(extract(epoch from w.ended_at - w.started_at) / 60) end,
    'exercises', (select coalesce(jsonb_agg(public.coach_exercise_name(we.exercise_id, we.custom_exercise_id, p_locale)
                                            order by we.position), '[]'::jsonb)
                    from public.workout_exercises we where we.workout_id = w.id and we.deleted_at is null),
    'working_sets', (select count(*) from public.sets s
                       join public.workout_exercises we on we.id = s.workout_exercise_id and we.deleted_at is null
                      where we.workout_id = w.id and s.deleted_at is null and s.is_completed and s.set_type <> 'warmup'),
    'volume_kg', (select coalesce(round(sum(s.weight_kg * s.reps)), 0) from public.sets s
                    join public.workout_exercises we on we.id = s.workout_exercise_id and we.deleted_at is null
                   where we.workout_id = w.id and s.deleted_at is null and s.is_completed and s.set_type <> 'warmup')
  ) order by w.started_at desc), '[]'::jsonb)
  from w;
$$;

------------------------------------------------------------------------------
-- get_exercise_history(exercise_id, weeks): best set per session; e1RM records the app synced.
-- p_exercise_id is a catalog id or a custom exercise uuid. Unknown exercise → null.
------------------------------------------------------------------------------
create function public.coach_exercise_history(p_exercise_id text, p_weeks integer default 8, p_locale text default 'en')
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_custom uuid;
  v_catalog text;
  v_since timestamptz := now() - make_interval(weeks => greatest(least(coalesce(p_weeks, 8), 52), 1));
begin
  if p_exercise_id ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    select c.id into v_custom from public.custom_exercises c
     where c.id = p_exercise_id::uuid and c.deleted_at is null;
    if v_custom is null then return null; end if;
  else
    select e.id into v_catalog from public.exercises e where e.id = p_exercise_id;
    if v_catalog is null then return null; end if;
  end if;

  return jsonb_build_object(
    'exercise', jsonb_build_object('id', p_exercise_id, 'name', public.coach_exercise_name(v_catalog, v_custom, p_locale)),
    'weeks', greatest(least(coalesce(p_weeks, 8), 52), 1),
    'sessions', coalesce((
      select jsonb_agg(session order by session ->> 'date')
      from (
        select jsonb_build_object(
          'date', (w.started_at at time zone 'UTC')::date,
          'top_set', (select jsonb_build_object('kg', round(s2.weight_kg, 1), 'reps', s2.reps)
                        from public.sets s2
                       where s2.workout_exercise_id = we.id and s2.deleted_at is null and s2.is_completed
                         and s2.set_type <> 'warmup'
                       order by s2.weight_kg desc, s2.reps desc limit 1),
          'working_sets', count(s.id),
          'volume_kg', coalesce(round(sum(s.weight_kg * s.reps)), 0)
        ) as session
        from public.workout_exercises we
        join public.workouts w on w.id = we.workout_id and w.deleted_at is null
        left join public.sets s on s.workout_exercise_id = we.id and s.deleted_at is null
                               and s.is_completed and s.set_type <> 'warmup'
        where we.deleted_at is null and w.started_at >= v_since
          and (we.exercise_id = v_catalog or we.custom_exercise_id = v_custom)
        group by we.id, w.started_at
        order by w.started_at desc
        limit 30
      ) t
    ), '[]'::jsonb),
    'e1rm_records', coalesce((
      select jsonb_agg(jsonb_build_object('date', r.date, 'kg', round(r.value, 1)) order by r.date)
      from (select pr.date, pr.value from public.personal_records pr
             where pr.deleted_at is null and pr.kind = 'e1rm' and pr.date >= v_since::date
               and (pr.exercise_id = v_catalog or pr.custom_exercise_id = v_custom)
             order by pr.date desc limit 12) r
    ), '[]'::jsonb)
  );
end
$$;

------------------------------------------------------------------------------
-- get_scores(scope): latest snapshot per key in the user's reference group.
-- `stale` = the newest workout is later than the newest score, i.e. the app has not synced fresh scores yet.
------------------------------------------------------------------------------
create function public.coach_scores(p_scope text default 'all', p_locale text default 'en')
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  with settings as (
    select coalesce((select s.reference_group from public.user_settings s
                      where s.user_id = (select auth.uid()) and s.deleted_at is null limit 1), 'gym') as reference_group
  ),
  latest as (
    select distinct on (s.scope, s.key) s.scope, s.key, s.score, s.confidence, s.date, s.model_version
    from public.score_snapshots s
    where s.user_id = (select auth.uid()) and s.deleted_at is null
      and s.reference_group = (select reference_group from settings)
      and (coalesce(p_scope, 'all') = 'all' or s.scope = p_scope)
    order by s.scope, s.key, s.date desc, s.updated_at desc
  ),
  last_workout as (
    select max((w.started_at at time zone 'UTC')::date) as d from public.workouts w
    where w.user_id = (select auth.uid()) and w.deleted_at is null
  )
  select jsonb_build_object(
    'reference_group', (select reference_group from settings),
    'as_of', (select max(date) from latest),
    'last_workout', (select d from last_workout),
    'stale', coalesce((select max(date) from latest) < (select d from last_workout), false),
    'items', coalesce((
      select jsonb_agg(jsonb_build_object(
               'scope', l.scope,
               'key', l.key,
               'name', case when l.scope = 'exercise' then public.coach_exercise_name(l.key, null, p_locale) end,
               'score', round(l.score),
               'confidence', l.confidence,
               'date', l.date)
             order by case l.scope when 'overall' then 0 when 'muscle' then 1 else 2 end, l.score desc, l.key)
      from (select * from latest order by case scope when 'overall' then 0 when 'muscle' then 1 else 2 end, score desc
            limit 40) l
    ), '[]'::jsonb)
  );
$$;

------------------------------------------------------------------------------
-- get_insights(): active, not dismissed, highest priority first.
------------------------------------------------------------------------------
create function public.coach_insights()
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
           'kind', i.kind, 'subject', i.subject, 'severity', i.severity, 'action', i.action,
           'detected', (i.detected_at at time zone 'UTC')::date, 'data', i.payload::jsonb)
         order by i.priority desc), '[]'::jsonb)
  from (select * from public.insights i
         where i.user_id = (select auth.uid()) and i.deleted_at is null and i.is_active and i.dismissed_at is null
         order by i.priority desc limit 10) i;
$$;

------------------------------------------------------------------------------
-- get_routine(routine_id?): the given routine, else the one of the latest workout, else the latest edited one.
------------------------------------------------------------------------------
create function public.coach_routine(p_routine_id uuid default null, p_locale text default 'en')
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  with chosen as (
    select r.id, r.name, r.notes
    from public.routines r
    where r.user_id = (select auth.uid()) and r.deleted_at is null
      and (p_routine_id is null or r.id = p_routine_id)
    order by (r.id = (select w.routine_id from public.workouts w
                       where w.user_id = (select auth.uid()) and w.deleted_at is null and w.routine_id is not null
                       order by w.started_at desc limit 1)) desc nulls last,
             r.updated_at desc
    limit 1
  )
  select jsonb_build_object(
    'id', c.id,
    'name', c.name,
    'notes', c.notes,
    'days', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', d.id,
               'name', d.name,
               'exercises', coalesce((
                 select jsonb_agg(jsonb_build_object(
                          'exercise_id', coalesce(e.exercise_id, e.custom_exercise_id::text),
                          'name', public.coach_exercise_name(e.exercise_id, e.custom_exercise_id, p_locale),
                          'sets', e.target_sets,
                          'reps', case when e.target_reps_min is null and e.target_reps_max is null then null
                                       else concat_ws('-', e.target_reps_min, e.target_reps_max) end,
                          'rir', e.target_rir,
                          'rest_s', e.rest_seconds)
                        order by e.position)
                 from public.routine_exercises e where e.routine_day_id = d.id and e.deleted_at is null), '[]'::jsonb))
             order by d.position)
      from public.routine_days d where d.routine_id = c.id and d.deleted_at is null), '[]'::jsonb))
  from chosen c;
$$;

------------------------------------------------------------------------------
-- get_weekly_volume(weeks): completed non-warm-up sets per primary muscle and ISO week (Monday start, UTC).
------------------------------------------------------------------------------
create function public.coach_weekly_volume(p_weeks integer default 4)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  with done_sets as (
    select date_trunc('week', w.started_at at time zone 'UTC')::date as week,
           coalesce(c.primary_muscles, e.primary_muscles) as muscles
    from public.sets s
    join public.workout_exercises we on we.id = s.workout_exercise_id and we.deleted_at is null
    join public.workouts w on w.id = we.workout_id and w.deleted_at is null
    left join public.exercises e on e.id = we.exercise_id
    left join public.custom_exercises c on c.id = we.custom_exercise_id
    where s.user_id = (select auth.uid()) and s.deleted_at is null and s.is_completed and s.set_type <> 'warmup'
      and w.started_at >= date_trunc('week', now() at time zone 'UTC')
                           - make_interval(weeks => greatest(least(coalesce(p_weeks, 4), 12), 1) - 1)
  ),
  per_week as (
    select week, muscle, count(*) as n
    from done_sets, unnest(muscles) as muscle
    group by week, muscle
  )
  select coalesce(jsonb_agg(jsonb_build_object('week', t.week, 'sets', t.by_muscle) order by t.week), '[]'::jsonb)
  from (select week, jsonb_object_agg(muscle, n order by muscle) as by_muscle from per_week group by week) t;
$$;

revoke all on function public.coach_exercise_name(text, uuid, text) from public, anon;
revoke all on function public.coach_recent_workouts(integer, date, text) from public, anon;
revoke all on function public.coach_exercise_history(text, integer, text) from public, anon;
revoke all on function public.coach_scores(text, text) from public, anon;
revoke all on function public.coach_insights() from public, anon;
revoke all on function public.coach_routine(uuid, text) from public, anon;
revoke all on function public.coach_weekly_volume(integer) from public, anon;
grant execute on function public.coach_exercise_name(text, uuid, text) to authenticated;
grant execute on function public.coach_recent_workouts(integer, date, text) to authenticated;
grant execute on function public.coach_exercise_history(text, integer, text) to authenticated;
grant execute on function public.coach_scores(text, text) to authenticated;
grant execute on function public.coach_insights() to authenticated;
grant execute on function public.coach_routine(uuid, text) to authenticated;
grant execute on function public.coach_weekly_volume(integer) to authenticated;
