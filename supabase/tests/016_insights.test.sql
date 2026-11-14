-- P069 · insights: constraints, owner-only access, no hard delete.
begin;
select plan(10);

select tests.create_two_users();
select has_table('public', 'insights', 'insights exists');

select tests.authenticate_as(tests.user_a());
select lives_ok(format($$
  insert into public.insights (id, user_id, kind, subject, severity, priority, action, payload, detected_at)
  values ('76000000-0000-0000-0000-000000000001', %L, 'plateau', 'barbell-bench-press-medium-grip', 'mild', 51.3,
          'ask_coach', '{"subjects":["barbell-bench-press-medium-grip"]}', now())
$$, tests.user_a()), 'owner inserts an insight');
select throws_ok(format($$
  insert into public.insights (id, user_id, kind, subject, severity, priority, action, detected_at)
  values ('76000000-0000-0000-0000-000000000002', %L, 'horoscope', 'x', 'mild', 1, 'ask_coach', now())
$$, tests.user_a()), '23514', null, 'unknown kind rejected');
select throws_ok(format($$
  insert into public.insights (id, user_id, kind, subject, severity, priority, action, detected_at)
  values ('76000000-0000-0000-0000-000000000003', %L, 'comeback', 'global', 'catastrophic', 1, 'start_workout', now())
$$, tests.user_a()), '23514', null, 'unknown severity rejected');
select throws_ok(format($$
  insert into public.insights (id, user_id, kind, subject, severity, priority, action, payload, detected_at)
  values ('76000000-0000-0000-0000-000000000004', %L, 'comeback', 'global', 'mild', 1, 'start_workout', 'not json', now())
$$, tests.user_a()), '23514', null, 'payload must be a JSON object');

select lives_ok($$ update public.insights set dismissed_at = now() where id = '76000000-0000-0000-0000-000000000001' $$,
  'owner dismisses an insight');
select throws_ok($$ delete from public.insights where id = '76000000-0000-0000-0000-000000000001' $$,
  '42501', null, 'hard delete is not granted');

select tests.authenticate_as(tests.user_b());
select is((select count(*)::int from public.insights), 0, 'another user sees nothing');
select lives_ok($$ update public.insights set is_active = false $$, 'another user update matches no rows');
select tests.authenticate_as(tests.user_a());
select is((select is_active from public.insights where id = '76000000-0000-0000-0000-000000000001'), true,
  'the owner row is untouched');

select * from finish();
rollback;
