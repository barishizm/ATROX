-- D008 · search_custom_exercises returns only the caller's own, non-deleted custom exercises.
begin;
select plan(5);

select tests.create_two_users();

insert into public.custom_exercises (id, user_id, name, primary_muscles)
values ('50000000-0000-0000-0000-0000000000c1', tests.user_a(), 'Zercher Squat', '{quadriceps}'),
       ('50000000-0000-0000-0000-0000000000c2', tests.user_b(), 'Zercher Lunge', '{quadriceps}');
insert into public.custom_exercises (id, user_id, name, primary_muscles, deleted_at)
values ('50000000-0000-0000-0000-0000000000c3', tests.user_a(), 'Zercher Deleted', '{quadriceps}', now());

select tests.authenticate_as(tests.user_a());
select is((select count(*)::int from public.search_custom_exercises('zercher')), 1, 'only the own, live exercise is found');
select is((select exercise_id from public.search_custom_exercises('ZERCHER')), '50000000-0000-0000-0000-0000000000c1', 'case-insensitive, id as text');
select is((select count(*)::int from public.search_custom_exercises('', 'biceps')), 0, 'muscle filter applies');
select is((select count(*)::int from public.search_custom_exercises('')), 1, 'empty query lists the own exercises');
reset role;

set local role anon;
select throws_ok($$ select * from public.search_custom_exercises('zercher') $$, '42501', null, 'anon cannot call it');
reset role;

select * from finish();
rollback;
