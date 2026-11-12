-- P028 · Schema 4 — align the catalog tables with the vocabulary the import pipeline actually produces.
--
-- P011 copied the raw free-exercise-db strings ('body only', 'lower back', 'e-z curl bar', ...) and a guessed
-- movement-pattern list. The pipeline (tools/catalog, P024/P025) normalises them to snake_case values, uses hyphenated
-- slug ids (locked in tools/catalog/id_lock.json) and a richer movement-pattern taxonomy. The catalog is the source of
-- truth, so the constraints follow it. Nothing has been seeded yet, so no data needs rewriting.
--
-- Also adds:
--   exercises.archived_at   a catalog update never deletes an exercise (workouts reference it); removed ones are archived
--   *.is_unilateral         one side at a time (taxonomy field, used by the score engine for load conventions)

------------------------------------------------------------------------------
-- exercises
------------------------------------------------------------------------------
alter table public.exercises
  drop constraint exercises_id_check,
  drop constraint exercises_equipment_check,
  drop constraint exercises_category_check,
  drop constraint exercises_primary_muscles_check,
  drop constraint exercises_secondary_muscles_check,
  drop constraint exercises_movement_pattern_check;

alter table public.exercises
  add column archived_at   timestamptz,
  add column is_unilateral boolean not null default false;

alter table public.exercises
  add constraint exercises_id_check
    check (id ~ '^[a-z0-9]+([_-][a-z0-9]+)*$' and char_length(id) <= 100),
  add constraint exercises_equipment_check
    check (equipment is null or equipment in (
      'barbell', 'dumbbell', 'kettlebell', 'machine', 'cable', 'bands', 'body_only',
      'ez_bar', 'exercise_ball', 'foam_roll', 'medicine_ball', 'other')),
  add constraint exercises_category_check
    check (category in ('strength', 'powerlifting', 'olympic_weightlifting', 'strongman',
                        'plyometrics', 'stretching', 'cardio')),
  add constraint exercises_primary_muscles_check
    check (cardinality(primary_muscles) >= 1 and primary_muscles <@ array[
      'abdominals', 'abductors', 'adductors', 'biceps', 'calves', 'chest', 'forearms', 'glutes', 'hamstrings',
      'lats', 'lower_back', 'middle_back', 'neck', 'quadriceps', 'shoulders', 'traps', 'triceps']::text[]),
  add constraint exercises_secondary_muscles_check
    check (secondary_muscles <@ array[
      'abdominals', 'abductors', 'adductors', 'biceps', 'calves', 'chest', 'forearms', 'glutes', 'hamstrings',
      'lats', 'lower_back', 'middle_back', 'neck', 'quadriceps', 'shoulders', 'traps', 'triceps']::text[]),
  add constraint exercises_movement_pattern_check
    check (movement_pattern in (
      'squat', 'hip_hinge', 'horizontal_push', 'vertical_push', 'horizontal_pull', 'vertical_pull',
      'isolation_biceps', 'isolation_triceps', 'isolation_forearms', 'isolation_shoulders', 'isolation_chest',
      'isolation_back', 'isolation_quads', 'isolation_hamstrings', 'isolation_glutes', 'isolation_calves',
      'isolation_hips', 'isolation_neck', 'core', 'carry', 'olympic', 'plyometric', 'cardio', 'mobility', 'other'));

-- The taxonomy (P025) assigns scoring_type to every exercise, but anchor/ratio/tau/confidence are only computed in
-- P056. Until then a weighted row may carry no scoring parameters at all; once any is set, all must be (the
-- complete-or-empty rule). P056 restores the strict P011 checks together with the numbers.
alter table public.exercises
  drop constraint exercises_weighted_fields_check,
  drop constraint exercises_bodyweight_loaded_fields_check;

alter table public.exercises
  add constraint exercises_weighted_fields_check
    check (scoring_type <> 'weighted'
           or (anchor_lift is null and ratio is null and tau is null and ratio_confidence is null)
           or (anchor_lift is not null and ratio is not null and tau is not null
               and load_convention is not null and ratio_confidence is not null)),
  add constraint exercises_bodyweight_loaded_fields_check
    check (scoring_type <> 'bodyweight_loaded'
           or (anchor_lift is null and ratio is null and tau is null and ratio_confidence is null)
           or (anchor_lift is not null and ratio is not null and tau is not null
               and bw_fraction is not null and ratio_confidence is not null));

create index exercises_archived_at_idx on public.exercises (archived_at) where archived_at is not null;

------------------------------------------------------------------------------
-- custom_exercises (same vocabulary as the catalog)
------------------------------------------------------------------------------
alter table public.custom_exercises
  drop constraint custom_exercises_equipment_check,
  drop constraint custom_exercises_category_check,
  drop constraint custom_exercises_primary_muscles_check,
  drop constraint custom_exercises_secondary_muscles_check,
  drop constraint custom_exercises_movement_pattern_check;

alter table public.custom_exercises
  add column is_unilateral boolean not null default false;

alter table public.custom_exercises
  add constraint custom_exercises_equipment_check
    check (equipment is null or equipment in (
      'barbell', 'dumbbell', 'kettlebell', 'machine', 'cable', 'bands', 'body_only',
      'ez_bar', 'exercise_ball', 'foam_roll', 'medicine_ball', 'other')),
  add constraint custom_exercises_category_check
    check (category in ('strength', 'powerlifting', 'olympic_weightlifting', 'strongman',
                        'plyometrics', 'stretching', 'cardio')),
  add constraint custom_exercises_primary_muscles_check
    check (cardinality(primary_muscles) >= 1 and primary_muscles <@ array[
      'abdominals', 'abductors', 'adductors', 'biceps', 'calves', 'chest', 'forearms', 'glutes', 'hamstrings',
      'lats', 'lower_back', 'middle_back', 'neck', 'quadriceps', 'shoulders', 'traps', 'triceps']::text[]),
  add constraint custom_exercises_secondary_muscles_check
    check (secondary_muscles <@ array[
      'abdominals', 'abductors', 'adductors', 'biceps', 'calves', 'chest', 'forearms', 'glutes', 'hamstrings',
      'lats', 'lower_back', 'middle_back', 'neck', 'quadriceps', 'shoulders', 'traps', 'triceps']::text[]),
  add constraint custom_exercises_movement_pattern_check
    check (movement_pattern in (
      'squat', 'hip_hinge', 'horizontal_push', 'vertical_push', 'horizontal_pull', 'vertical_pull',
      'isolation_biceps', 'isolation_triceps', 'isolation_forearms', 'isolation_shoulders', 'isolation_chest',
      'isolation_back', 'isolation_quads', 'isolation_hamstrings', 'isolation_glutes', 'isolation_calves',
      'isolation_hips', 'isolation_neck', 'core', 'carry', 'olympic', 'plyometric', 'cardio', 'mobility', 'other'));

------------------------------------------------------------------------------
-- search_exercises: browsing and searching skip archived exercises
------------------------------------------------------------------------------
create or replace function public.search_exercises(
  p_query     text,
  p_locale    text default 'en',
  p_muscle    text default null,
  p_equipment text[] default null,
  p_limit     integer default 20
)
returns table (
  exercise_id      text,
  name             text,
  locale           text,
  equipment        text,
  primary_muscles  text[],
  is_core          boolean,
  score            real
)
language sql
stable
set search_path = public, extensions
as $$
  with q as (
    select public.normalize_search_text(btrim(coalesce(p_query, ''))) as n
  ),
  hits as (
    select
      t.exercise_id,
      max(case
            when (select n from q) = '' then 0
            when t.search_text like (replace(replace(replace((select n from q), '\', '\\'), '%', '\%'), '_', '\_') || '%') then 1.0
            else greatest(word_similarity((select n from q), t.search_text), 0.5)
          end)::real as score
    from public.exercise_translations t
    where (select n from q) = ''
       or t.search_text like ('%' || replace(replace(replace((select n from q), '\', '\\'), '%', '\%'), '_', '\_') || '%')
       or word_similarity((select n from q), t.search_text) >= 0.45
    group by t.exercise_id
  )
  select
    e.id,
    coalesce(tl.name, ten.name, tany.name),
    coalesce(tl.locale, ten.locale, tany.locale),
    e.equipment,
    e.primary_muscles,
    e.is_core,
    h.score
  from hits h
  join public.exercises e on e.id = h.exercise_id
  left join public.exercise_translations tl  on tl.exercise_id  = e.id and tl.locale  = p_locale
  left join public.exercise_translations ten on ten.exercise_id = e.id and ten.locale = 'en'
  left join lateral (
    select a.name, a.locale from public.exercise_translations a
    where a.exercise_id = e.id order by a.locale limit 1
  ) tany on true
  where e.archived_at is null
    and (p_muscle is null or p_muscle = any (e.primary_muscles))
    and (p_equipment is null or e.equipment = any (p_equipment))
  order by h.score desc, e.is_core desc, coalesce(tl.name, ten.name, tany.name)
  limit greatest(least(coalesce(p_limit, 20), 100), 1);
$$;
