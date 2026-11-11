-- P011 · Schema 2 — exercise catalog
-- See docs/02-MIMARI.md §3 and docs/03-ML-MODEL.md §6.
--
--   exercises             shared read-only catalog (stable text slug ids); written by the service role only
--   exercise_translations one row per (exercise, locale): name, aliases, instructions
--   catalog_versions      published catalog versions; the app compares its local version to the latest
--   custom_exercises      per-user, synced, same descriptor fields as the catalog
--
-- Enum-like values:
--   equipment / mechanic / force / level / category / muscles  -> free-exercise-db vocabulary (docs/00-KARARLAR.md §5.4);
--                                                                 values are kept verbatim so the importer needs no mapping.
--   scoring_type / anchor_lift / load_convention / ratio_confidence -> docs/03-ML-MODEL.md §6.
--   movement_pattern      -> not specified in the docs yet; the list below is our own taxonomy (see docs/ILERLEME.md).

------------------------------------------------------------------------------
-- Extensions (accent-insensitive, typo-tolerant search)
------------------------------------------------------------------------------
create extension if not exists unaccent with schema extensions;
create extension if not exists pg_trgm  with schema extensions;

------------------------------------------------------------------------------
-- Search normalisation
------------------------------------------------------------------------------
-- unaccent() is only STABLE, so indexes and generated columns need an IMMUTABLE wrapper that pins the dictionary.
-- Turkish dotted/dotless i is folded explicitly (I, İ, ı -> i) because lower() is locale-dependent.
-- ş ğ ü ö ç â are handled by the default unaccent rules.
create or replace function public.normalize_search_text(input text)
returns text
language sql
immutable
parallel safe
strict
set search_path = ''
as $$
  select lower(
    extensions.unaccent('extensions.unaccent'::regdictionary, translate(input, 'İıI', 'iii'))
  );
$$;

create or replace function public.exercise_search_text(name text, aliases text[])
returns text
language sql
immutable
parallel safe
set search_path = ''
as $$
  select public.normalize_search_text(
    coalesce(name, '') || ' ' || coalesce(array_to_string(aliases, ' '), '')
  );
$$;

------------------------------------------------------------------------------
-- exercises
------------------------------------------------------------------------------
create table public.exercises (
  id                text primary key,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),

  -- free-exercise-db descriptors
  equipment         text,
  mechanic          text,
  force             text,
  level             text not null,
  category          text not null,
  primary_muscles   text[] not null,
  secondary_muscles text[] not null default '{}',

  -- our own classification
  movement_pattern  text not null default 'other',

  -- scoring taxonomy (tools/catalog/scoring_taxonomy.yaml)
  scoring_type      text not null default 'none',
  anchor_lift       text,
  load_convention   text,
  ratio             numeric(6, 4),
  tau               numeric(6, 4),
  ratio_confidence  text,
  bw_fraction       numeric(4, 3),
  is_core           boolean not null default false,

  image_paths       text[] not null default '{}',

  constraint exercises_id_check
    check (id ~ '^[a-z0-9]+(_[a-z0-9]+)*$' and char_length(id) <= 100),
  constraint exercises_equipment_check
    check (equipment is null or equipment in (
      'barbell', 'dumbbell', 'kettlebells', 'machine', 'cable', 'bands', 'body only',
      'e-z curl bar', 'exercise ball', 'foam roll', 'medicine ball', 'other')),
  constraint exercises_mechanic_check
    check (mechanic is null or mechanic in ('compound', 'isolation')),
  constraint exercises_force_check
    check (force is null or force in ('push', 'pull', 'static')),
  constraint exercises_level_check
    check (level in ('beginner', 'intermediate', 'expert')),
  constraint exercises_category_check
    check (category in ('strength', 'powerlifting', 'olympic weightlifting', 'strongman',
                        'plyometrics', 'stretching', 'cardio')),
  constraint exercises_primary_muscles_check
    check (cardinality(primary_muscles) >= 1 and primary_muscles <@ array[
      'abdominals', 'abductors', 'adductors', 'biceps', 'calves', 'chest', 'forearms', 'glutes', 'hamstrings',
      'lats', 'lower back', 'middle back', 'neck', 'quadriceps', 'shoulders', 'traps', 'triceps']::text[]),
  constraint exercises_secondary_muscles_check
    check (secondary_muscles <@ array[
      'abdominals', 'abductors', 'adductors', 'biceps', 'calves', 'chest', 'forearms', 'glutes', 'hamstrings',
      'lats', 'lower back', 'middle back', 'neck', 'quadriceps', 'shoulders', 'traps', 'triceps']::text[]),
  constraint exercises_movement_pattern_check
    check (movement_pattern in (
      'squat', 'hinge', 'lunge', 'horizontal_push', 'vertical_push', 'horizontal_pull', 'vertical_pull',
      'carry', 'core', 'rotation', 'isolation', 'cardio', 'mobility', 'other')),
  constraint exercises_scoring_type_check
    check (scoring_type in ('weighted', 'bodyweight_loaded', 'reps_only', 'time', 'none')),
  constraint exercises_anchor_lift_check
    check (anchor_lift is null or anchor_lift in ('squat', 'bench', 'deadlift')),
  constraint exercises_load_convention_check
    check (load_convention is null or load_convention in
      ('total', 'per_hand', 'per_side', 'machine_stack', 'bodyweight_plus')),
  constraint exercises_ratio_check
    check (ratio is null or ratio > 0),
  constraint exercises_tau_check
    check (tau is null or tau > 0),
  constraint exercises_ratio_confidence_check
    check (ratio_confidence is null or ratio_confidence in ('A', 'B', 'C')),
  constraint exercises_bw_fraction_check
    check (bw_fraction is null or bw_fraction between 0 and 1.5),
  -- Scored exercises must carry what the scoring engine needs.
  constraint exercises_weighted_fields_check
    check (scoring_type <> 'weighted'
           or (anchor_lift is not null and ratio is not null and tau is not null
               and load_convention is not null and ratio_confidence is not null)),
  constraint exercises_bodyweight_loaded_fields_check
    check (scoring_type <> 'bodyweight_loaded'
           or (anchor_lift is not null and ratio is not null and tau is not null
               and bw_fraction is not null and ratio_confidence is not null))
);

create index exercises_updated_at_idx on public.exercises (updated_at);
create index exercises_primary_muscles_idx on public.exercises using gin (primary_muscles);
create index exercises_equipment_idx on public.exercises (equipment);
create index exercises_core_idx on public.exercises (id) where is_core;

create trigger exercises_set_updated_at
  before insert or update on public.exercises
  for each row execute function public.set_updated_at();

------------------------------------------------------------------------------
-- exercise_translations
------------------------------------------------------------------------------
create table public.exercise_translations (
  exercise_id  text not null references public.exercises (id) on delete cascade on update cascade,
  locale       text not null,
  name         text not null,
  aliases      text[] not null default '{}',
  instructions text[] not null default '{}',
  -- Normalised name + aliases for accent-insensitive search.
  search_text  text generated always as (public.exercise_search_text(name, aliases)) stored,

  primary key (exercise_id, locale),
  constraint exercise_translations_locale_check
    check (locale ~ '^[a-z]{2}(-[A-Z]{2})?$'),
  constraint exercise_translations_name_check
    check (char_length(btrim(name)) between 1 and 200)
);

create index exercise_translations_search_trgm_idx
  on public.exercise_translations using gin (search_text extensions.gin_trgm_ops);

------------------------------------------------------------------------------
-- catalog_versions
------------------------------------------------------------------------------
create table public.catalog_versions (
  version      integer primary key,
  published_at timestamptz not null default now(),
  checksum     text not null,

  constraint catalog_versions_version_check check (version > 0),
  constraint catalog_versions_checksum_check check (char_length(checksum) > 0)
);

------------------------------------------------------------------------------
-- custom_exercises (per user, synced; same conventions as the P010 user tables)
------------------------------------------------------------------------------
create table public.custom_exercises (
  id                uuid primary key,
  user_id           uuid not null references auth.users (id) on delete cascade,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  deleted_at        timestamptz,

  name              text not null,
  aliases           text[] not null default '{}',
  instructions      text[] not null default '{}',

  equipment         text,
  mechanic          text,
  force             text,
  level             text not null default 'beginner',
  category          text not null default 'strength',
  primary_muscles   text[] not null,
  secondary_muscles text[] not null default '{}',
  movement_pattern  text not null default 'other',

  scoring_type      text not null default 'none',
  anchor_lift       text,
  load_convention   text,
  ratio             numeric(6, 4),
  tau               numeric(6, 4),
  ratio_confidence  text,
  bw_fraction       numeric(4, 3),

  constraint custom_exercises_name_check
    check (char_length(btrim(name)) between 1 and 200),
  constraint custom_exercises_equipment_check
    check (equipment is null or equipment in (
      'barbell', 'dumbbell', 'kettlebells', 'machine', 'cable', 'bands', 'body only',
      'e-z curl bar', 'exercise ball', 'foam roll', 'medicine ball', 'other')),
  constraint custom_exercises_mechanic_check
    check (mechanic is null or mechanic in ('compound', 'isolation')),
  constraint custom_exercises_force_check
    check (force is null or force in ('push', 'pull', 'static')),
  constraint custom_exercises_level_check
    check (level in ('beginner', 'intermediate', 'expert')),
  constraint custom_exercises_category_check
    check (category in ('strength', 'powerlifting', 'olympic weightlifting', 'strongman',
                        'plyometrics', 'stretching', 'cardio')),
  constraint custom_exercises_primary_muscles_check
    check (cardinality(primary_muscles) >= 1 and primary_muscles <@ array[
      'abdominals', 'abductors', 'adductors', 'biceps', 'calves', 'chest', 'forearms', 'glutes', 'hamstrings',
      'lats', 'lower back', 'middle back', 'neck', 'quadriceps', 'shoulders', 'traps', 'triceps']::text[]),
  constraint custom_exercises_secondary_muscles_check
    check (secondary_muscles <@ array[
      'abdominals', 'abductors', 'adductors', 'biceps', 'calves', 'chest', 'forearms', 'glutes', 'hamstrings',
      'lats', 'lower back', 'middle back', 'neck', 'quadriceps', 'shoulders', 'traps', 'triceps']::text[]),
  constraint custom_exercises_movement_pattern_check
    check (movement_pattern in (
      'squat', 'hinge', 'lunge', 'horizontal_push', 'vertical_push', 'horizontal_pull', 'vertical_pull',
      'carry', 'core', 'rotation', 'isolation', 'cardio', 'mobility', 'other')),
  constraint custom_exercises_scoring_type_check
    check (scoring_type in ('weighted', 'bodyweight_loaded', 'reps_only', 'time', 'none')),
  constraint custom_exercises_anchor_lift_check
    check (anchor_lift is null or anchor_lift in ('squat', 'bench', 'deadlift')),
  constraint custom_exercises_load_convention_check
    check (load_convention is null or load_convention in
      ('total', 'per_hand', 'per_side', 'machine_stack', 'bodyweight_plus')),
  constraint custom_exercises_ratio_check
    check (ratio is null or ratio > 0),
  constraint custom_exercises_tau_check
    check (tau is null or tau > 0),
  constraint custom_exercises_ratio_confidence_check
    check (ratio_confidence is null or ratio_confidence in ('A', 'B', 'C')),
  constraint custom_exercises_bw_fraction_check
    check (bw_fraction is null or bw_fraction between 0 and 1.5)
);

create index custom_exercises_user_id_updated_at_idx on public.custom_exercises (user_id, updated_at);

create trigger custom_exercises_set_updated_at
  before insert or update on public.custom_exercises
  for each row execute function public.set_updated_at();

------------------------------------------------------------------------------
-- Row level security
------------------------------------------------------------------------------
alter table public.exercises             enable row level security;
alter table public.exercise_translations enable row level security;
alter table public.catalog_versions      enable row level security;
alter table public.custom_exercises      enable row level security;

revoke all on public.exercises, public.exercise_translations, public.catalog_versions, public.custom_exercises
  from anon, authenticated;

-- Catalog: everyone reads, nobody but the service role writes (service_role bypasses RLS; no write policies exist).
grant select on public.exercises, public.exercise_translations, public.catalog_versions
  to anon, authenticated;

create policy exercises_select_all on public.exercises
  for select to anon, authenticated using (true);
create policy exercise_translations_select_all on public.exercise_translations
  for select to anon, authenticated using (true);
create policy catalog_versions_select_all on public.catalog_versions
  for select to anon, authenticated using (true);

-- Custom exercises: owner only; soft delete (no delete policy / grant).
grant select, insert, update on public.custom_exercises to authenticated;

create policy custom_exercises_select_own on public.custom_exercises
  for select to authenticated using (user_id = (select auth.uid()));
create policy custom_exercises_insert_own on public.custom_exercises
  for insert to authenticated with check (user_id = (select auth.uid()));
create policy custom_exercises_update_own on public.custom_exercises
  for update to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));

------------------------------------------------------------------------------
-- search_exercises
------------------------------------------------------------------------------
-- Accent- and case-insensitive catalog search across every locale's name and aliases ("sirt" finds "sırt",
-- "bench" finds "Bench Press - Bench Press"), with typo tolerance through trigram word similarity.
-- Results carry the name in the requested locale (fallback: English, then any).
-- An empty query browses the catalog (core exercises first), still honouring the filters.
-- SECURITY INVOKER: it runs under the caller's RLS.
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
  where (p_muscle is null or p_muscle = any (e.primary_muscles))
    and (p_equipment is null or e.equipment = any (p_equipment))
  order by h.score desc, e.is_core desc, coalesce(tl.name, ten.name, tany.name)
  limit greatest(least(coalesce(p_limit, 20), 100), 1);
$$;

revoke all on function public.search_exercises(text, text, text, text[], integer) from public;
grant execute on function public.search_exercises(text, text, text, text[], integer) to anon, authenticated, service_role;
