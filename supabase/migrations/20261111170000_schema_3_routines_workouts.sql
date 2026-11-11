-- P012 · Schema 3 — routines and workouts
-- See docs/02-MIMARI.md §2.3 (local model) and §3.1 (tables).
--
--   routines -> routine_days -> routine_exercises        planned programs
--   workouts -> workout_exercises -> sets                 performed training
--   personal_records                                      derived bests (weight / reps / e1rm / volume)
--
-- Conventions (same as P010/P011): client-generated uuid ids, user_id -> auth.users (cascade),
-- created_at / updated_at (server clock) / deleted_at (soft delete), (user_id, updated_at) sync index,
-- owner-only RLS with no delete policy.
--
-- Additions specific to this migration:
--   * user_id is repeated on every child table so RLS is a plain `user_id = auth.uid()` check.
--   * Every parent FK is composite (parent_id, user_id) -> parent (id, user_id), so a child can never point at
--     another user's parent row, even though RLS only checks the child's own user_id.
--   * exercise_ref = (exercise_id | custom_exercise_id), exactly one non-null (CHECK).
--   * Weights are kg numeric(6,2), 0..1000. Lengths/units are display-only (docs/00-KARARLAR.md).

------------------------------------------------------------------------------
-- custom_exercises: composite FK target for exercise_ref
------------------------------------------------------------------------------
alter table public.custom_exercises
  add constraint custom_exercises_id_user_id_key unique (id, user_id);

------------------------------------------------------------------------------
-- routines
------------------------------------------------------------------------------
create table public.routines (
  id          uuid primary key,
  user_id     uuid not null references auth.users (id) on delete cascade,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  deleted_at  timestamptz,

  name        text not null,
  notes       text,

  constraint routines_id_user_id_key unique (id, user_id),
  constraint routines_name_check  check (char_length(btrim(name)) between 1 and 200),
  constraint routines_notes_check check (notes is null or char_length(notes) <= 4000)
);

create index routines_user_id_updated_at_idx on public.routines (user_id, updated_at);

create trigger routines_set_updated_at
  before insert or update on public.routines
  for each row execute function public.set_updated_at();

------------------------------------------------------------------------------
-- routine_days
------------------------------------------------------------------------------
create table public.routine_days (
  id          uuid primary key,
  user_id     uuid not null references auth.users (id) on delete cascade,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  deleted_at  timestamptz,

  routine_id  uuid not null,
  position    integer not null,
  name        text not null,

  constraint routine_days_id_user_id_key unique (id, user_id),
  constraint routine_days_routine_fkey
    foreign key (routine_id, user_id) references public.routines (id, user_id) on delete cascade,
  constraint routine_days_position_check check (position >= 0),
  constraint routine_days_name_check     check (char_length(btrim(name)) between 1 and 200)
);

create index routine_days_user_id_updated_at_idx on public.routine_days (user_id, updated_at);
create index routine_days_routine_id_position_idx on public.routine_days (routine_id, position);

create trigger routine_days_set_updated_at
  before insert or update on public.routine_days
  for each row execute function public.set_updated_at();

------------------------------------------------------------------------------
-- routine_exercises
------------------------------------------------------------------------------
create table public.routine_exercises (
  id                  uuid primary key,
  user_id             uuid not null references auth.users (id) on delete cascade,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),
  deleted_at          timestamptz,

  routine_day_id      uuid not null,
  position            integer not null,

  -- exercise_ref: exactly one of the two
  exercise_id         text references public.exercises (id) on update cascade,
  custom_exercise_id  uuid,

  target_sets         smallint not null default 3,
  target_reps_min     smallint,
  target_reps_max     smallint,
  target_rir          smallint,
  superset_group      smallint,
  rest_seconds        integer,
  notes               text,

  constraint routine_exercises_id_user_id_key unique (id, user_id),
  constraint routine_exercises_day_fkey
    foreign key (routine_day_id, user_id) references public.routine_days (id, user_id) on delete cascade,
  constraint routine_exercises_custom_exercise_fkey
    foreign key (custom_exercise_id, user_id) references public.custom_exercises (id, user_id),
  constraint routine_exercises_exercise_ref_check
    check (num_nonnulls(exercise_id, custom_exercise_id) = 1),
  constraint routine_exercises_position_check    check (position >= 0),
  constraint routine_exercises_target_sets_check check (target_sets between 1 and 50),
  constraint routine_exercises_reps_min_check    check (target_reps_min is null or target_reps_min between 0 and 100),
  constraint routine_exercises_reps_max_check    check (target_reps_max is null or target_reps_max between 0 and 100),
  constraint routine_exercises_reps_range_check
    check (target_reps_min is null or target_reps_max is null or target_reps_min <= target_reps_max),
  constraint routine_exercises_target_rir_check  check (target_rir is null or target_rir between 0 and 10),
  constraint routine_exercises_superset_check    check (superset_group is null or superset_group >= 1),
  constraint routine_exercises_rest_check        check (rest_seconds is null or rest_seconds between 0 and 3600),
  constraint routine_exercises_notes_check       check (notes is null or char_length(notes) <= 2000)
);

create index routine_exercises_user_id_updated_at_idx on public.routine_exercises (user_id, updated_at);
create index routine_exercises_day_id_position_idx on public.routine_exercises (routine_day_id, position);
create index routine_exercises_custom_exercise_idx on public.routine_exercises (custom_exercise_id)
  where custom_exercise_id is not null;

create trigger routine_exercises_set_updated_at
  before insert or update on public.routine_exercises
  for each row execute function public.set_updated_at();

------------------------------------------------------------------------------
-- workouts
------------------------------------------------------------------------------
create table public.workouts (
  id              uuid primary key,
  user_id         uuid not null references auth.users (id) on delete cascade,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  deleted_at      timestamptz,

  -- Optional link to the routine the workout was started from (kept as history if the routine is purged).
  routine_id      uuid,
  routine_day_id  uuid,

  name            text,
  started_at      timestamptz not null,
  ended_at        timestamptz,
  notes           text,

  constraint workouts_id_user_id_key unique (id, user_id),
  constraint workouts_routine_fkey
    foreign key (routine_id, user_id) references public.routines (id, user_id) on delete set null (routine_id),
  constraint workouts_routine_day_fkey
    foreign key (routine_day_id, user_id) references public.routine_days (id, user_id) on delete set null (routine_day_id),
  constraint workouts_name_check  check (name is null or char_length(name) <= 200),
  constraint workouts_ended_check check (ended_at is null or ended_at >= started_at),
  constraint workouts_notes_check check (notes is null or char_length(notes) <= 4000)
);

create index workouts_user_id_updated_at_idx on public.workouts (user_id, updated_at);
create index workouts_user_id_started_at_idx on public.workouts (user_id, started_at desc);
create index workouts_routine_id_idx on public.workouts (routine_id) where routine_id is not null;
create index workouts_routine_day_id_idx on public.workouts (routine_day_id) where routine_day_id is not null;

create trigger workouts_set_updated_at
  before insert or update on public.workouts
  for each row execute function public.set_updated_at();

------------------------------------------------------------------------------
-- workout_exercises
------------------------------------------------------------------------------
create table public.workout_exercises (
  id                  uuid primary key,
  user_id             uuid not null references auth.users (id) on delete cascade,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),
  deleted_at          timestamptz,

  workout_id          uuid not null,
  position            integer not null,

  exercise_id         text references public.exercises (id) on update cascade,
  custom_exercise_id  uuid,

  superset_group      smallint,
  notes               text,

  constraint workout_exercises_id_user_id_key unique (id, user_id),
  constraint workout_exercises_workout_fkey
    foreign key (workout_id, user_id) references public.workouts (id, user_id) on delete cascade,
  constraint workout_exercises_custom_exercise_fkey
    foreign key (custom_exercise_id, user_id) references public.custom_exercises (id, user_id),
  constraint workout_exercises_exercise_ref_check
    check (num_nonnulls(exercise_id, custom_exercise_id) = 1),
  constraint workout_exercises_position_check check (position >= 0),
  constraint workout_exercises_superset_check check (superset_group is null or superset_group >= 1),
  constraint workout_exercises_notes_check    check (notes is null or char_length(notes) <= 2000)
);

create index workout_exercises_user_id_updated_at_idx on public.workout_exercises (user_id, updated_at);
create index workout_exercises_workout_id_position_idx on public.workout_exercises (workout_id, position);
create index workout_exercises_exercise_idx on public.workout_exercises (user_id, exercise_id)
  where exercise_id is not null;
create index workout_exercises_custom_exercise_idx on public.workout_exercises (custom_exercise_id)
  where custom_exercise_id is not null;

create trigger workout_exercises_set_updated_at
  before insert or update on public.workout_exercises
  for each row execute function public.set_updated_at();

------------------------------------------------------------------------------
-- sets
------------------------------------------------------------------------------
-- No UNIQUE (workout_exercise_id, position): the client reorders sets offline and syncs rows one at a time,
-- and soft-deleted rows keep their position, so a unique constraint would only cause spurious sync failures.
create table public.sets (
  id                   uuid primary key,
  user_id              uuid not null references auth.users (id) on delete cascade,
  created_at           timestamptz not null default now(),
  updated_at           timestamptz not null default now(),
  deleted_at           timestamptz,

  workout_exercise_id  uuid not null,
  position             integer not null,

  weight_kg            numeric(6, 2) not null default 0,
  reps                 smallint not null default 0,
  rpe                  numeric(3, 1),
  rir                  smallint,
  set_type             text not null default 'working',
  is_completed         boolean not null default false,

  constraint sets_id_user_id_key unique (id, user_id),
  constraint sets_workout_exercise_fkey
    foreign key (workout_exercise_id, user_id) references public.workout_exercises (id, user_id) on delete cascade,
  constraint sets_position_check  check (position >= 0),
  constraint sets_weight_check    check (weight_kg between 0 and 1000),
  constraint sets_reps_check      check (reps between 0 and 100),
  constraint sets_rpe_check       check (rpe is null or rpe between 1 and 10),
  constraint sets_rir_check       check (rir is null or rir between 0 and 10),
  constraint sets_set_type_check  check (set_type in ('warmup', 'working', 'drop', 'failure'))
);

create index sets_user_id_updated_at_idx on public.sets (user_id, updated_at);
create index sets_workout_exercise_id_position_idx on public.sets (workout_exercise_id, position);

create trigger sets_set_updated_at
  before insert or update on public.sets
  for each row execute function public.set_updated_at();

------------------------------------------------------------------------------
-- personal_records
------------------------------------------------------------------------------
-- value unit depends on kind: weight -> kg, reps -> count, e1rm -> kg, volume -> kg (sum of weight x reps).
-- Volume can exceed numeric(6,2), hence numeric(10,2).
create table public.personal_records (
  id                  uuid primary key,
  user_id             uuid not null references auth.users (id) on delete cascade,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),
  deleted_at          timestamptz,

  exercise_id         text references public.exercises (id) on update cascade,
  custom_exercise_id  uuid,

  kind                text not null,
  value               numeric(10, 2) not null,
  set_id              uuid,
  date                date not null,

  constraint personal_records_id_user_id_key unique (id, user_id),
  constraint personal_records_custom_exercise_fkey
    foreign key (custom_exercise_id, user_id) references public.custom_exercises (id, user_id),
  -- The record stays valid history if the set it came from is purged.
  constraint personal_records_set_fkey
    foreign key (set_id, user_id) references public.sets (id, user_id) on delete set null (set_id),
  constraint personal_records_exercise_ref_check
    check (num_nonnulls(exercise_id, custom_exercise_id) = 1),
  constraint personal_records_kind_check  check (kind in ('weight', 'reps', 'e1rm', 'volume')),
  constraint personal_records_value_check check (value >= 0)
);

create index personal_records_user_id_updated_at_idx on public.personal_records (user_id, updated_at);
create index personal_records_user_exercise_kind_idx on public.personal_records (user_id, exercise_id, kind, date desc);
create index personal_records_custom_exercise_idx on public.personal_records (custom_exercise_id)
  where custom_exercise_id is not null;
create index personal_records_set_id_idx on public.personal_records (set_id) where set_id is not null;

create trigger personal_records_set_updated_at
  before insert or update on public.personal_records
  for each row execute function public.set_updated_at();

------------------------------------------------------------------------------
-- Row level security: owner may select / insert / update; nobody may delete (soft delete only).
------------------------------------------------------------------------------
alter table public.routines           enable row level security;
alter table public.routine_days       enable row level security;
alter table public.routine_exercises  enable row level security;
alter table public.workouts           enable row level security;
alter table public.workout_exercises  enable row level security;
alter table public.sets               enable row level security;
alter table public.personal_records   enable row level security;

revoke all on public.routines, public.routine_days, public.routine_exercises, public.workouts,
              public.workout_exercises, public.sets, public.personal_records
  from anon, authenticated;

grant select, insert, update on public.routines, public.routine_days, public.routine_exercises, public.workouts,
                                public.workout_exercises, public.sets, public.personal_records
  to authenticated;

do $$
declare
  t text;
begin
  foreach t in array array['routines', 'routine_days', 'routine_exercises', 'workouts',
                           'workout_exercises', 'sets', 'personal_records']
  loop
    execute format('create policy %I on public.%I for select to authenticated using (user_id = (select auth.uid()))',
                   t || '_select_own', t);
    execute format('create policy %I on public.%I for insert to authenticated with check (user_id = (select auth.uid()))',
                   t || '_insert_own', t);
    execute format('create policy %I on public.%I for update to authenticated '
                   'using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()))',
                   t || '_update_own', t);
  end loop;
end
$$;

------------------------------------------------------------------------------
-- purge_soft_deleted: remove tombstones older than the retention window (default 90 days)
------------------------------------------------------------------------------
-- Scheduling (pg_cron / Edge Function) comes later; until then the function is callable by the service role only.
-- Rows are deleted children-first. Deleting a parent also cascades to its children (a deleted workout takes its
-- exercises and sets with it); those cascaded rows are not included in the counts.
-- A custom exercise that is still referenced by a workout, routine or record is kept (the FK would reject the delete).
create or replace function public.purge_soft_deleted(retention interval default interval '90 days')
returns table (table_name text, rows_deleted bigint)
language plpgsql
set search_path = ''
as $$
declare
  cutoff timestamptz;
  n bigint;
begin
  if retention is null or retention < interval '1 day' then
    raise exception 'retention must be at least 1 day' using errcode = '22023';
  end if;
  cutoff := now() - retention;

  with d as (delete from public.personal_records where deleted_at < cutoff returning 1)
    select count(*) into n from d;
  table_name := 'personal_records'; rows_deleted := n; return next;

  with d as (delete from public.sets where deleted_at < cutoff returning 1)
    select count(*) into n from d;
  table_name := 'sets'; rows_deleted := n; return next;

  with d as (delete from public.workout_exercises where deleted_at < cutoff returning 1)
    select count(*) into n from d;
  table_name := 'workout_exercises'; rows_deleted := n; return next;

  with d as (delete from public.workouts where deleted_at < cutoff returning 1)
    select count(*) into n from d;
  table_name := 'workouts'; rows_deleted := n; return next;

  with d as (delete from public.routine_exercises where deleted_at < cutoff returning 1)
    select count(*) into n from d;
  table_name := 'routine_exercises'; rows_deleted := n; return next;

  with d as (delete from public.routine_days where deleted_at < cutoff returning 1)
    select count(*) into n from d;
  table_name := 'routine_days'; rows_deleted := n; return next;

  with d as (delete from public.routines where deleted_at < cutoff returning 1)
    select count(*) into n from d;
  table_name := 'routines'; rows_deleted := n; return next;

  with d as (
    delete from public.custom_exercises ce
    where ce.deleted_at < cutoff
      and not exists (select 1 from public.routine_exercises r where r.custom_exercise_id = ce.id)
      and not exists (select 1 from public.workout_exercises w where w.custom_exercise_id = ce.id)
      and not exists (select 1 from public.personal_records p where p.custom_exercise_id = ce.id)
    returning 1)
    select count(*) into n from d;
  table_name := 'custom_exercises'; rows_deleted := n; return next;

  with d as (delete from public.body_measurements where deleted_at < cutoff returning 1)
    select count(*) into n from d;
  table_name := 'body_measurements'; rows_deleted := n; return next;
end;
$$;

revoke all on function public.purge_soft_deleted(interval) from public, anon, authenticated;
grant execute on function public.purge_soft_deleted(interval) to service_role;
