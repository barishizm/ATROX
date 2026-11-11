-- P010 · RLS and constraint tests for profiles, user_settings, consents, body_measurements.
begin;
create extension if not exists pgtap with schema extensions;
select plan(35);

-- Two users, created as the superuser.
insert into auth.users (id, instance_id, aud, role, email)
values
  ('00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'a@example.test'),
  ('00000000-0000-0000-0000-0000000000b2', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'b@example.test');

-- RLS enabled on every table.
select ok((select relrowsecurity from pg_class where oid = 'public.profiles'::regclass), 'profiles: RLS enabled');
select ok((select relrowsecurity from pg_class where oid = 'public.user_settings'::regclass), 'user_settings: RLS enabled');
select ok((select relrowsecurity from pg_class where oid = 'public.consents'::regclass), 'consents: RLS enabled');
select ok((select relrowsecurity from pg_class where oid = 'public.body_measurements'::regclass), 'body_measurements: RLS enabled');

-- Act as user A.
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000a1","role":"authenticated"}', true);

select lives_ok($$
  insert into public.profiles (id, user_id, birth_date, height_cm, experience, goal, weekly_frequency, equipment_access)
  values ('10000000-0000-0000-0000-00000000000a', '00000000-0000-0000-0000-0000000000a1',
          '1995-05-05', 180, 'two_to_5_years', 'strength', 4, 'full_gym')
$$, 'owner can insert own profile');

select lives_ok($$
  insert into public.user_settings (id, user_id)
  values ('20000000-0000-0000-0000-00000000000a', '00000000-0000-0000-0000-0000000000a1')
$$, 'owner can insert own settings (defaults apply)');

select lives_ok($$
  insert into public.consents (id, user_id, kind, version, granted)
  values ('30000000-0000-0000-0000-00000000000a', '00000000-0000-0000-0000-0000000000a1', 'terms', '1', true)
$$, 'owner can insert own consent');

select lives_ok($$
  insert into public.body_measurements (id, user_id, date, weight_kg)
  values ('40000000-0000-0000-0000-00000000000a', '00000000-0000-0000-0000-0000000000a1', '2026-11-01', 82.5)
$$, 'owner can insert own measurement');

-- Cannot insert rows for another user.
select throws_ok($$
  insert into public.profiles (id, user_id, birth_date, height_cm, experience, goal, weekly_frequency, equipment_access)
  values ('10000000-0000-0000-0000-0000000000ff', '00000000-0000-0000-0000-0000000000b2',
          '1995-05-05', 180, 'none', 'strength', 3, 'full_gym')
$$, '42501', null, 'profiles: cannot insert for another user');
select throws_ok($$
  insert into public.user_settings (id, user_id)
  values ('20000000-0000-0000-0000-0000000000ff', '00000000-0000-0000-0000-0000000000b2')
$$, '42501', null, 'user_settings: cannot insert for another user');
select throws_ok($$
  insert into public.consents (id, user_id, kind, version, granted)
  values ('30000000-0000-0000-0000-0000000000ff', '00000000-0000-0000-0000-0000000000b2', 'terms', '1', true)
$$, '42501', null, 'consents: cannot insert for another user');
select throws_ok($$
  insert into public.body_measurements (id, user_id, date, weight_kg)
  values ('40000000-0000-0000-0000-0000000000ff', '00000000-0000-0000-0000-0000000000b2', '2026-11-01', 70)
$$, '42501', null, 'body_measurements: cannot insert for another user');

-- Owner updates work and updated_at is maintained by the server.
select lives_ok($$
  update public.profiles set first_name = 'Ada' where user_id = '00000000-0000-0000-0000-0000000000a1'
$$, 'owner can update own profile');
select is((select first_name from public.profiles), 'Ada', 'profile update persisted');
select ok((select updated_at >= created_at from public.profiles), 'updated_at maintained by trigger');

-- Soft delete is an update.
select lives_ok($$
  update public.body_measurements set deleted_at = now() where id = '40000000-0000-0000-0000-00000000000a'
$$, 'owner can soft-delete own measurement');

-- Hard delete is not permitted at all.
select throws_ok($$ delete from public.profiles $$, '42501', null, 'profiles: delete denied');
select throws_ok($$ delete from public.user_settings $$, '42501', null, 'user_settings: delete denied');
select throws_ok($$ delete from public.consents $$, '42501', null, 'consents: delete denied');
select throws_ok($$ delete from public.body_measurements $$, '42501', null, 'body_measurements: delete denied');

-- Consents are append-only: no update.
select throws_ok($$ update public.consents set granted = false $$, '42501', null, 'consents: update denied');

-- Constraints.
select throws_ok($$
  insert into public.body_measurements (id, user_id, date, weight_kg)
  values ('40000000-0000-0000-0000-0000000000a2', '00000000-0000-0000-0000-0000000000a1', '2026-11-02', 19)
$$, '23514', null, 'weight below 20 kg rejected');
select throws_ok($$
  insert into public.consents (id, user_id, kind, version, granted)
  values ('30000000-0000-0000-0000-0000000000a2', '00000000-0000-0000-0000-0000000000a1', 'bogus', '1', true)
$$, '23514', null, 'unknown consent kind rejected');
select throws_ok($$
  update public.profiles set height_cm = 99
$$, '23514', null, 'height below 100 cm rejected');
select throws_ok($$
  update public.profiles set height_cm = 251
$$, '23514', null, 'height above 250 cm rejected');
select throws_ok($$
  update public.profiles set birth_date = (current_date - interval '15 years')::date
$$, '23514', null, 'age under 16 rejected');
select throws_ok($$
  update public.profiles set sex = 'other'
$$, '23514', null, 'invalid sex rejected');

-- Act as user B: sees nothing of A's, and cannot modify it.
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000b2","role":"authenticated"}', true);

select is((select count(*)::int from public.profiles), 0, 'B cannot read A profile');
select is((select count(*)::int from public.user_settings), 0, 'B cannot read A settings');
select is((select count(*)::int from public.consents), 0, 'B cannot read A consents');
select is((select count(*)::int from public.body_measurements), 0, 'B cannot read A measurements');

update public.profiles set first_name = 'Mallory';
update public.body_measurements set weight_kg = 50;

-- Back to A: nothing was changed by B.
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000a1","role":"authenticated"}', true);
select is((select first_name from public.profiles), 'Ada', 'B update did not touch A profile');
select is((select weight_kg from public.body_measurements), 82.5, 'B update did not touch A measurement');

-- Anonymous role has no access.
reset role;
set local role anon;
select throws_ok($$ select * from public.profiles $$, '42501', null, 'anon cannot read profiles');
select throws_ok($$ select * from public.body_measurements $$, '42501', null, 'anon cannot read measurements');

select * from finish();
rollback;
