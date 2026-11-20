-- Diary logs: constraints and ownership.
begin;
select plan(7);
select tests.create_two_users();

select tests.authenticate_as(tests.user_a());
select lives_ok(
  $$insert into public.diary_logs (id, user_id, kind, at, amount) values (gen_random_uuid(), tests.user_a(), 'water', now(), 250)$$,
  'owner can log water');
select throws_ok(
  $$insert into public.diary_logs (id, user_id, kind, at, amount) values (gen_random_uuid(), tests.user_a(), 'water', now(), 0)$$,
  '23514', null, 'a glass of nothing is rejected');
select throws_ok(
  $$insert into public.diary_logs (id, user_id, kind, at) values (gen_random_uuid(), tests.user_a(), 'mood', now())$$,
  '23514', null, 'unknown kind rejected');
select throws_ok(
  $$insert into public.diary_logs (id, user_id, kind, at, amount) values (gen_random_uuid(), tests.user_a(), 'goal_weight', now(), 5)$$,
  '23514', null, 'absurd goal weight rejected');
select throws_ok(
  $$insert into public.diary_logs (id, user_id, kind, at, ended_at, quantity)
    values (gen_random_uuid(), tests.user_a(), 'fast', now(), now() - interval '1 hour', 16)$$,
  '23514', null, 'a fast cannot end before it starts');
select throws_ok(
  $$insert into public.diary_logs (id, user_id, kind, at, amount) values (gen_random_uuid(), tests.user_b(), 'water', now(), 250)$$,
  '42501', null, 'cannot write another user''s row');

select tests.authenticate_as(tests.user_b());
select is((select count(*)::int from public.diary_logs), 0, 'another user sees nothing');

select * from finish();
rollback;
