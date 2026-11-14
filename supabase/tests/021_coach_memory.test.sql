-- P078 · conversation memory: rolling summary window, memory merge/limit, edit/delete, permanent deletion, isolation.
begin;
select plan(31);

select tests.create_two_users();

insert into public.coach_threads (id, user_id, title)
values ('78100000-0000-0000-0000-000000000001', tests.user_a(), 'T1'),
       ('78100000-0000-0000-0000-000000000002', tests.user_a(), 'T2'),
       ('78100000-0000-0000-0000-000000000003', tests.user_b(), 'B');
-- 16 messages in T1, one second apart (m00 oldest … m15 newest).
insert into public.coach_messages (id, user_id, thread_id, created_at, role, content)
select ('78200000-0000-0000-0000-0000000000' || lpad(g::text, 2, '0'))::uuid, tests.user_a(),
       '78100000-0000-0000-0000-000000000001', now() - make_interval(secs => 100 - g),
       case when g % 2 = 0 then 'user' else 'assistant' end, 'm' || lpad(g::text, 2, '0')
from generate_series(0, 15) g;
insert into public.coach_messages (id, user_id, thread_id, role, content)
values ('78200000-0000-0000-0000-000000000100', tests.user_a(), '78100000-0000-0000-0000-000000000002', 'user', 'hello T2'),
       ('78200000-0000-0000-0000-000000000101', tests.user_b(), '78100000-0000-0000-0000-000000000003', 'user', 'secret B');

-- ===== Rolling summary window =====
select tests.authenticate_as(tests.user_a());
select is(jsonb_array_length(public.coach_thread_history('78100000-0000-0000-0000-000000000001', 12) -> 'messages'), 12,
  'history: the window holds 12 messages');
select is(jsonb_array_length(public.coach_thread_history('78100000-0000-0000-0000-000000000001', 12) -> 'overflow'), 4,
  'history: the 4 older messages are overflow before any summary');
select is(public.coach_thread_history('78100000-0000-0000-0000-000000000001', 12) -> 'overflow' -> 0 ->> 'content', 'm00',
  'history: overflow starts with the oldest message');

select is(public.coach_set_summary('78100000-0000-0000-0000-000000000001', 'Knee injury, wants 3 days.',
  (select created_at from public.coach_messages where id = '78200000-0000-0000-0000-000000000003')), true,
  'summary: stored');
select is(public.coach_thread_history('78100000-0000-0000-0000-000000000001', 12) ->> 'summary', 'Knee injury, wants 3 days.',
  'history: returns the summary');
select is(jsonb_array_length(public.coach_thread_history('78100000-0000-0000-0000-000000000001', 12) -> 'overflow'), 0,
  'history: summarised messages are no longer overflow');
select is(public.coach_set_summary('78100000-0000-0000-0000-000000000001', 'older',
  (select created_at from public.coach_messages where id = '78200000-0000-0000-0000-000000000001')), false,
  'summary: never moves backwards');
select is(public.coach_set_summary('78100000-0000-0000-0000-000000000003', 'not mine', now()), false,
  'summary: another user''s thread is untouched');

-- ===== Memory merge and limit =====
select is(public.coach_save_memory('78300000-0000-0000-0000-000000000001', 'Left knee hurts on deep squats') ->> 'merged', 'false',
  'memory: first note is new');
select is(public.coach_save_memory('78300000-0000-0000-0000-000000000002', '  left KNEE hurts on deep squats. ') ->> 'merged', 'true',
  'memory: an identical note is merged');
select is((select count(*)::int from public.coach_memory where user_id = tests.user_a()), 1, 'memory: still one note');
select is(public.coach_save_memory('78300000-0000-0000-0000-000000000003',
  'Left knee hurts on deep squats, also on lunges') ->> 'note', 'Left knee hurts on deep squats, also on lunges',
  'memory: a refined note replaces the old text');
select is((select count(*)::int from public.coach_memory where user_id = tests.user_a()), 1, 'memory: refinement did not add a note');
select lives_ok($$select public.coach_save_memory(('78300000-0000-0000-0000-0000000001' || lpad(g::text, 2, '0'))::uuid, 'fact ' || md5(g::text))
  from generate_series(1, 19) g$$, 'memory: fills up to 20 notes');
select throws_ok($$select public.coach_save_memory('78300000-0000-0000-0000-000000000999', 'one fact too many')$$,
  'P0001', 'coach_memory_full', 'memory: the 21st note is refused');

-- ===== User edit / delete =====
select is(public.coach_edit_memory('78300000-0000-0000-0000-000000000001', 'Trains at home'), true, 'memory: user edits a note');
select is((select source from public.coach_memory where id = '78300000-0000-0000-0000-000000000001'), 'user',
  'memory: an edited note becomes the user''s');
select is(public.coach_delete_memory('78300000-0000-0000-0000-000000000001'), true, 'memory: user deletes a note');
select is((select count(*)::int from public.coach_memory where id = '78300000-0000-0000-0000-000000000001'), 0,
  'memory: the note is gone for good (no tombstone)');
select ok(not (public.coach_user_context('en') -> 'memory')::text like '%Trains at home%', 'context: a deleted note is not in the context');

-- ===== Permanent thread deletion and isolation =====
select is(public.coach_delete_thread('78100000-0000-0000-0000-000000000001'), true, 'thread: deleted');
select is((select count(*)::int from public.coach_messages where thread_id = '78100000-0000-0000-0000-000000000001'), 0,
  'thread: messages and summary are gone, nothing is left for the context');
select is(public.coach_delete_thread('78100000-0000-0000-0000-000000000003'), false,
  'thread: another user''s thread cannot be deleted');
select is(public.coach_delete_all_threads(), 1, 'thread: delete-all removes the remaining own thread');
select tests.clear_authentication();
select is((select count(*)::int from public.coach_threads where user_id = tests.user_b()), 1,
  'thread: the other user''s thread survived');

-- ===== P079 retry with the same user message id =====
select tests.authenticate_as(tests.user_a());
select public.coach_save_turn('78100000-0000-0000-0000-000000000002', 'T2', jsonb_build_array(
  jsonb_build_object('id', '78200000-0000-0000-0000-000000000200', 'role', 'user', 'content', 'build a plan'),
  jsonb_build_object('id', '78200000-0000-0000-0000-000000000201', 'role', 'assistant', 'content', 'Here is', 'status', 'partial')));
select public.coach_save_turn('78100000-0000-0000-0000-000000000002', 'T2', jsonb_build_array(
  jsonb_build_object('id', '78200000-0000-0000-0000-000000000200', 'role', 'user', 'content', 'build a plan'),
  jsonb_build_object('id', '78200000-0000-0000-0000-000000000202', 'role', 'assistant', 'content', 'Here is the plan')));
select is((select count(*)::int from public.coach_messages
            where thread_id = '78100000-0000-0000-0000-000000000002' and role = 'user' and content = 'build a plan'), 1,
  'retry: the user message is stored once');
select is((select count(*)::int from public.coach_messages
            where thread_id = '78100000-0000-0000-0000-000000000002' and role = 'assistant' and deleted_at is null), 1,
  'retry: only the new answer is live');
select is(public.coach_thread_history('78100000-0000-0000-0000-000000000002', 12) -> 'messages' -> 1 ->> 'content',
  'Here is the plan', 'retry: history shows the retried answer');

-- ===== P080 decisions =====
insert into public.coach_messages (id, user_id, thread_id, role, content, proposal)
values ('78200000-0000-0000-0000-000000000210', tests.user_a(), '78100000-0000-0000-0000-000000000002', 'tool', '{}',
        '{"id":"prop-1","kind":"routine","data":{}}'),
       ('78200000-0000-0000-0000-000000000211', tests.user_a(), '78100000-0000-0000-0000-000000000002', 'tool', '{}',
        '{"id":"prop-2","kind":"memory_saved","data":{}}');
select is(public.coach_record_decision('prop-1', 'applied'), true, 'decision: recorded on the stored proposal');
select is(public.coach_recent_decisions('78100000-0000-0000-0000-000000000002'),
  '[{"kind": "routine", "decision": "applied"}]'::jsonb, 'decision: the coach sees kind and decision only');
select throws_ok($$select public.coach_record_decision('prop-1', 'maybe')$$, '22023', 'coach_invalid_decision',
  'decision: unknown values are refused');
select tests.clear_authentication();

select * from finish();
rollback;
