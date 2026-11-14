-- P093 · Anonymous ML contributions (docs/02-MIMARI.md §3.3).
-- The table has NO user_id and no link to any user table: `contribution_key` is a random key generated on the device
-- (rotated every 12 months). Client roles have no grants and no policy; only the service role (the `contribute`
-- Edge Function) reads and writes it.
create table public.ml_contributions (
  id                uuid primary key default gen_random_uuid(),
  contribution_key  uuid not null,
  sex               text not null check (sex in ('male', 'female')),
  age_band          smallint not null check (age_band between 10 and 95 and age_band % 5 = 0),
  bodyweight_kg     smallint not null check (bodyweight_kg between 30 and 300),
  height_band       smallint not null check (height_band between 120 and 230 and height_band % 5 = 0),
  experience_band   text not null check (experience_band in
    ('none', 'under_6_months', 'six_months_to_2_years', 'two_to_5_years', 'over_5_years')),
  frequency_band    text not null check (frequency_band in ('1-2', '3-4', '5-6', '7+')),
  month             text not null check (month ~ '^20[0-9]{2}-(0[1-9]|1[0-2])$'),
  exercise_id       text not null check (exercise_id ~ '^[a-z0-9][a-z0-9_-]{0,63}$'),
  best_e1rm_kg      numeric(6, 1) not null check (best_e1rm_kg > 0 and best_e1rm_kg <= 700),
  best_set_reps     smallint not null check (best_set_reps between 1 and 30),
  sessions_in_month smallint not null check (sessions_in_month between 1 and 62),
  model_version     text not null check (char_length(model_version) between 1 and 64),
  created_at        timestamptz not null default now(),
  unique (contribution_key, month, exercise_id)
);

alter table public.ml_contributions enable row level security;
revoke all on public.ml_contributions from anon, authenticated;

-- Explicit deny-all so the RLS audit (001_rls_audit) sees a stated intent; clients have no grants anyway.
create policy ml_contributions_no_client_access on public.ml_contributions
  for select to authenticated using (false);

-- Export cells (sex × age band × weight band × exercise) with fewer than 20 contributors stay out of training exports.
create index ml_contributions_cell_idx on public.ml_contributions (sex, age_band, exercise_id);
create index ml_contributions_key_idx on public.ml_contributions (contribution_key);
