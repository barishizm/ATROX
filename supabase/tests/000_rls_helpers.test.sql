-- P013 · Shared pgTAP helpers and the RLS table registry.
--
-- This file is intentionally NOT wrapped in a rolled-back transaction: it creates the `tests` schema that the
-- other test files rely on. It runs first (alphabetical order) against a freshly reset local database.
--
-- REGISTRY: every table in `public` must be listed in exactly one of tests.owner_tables() / tests.catalog_tables().
-- When you add a table in a migration, add it here AND write its tests; 001_rls_audit.test.sql fails otherwise.
begin;
create extension if not exists pgtap with schema extensions;

create schema if not exists tests;
grant usage on schema tests to anon, authenticated, service_role;

-- Tables whose rows belong to one user (have a user_id column, RLS "own rows only").
create or replace function tests.owner_tables() returns text[]
language sql immutable set search_path = '' as $$
  select array[
    'profiles', 'user_settings', 'consents', 'body_measurements',
    'custom_exercises',
    'routines', 'routine_days', 'routine_exercises',
    'workouts', 'workout_exercises', 'sets', 'personal_records', 'score_snapshots', 'insights',
    'coach_threads', 'coach_messages', 'coach_memory'
  ]
$$;

-- Owner-readable tables only the service role writes (the app cannot insert or update).
create or replace function tests.owner_readonly_tables() returns text[]
language sql immutable set search_path = '' as $$
  select array['coach_usage', 'entitlements', 'coach_quota', 'coach_digests', 'social_rate_limits']
$$;

-- Social tables (P085): readable under bespoke rules (discoverable / friends / blocks), written only through
-- security definer functions. Covered by 023_social.test.sql instead of the generic owner matrix.
create or replace function tests.social_tables() returns text[]
language sql immutable set search_path = '' as $$
  select array['public_profiles', 'friendships', 'reports', 'social_score_history']
$$;

-- Anonymous tables (P093): no user_id, no client grants; only the service role touches them (027_ml_contributions).
create or replace function tests.anonymous_tables() returns text[]
language sql immutable set search_path = '' as $$
  select array['ml_contributions']
$$;

-- Public, read-only reference tables (readable by everyone, writable only by service_role / migrations).
create or replace function tests.catalog_tables() returns text[]
language sql immutable set search_path = '' as $$
  select array['exercises', 'exercise_translations', 'catalog_versions', 'model_versions', 'coach_limits']
$$;

-- Two fake users, created as the superuser. Returns the ids as a convenience.
create or replace function tests.create_user(p_id uuid, p_email text) returns uuid
language plpgsql set search_path = '' as $$
begin
  insert into auth.users (id, instance_id, aud, role, email)
  values (p_id, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', p_email);
  return p_id;
end $$;

create or replace function tests.user_a() returns uuid language sql immutable set search_path = '' as
  $$ select '00000000-0000-0000-0000-0000000000a1'::uuid $$;
create or replace function tests.user_b() returns uuid language sql immutable set search_path = '' as
  $$ select '00000000-0000-0000-0000-0000000000b2'::uuid $$;

create or replace function tests.create_two_users() returns void
language plpgsql set search_path = '' as $$
begin
  perform tests.create_user(tests.user_a(), 'a@example.test');
  perform tests.create_user(tests.user_b(), 'b@example.test');
end $$;

-- Switch the session to `authenticated` with the given user's JWT claims.
create or replace function tests.authenticate_as(p_user uuid) returns void
language plpgsql set search_path = '' as $$
begin
  perform set_config('request.jwt.claims',
    json_build_object('sub', p_user, 'role', 'authenticated')::text, true);
  set local role authenticated;
end $$;

-- Switch the session to the anonymous role (no JWT).
create or replace function tests.authenticate_as_anon() returns void
language plpgsql set search_path = '' as $$
begin
  perform set_config('request.jwt.claims', '{"role":"anon"}', true);
  set local role anon;
end $$;

-- Back to the superuser (to seed or inspect data).
create or replace function tests.clear_authentication() returns void
language plpgsql set search_path = '' as $$
begin
  perform set_config('request.jwt.claims', null, true);
  reset role;
end $$;

-- Run a statement and report the SQLSTATE it raised (null when it succeeded). SECURITY INVOKER: runs as the caller.
create or replace function tests.try_sql(p_sql text) returns table (state text)
language plpgsql set search_path = '' as $$
begin
  execute p_sql;
  state := null;
  return next;
exception when others then
  state := SQLSTATE;
  return next;
end $$;

-- Row count of a public table as seen by the caller (so RLS applies).
create or replace function tests.count_rows(p_table text) returns bigint
language plpgsql set search_path = '' as $$
declare n bigint;
begin
  execute format('select count(*) from public.%I', p_table) into n;
  return n;
end $$;

-- First column of a public table (for generic UPDATE probes).
create or replace function tests.first_column(p_table text) returns text
language sql stable set search_path = '' as $$
  select attname::text from pg_attribute
  where attrelid = ('public.' || quote_ident(p_table))::regclass and attnum > 0 and not attisdropped
  order by attnum limit 1
$$;

grant execute on all functions in schema tests to anon, authenticated, service_role;

select plan(3);
select has_function('tests', 'create_two_users', 'helpers: create_two_users exists');
select has_function('tests', 'authenticate_as', array['uuid'], 'helpers: authenticate_as exists');
select is(
  (select count(*)::int from unnest(tests.owner_tables() || tests.catalog_tables()) t group by t having count(*) > 1),
  null, 'registry: no table is listed twice');
select * from finish();
commit;
