-- P072 · coach tables: constraints, owner-only access, service-role-only usage writes.
begin;
select plan(13);

select tests.create_two_users();

select tests.authenticate_as(tests.user_a());
select lives_ok(format($$
  insert into public.coach_threads (id, user_id, title) values ('77000000-0000-0000-0000-000000000001', %L, 'Plan')
$$, tests.user_a()), 'owner creates a thread');
select lives_ok(format($$
  insert into public.coach_messages (id, user_id, thread_id, role, content, tool_calls, proposal)
  values ('77000000-0000-0000-0000-000000000011', %L, '77000000-0000-0000-0000-000000000001', 'assistant', 'Hi',
          '[{"name":"get_scores"}]', '{"kind":"routine"}')
$$, tests.user_a()), 'owner stores a message with tool calls and a proposal');
select throws_ok(format($$
  insert into public.coach_messages (id, user_id, thread_id, role, content)
  values ('77000000-0000-0000-0000-000000000012', %L, '77000000-0000-0000-0000-000000000001', 'system', 'x')
$$, tests.user_a()), '23514', null, 'unknown role rejected');
select throws_ok(format($$
  insert into public.coach_messages (id, user_id, thread_id, role, content, tool_calls)
  values ('77000000-0000-0000-0000-000000000013', %L, '77000000-0000-0000-0000-000000000001', 'assistant', 'x', '{}')
$$, tests.user_a()), '23514', null, 'tool_calls must be an array');
select throws_ok(format($$
  insert into public.coach_messages (id, user_id, thread_id, role, content)
  values ('77000000-0000-0000-0000-000000000014', %L, '77000000-0000-0000-0000-0000000000ff', 'user', 'x')
$$, tests.user_a()), '23503', null, 'message needs an existing thread of the same user');
select lives_ok(format($$
  insert into public.coach_memory (id, user_id, note, source) values ('77000000-0000-0000-0000-000000000021', %L, 'Left knee: avoid deep squats', 'coach')
$$, tests.user_a()), 'owner stores a memory note');
select throws_ok(format($$
  insert into public.coach_memory (id, user_id, note) values ('77000000-0000-0000-0000-000000000022', %L, '')
$$, tests.user_a()), '23514', null, 'empty note rejected');
select throws_ok($$ delete from public.coach_threads $$, '42501', null, 'hard delete is not granted');

-- usage: the owner cannot write, the service role can, the owner reads it
select throws_ok(format($$
  insert into public.coach_usage (user_id, provider, model) values (%L, 'fake', 'm')
$$, tests.user_a()), '42501', null, 'owner cannot insert usage');
select tests.clear_authentication();
set local role service_role;
select lives_ok(format($$
  insert into public.coach_usage (user_id, thread_id, provider, model, prompt_tokens, cached_tokens, completion_tokens, cost_usd, latency_ms, agent_steps)
  values (%L, '77000000-0000-0000-0000-000000000001', 'openrouter', 'deepseek/deepseek-v4.1-flash', 3000, 2500, 400, 0.000471, 900, 2)
$$, tests.user_a()), 'service role writes usage');
reset role;
select tests.authenticate_as(tests.user_a());
select is((select count(*)::int from public.coach_usage), 1, 'owner reads own usage');

select tests.authenticate_as(tests.user_b());
select is((select count(*)::int from public.coach_threads) + (select count(*)::int from public.coach_messages)
        + (select count(*)::int from public.coach_memory) + (select count(*)::int from public.coach_usage), 0,
  'another user sees nothing');
select tests.authenticate_as(tests.user_a());
select throws_ok($$ update public.coach_usage set cost_usd = 0 $$, '42501', null, 'owner cannot rewrite usage');

select * from finish();
rollback;
