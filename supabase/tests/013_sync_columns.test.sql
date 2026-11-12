-- P044 · Sync columns and the server clock.
begin;
create extension if not exists pgtap with schema extensions;
select plan(9);

insert into auth.users (id, instance_id, aud, role, email)
values ('00000000-0000-0000-0000-0000000000c3', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'c@example.test');

select has_column('public', 'workouts', 'source', 'workouts.source exists');
select has_column('public', 'workouts', 'rating', 'workouts.rating exists');
select has_column('public', 'workouts', 'health_kit_uuid', 'workouts.health_kit_uuid exists');
select has_column('public', 'custom_exercises', 'is_unilateral', 'custom_exercises.is_unilateral exists');

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000c3","role":"authenticated"}', true);

select lives_ok($$
  insert into public.workouts (id, user_id, started_at, ended_at, source, rating, health_kit_uuid)
  values ('60000000-0000-0000-0000-0000000000c3', '00000000-0000-0000-0000-0000000000c3',
          now() - interval '1 hour', now(), 'routine', 4, '70000000-0000-0000-0000-0000000000c3')
$$, 'a workout with source, rating and HealthKit id is accepted');

select throws_ok($$
  update public.workouts set rating = 6 where id = '60000000-0000-0000-0000-0000000000c3'
$$, '23514', null, 'rating above 5 is rejected');

select throws_ok($$
  update public.workouts set source = 'watch' where id = '60000000-0000-0000-0000-0000000000c3'
$$, '23514', null, 'unknown source is rejected');

select ok(abs(extract(epoch from (public.server_time() - now()))) < 1, 'server_time() returns the server clock');

reset role;
set local role anon;
select throws_ok($$ select public.server_time() $$, '42501', null, 'anon cannot call server_time()');

select * from finish();
rollback;
