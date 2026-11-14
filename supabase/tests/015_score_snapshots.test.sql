-- P064 · score_snapshots: constraints, owner-only access, no hard delete.
begin;
select plan(11);

select tests.create_two_users();
select has_table('public', 'score_snapshots', 'score_snapshots exists');

select tests.authenticate_as(tests.user_a());
select lives_ok(format($$
  insert into public.score_snapshots (id, user_id, scope, key, reference_group, score, z, confidence, model_version, date)
  values ('75000000-0000-0000-0000-000000000001', %L, 'exercise', 'barbell-bench-press-medium-grip', 'gym', 73.4, 0.62,
          'high', '1.0.0', '2026-11-13')
$$, tests.user_a()), 'owner inserts a snapshot');

select throws_ok(format($$
  insert into public.score_snapshots (id, user_id, scope, key, score, z, confidence, model_version, date)
  values ('75000000-0000-0000-0000-000000000002', %L, 'team', 'x', 50, 0, 'high', '1.0.0', '2026-11-13')
$$, tests.user_a()), '23514', null, 'unknown scope rejected');
select throws_ok(format($$
  insert into public.score_snapshots (id, user_id, scope, key, reference_group, score, z, confidence, model_version, date)
  values ('75000000-0000-0000-0000-000000000003', %L, 'overall', 'overall', 'elite', 50, 0, 'high', '1.0.0', '2026-11-13')
$$, tests.user_a()), '23514', null, 'unknown reference group rejected');
select throws_ok(format($$
  insert into public.score_snapshots (id, user_id, scope, key, score, z, confidence, model_version, date)
  values ('75000000-0000-0000-0000-000000000004', %L, 'overall', 'overall', 101, 0, 'high', '1.0.0', '2026-11-13')
$$, tests.user_a()), '23514', null, 'score above 100 rejected');
select throws_ok(format($$
  insert into public.score_snapshots (id, user_id, scope, key, score, z, confidence, model_version, date)
  values ('75000000-0000-0000-0000-000000000005', %L, 'overall', 'overall', 50, 0, 'certain', '1.0.0', '2026-11-13')
$$, tests.user_a()), '23514', null, 'unknown confidence rejected');

select lives_ok($$ update public.score_snapshots set score = 80 where id = '75000000-0000-0000-0000-000000000001' $$,
  'owner updates a snapshot');
select throws_ok($$ delete from public.score_snapshots where id = '75000000-0000-0000-0000-000000000001' $$,
  '42501', null, 'hard delete is not granted');

select tests.authenticate_as(tests.user_b());
select is((select count(*)::int from public.score_snapshots), 0, 'another user sees nothing');
select lives_ok($$ update public.score_snapshots set score = 1 $$, 'another user update matches no rows');
select tests.authenticate_as(tests.user_a());
select is((select score from public.score_snapshots where id = '75000000-0000-0000-0000-000000000001'), 80::numeric,
  'the owner row is untouched');

select * from finish();
rollback;
