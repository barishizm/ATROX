-- P078 · Conversation memory (docs/04-AI-KOC.md §8).
--   coach_threads.summary / summary_through   rolling summary of the messages that fell out of the 12-message window
--   coach_thread_history()                    now also returns the summary and the not-yet-summarised overflow
--   coach_set_summary()                       stores the summary (only moves forward)
--   coach_save_memory()                       merges duplicate / refined notes instead of adding a second one
--   coach_edit_memory(), coach_delete_memory(), coach_delete_thread(), coach_delete_all_threads()
-- Deleting is permanent (hard delete) and only ever touches the caller's own rows. The tables stay without a DELETE
-- grant (the RLS matrix keeps asserting that); the delete functions are SECURITY DEFINER and filter by auth.uid().

alter table public.coach_threads
  add column summary         text,
  add column summary_through timestamptz,
  add constraint coach_threads_summary_check check (summary is null or length(summary) <= 4000);

-- Lower-case, single-spaced, no trailing punctuation: the key used to spot duplicate notes.
create function public.coach_note_key(p_note text)
returns text
language sql
immutable
set search_path = ''
as $$
  select btrim(regexp_replace(lower(btrim(p_note)), '\s+', ' ', 'g'), ' .!;,');
$$;

create or replace function public.coach_save_memory(p_id uuid, p_note text)
returns jsonb
language plpgsql
volatile
security invoker
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_note text := btrim(p_note);
  v_key text := public.coach_note_key(p_note);
  v_count integer;
  v_existing record;
begin
  -- Same fact again, or the new note says the same thing in fewer words: keep the existing note.
  -- The new note extends/refines an existing one (contains it): replace the old text, no second note.
  for v_existing in
    select m.id, m.note, public.coach_note_key(m.note) as key
    from public.coach_memory m
    where m.user_id = v_uid and m.deleted_at is null
    order by m.created_at
  loop
    if v_existing.key = v_key or (length(v_key) >= 8 and position(v_key in v_existing.key) > 0) then
      return jsonb_build_object('id', v_existing.id, 'note', v_existing.note, 'merged', true,
                                'notes_total', (select count(*) from public.coach_memory
                                                 where user_id = v_uid and deleted_at is null));
    end if;
    if length(v_existing.key) >= 8 and position(v_existing.key in v_key) > 0 then
      update public.coach_memory set note = v_note where id = v_existing.id and user_id = v_uid;
      return jsonb_build_object('id', v_existing.id, 'note', v_note, 'merged', true,
                                'notes_total', (select count(*) from public.coach_memory
                                                 where user_id = v_uid and deleted_at is null));
    end if;
  end loop;

  select count(*) into v_count from public.coach_memory m where m.user_id = v_uid and m.deleted_at is null;
  if v_count >= 20 then
    raise exception 'coach_memory_full' using errcode = 'P0001';
  end if;
  insert into public.coach_memory (id, user_id, note, source) values (p_id, v_uid, v_note, 'coach');
  return jsonb_build_object('id', p_id, 'note', v_note, 'merged', false, 'notes_total', v_count + 1);
end
$$;

-- The user edits a note in Settings; it becomes theirs (source = 'user').
create function public.coach_edit_memory(p_id uuid, p_note text)
returns boolean
language plpgsql
volatile
security invoker
set search_path = ''
as $$
declare
  v_rows integer;
begin
  update public.coach_memory set note = btrim(p_note), source = 'user'
   where id = p_id and user_id = (select auth.uid()) and deleted_at is null;
  get diagnostics v_rows = row_count;
  return v_rows > 0;
end
$$;

create function public.coach_delete_memory(p_id uuid)
returns boolean
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_rows integer;
begin
  delete from public.coach_memory where id = p_id and user_id = (select auth.uid());
  get diagnostics v_rows = row_count;
  return v_rows > 0;
end
$$;

-- Messages go with the thread (foreign key cascade), and so does its summary.
create function public.coach_delete_thread(p_id uuid)
returns boolean
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_rows integer;
begin
  delete from public.coach_threads where id = p_id and user_id = (select auth.uid());
  get diagnostics v_rows = row_count;
  return v_rows > 0;
end
$$;

create function public.coach_delete_all_threads()
returns integer
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_rows integer;
begin
  delete from public.coach_threads where user_id = (select auth.uid());
  get diagnostics v_rows = row_count;
  return v_rows;
end
$$;

-- The summary only moves forward, so a late or repeated summarisation cannot undo a newer one.
create function public.coach_set_summary(p_thread_id uuid, p_summary text, p_through timestamptz)
returns boolean
language plpgsql
volatile
security invoker
set search_path = ''
as $$
declare
  v_rows integer;
begin
  update public.coach_threads
     set summary = left(p_summary, 4000), summary_through = p_through
   where id = p_thread_id and user_id = (select auth.uid()) and deleted_at is null
     and (summary_through is null or summary_through < p_through);
  get diagnostics v_rows = row_count;
  return v_rows > 0;
end
$$;

-- Last p_limit user/assistant messages (oldest first), the thread summary, the overflow (older messages the summary
-- does not cover yet, oldest first, at most 40) and what the duplicate check needs.
create or replace function public.coach_thread_history(p_thread_id uuid, p_limit integer default 12)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  with thread as (
    select t.summary, t.summary_through
    from public.coach_threads t
    where t.id = p_thread_id and t.user_id = (select auth.uid()) and t.deleted_at is null
  ),
  visible as (
    select m.role, m.content, m.status, m.created_at, m.id
    from public.coach_messages m
    where m.thread_id = p_thread_id and m.user_id = (select auth.uid()) and m.deleted_at is null
      and m.role in ('user', 'assistant') and m.content <> ''
  ),
  recent as (
    select * from visible order by created_at desc, id desc limit greatest(least(coalesce(p_limit, 12), 50), 1)
  ),
  overflow as (
    select v.* from visible v
    where not exists (select 1 from recent r where r.id = v.id)
      and v.created_at > coalesce((select summary_through from thread), '-infinity'::timestamptz)
    order by v.created_at, v.id
    limit 40
  ),
  last_user as (
    select content, created_at from visible where role = 'user' order by created_at desc, id desc limit 1
  )
  select jsonb_build_object(
    'messages', coalesce((select jsonb_agg(jsonb_build_object('role', role, 'content', content)
                                           order by created_at, id) from recent), '[]'::jsonb),
    'summary', (select summary from thread),
    'overflow', coalesce((select jsonb_agg(jsonb_build_object('role', role, 'content', content, 'created_at', created_at)
                                           order by created_at, id) from overflow), '[]'::jsonb),
    'last_user_message', (select content from last_user),
    'last_turn_complete', coalesce((
      select v.status = 'complete' from visible v
       where v.role = 'assistant' and v.created_at > (select created_at from last_user)
       order by v.created_at desc, v.id desc limit 1), false)
  );
$$;

revoke all on function public.coach_note_key(text) from public, anon;
revoke all on function public.coach_edit_memory(uuid, text) from public, anon;
revoke all on function public.coach_delete_memory(uuid) from public, anon;
revoke all on function public.coach_delete_thread(uuid) from public, anon;
revoke all on function public.coach_delete_all_threads() from public, anon;
revoke all on function public.coach_set_summary(uuid, text, timestamptz) from public, anon;
grant execute on function public.coach_note_key(text) to authenticated;
grant execute on function public.coach_edit_memory(uuid, text) to authenticated;
grant execute on function public.coach_delete_memory(uuid) to authenticated;
grant execute on function public.coach_delete_thread(uuid) to authenticated;
grant execute on function public.coach_delete_all_threads() to authenticated;
grant execute on function public.coach_set_summary(uuid, text, timestamptz) to authenticated;

-- P079 · A retried turn re-sends the same user message id: the first attempt's rows after that message (a partial
-- answer) are superseded (soft-deleted, the app's retry replaces them) and the message itself is not stored twice.
create or replace function public.coach_save_turn(p_thread_id uuid, p_title text, p_messages jsonb)
returns void
language plpgsql
volatile
security invoker
set search_path = ''
as $$
declare
  v_first uuid := nullif(p_messages -> 0 ->> 'id', '')::uuid;
  v_first_at timestamptz;
begin
  insert into public.coach_threads (id, user_id, title)
  values (p_thread_id, (select auth.uid()), left(p_title, 200))
  on conflict (id) do update set updated_at = now();

  if p_messages -> 0 ->> 'role' = 'user' then
    select created_at into v_first_at from public.coach_messages
     where id = v_first and user_id = (select auth.uid()) and thread_id = p_thread_id;
    if v_first_at is not null then
      update public.coach_messages set deleted_at = now()
       where thread_id = p_thread_id and user_id = (select auth.uid()) and created_at > v_first_at
         and deleted_at is null;
    end if;
  end if;

  insert into public.coach_messages (id, user_id, thread_id, created_at, role, content, tool_calls, proposal,
                                     prompt_tokens, completion_tokens, status)
  select (m.value ->> 'id')::uuid, (select auth.uid()), p_thread_id,
         now() + make_interval(secs => m.ordinality / 1000000.0),
         m.value ->> 'role', left(coalesce(m.value ->> 'content', ''), 20000),
         nullif(m.value -> 'tool_calls', 'null'::jsonb), nullif(m.value -> 'proposal', 'null'::jsonb),
         (m.value ->> 'prompt_tokens')::integer, (m.value ->> 'completion_tokens')::integer,
         coalesce(m.value ->> 'status', 'complete')
  from jsonb_array_elements(p_messages) with ordinality as m (value, ordinality)
  on conflict (id) do nothing;
end
$$;

-- P080 · The user's decision on a proposal card is written onto the stored proposal, so the coach knows on the next
-- turn what happened to it. p_decision: applied | edited | rejected | undone.
create function public.coach_record_decision(p_proposal_id text, p_decision text)
returns boolean
language plpgsql
volatile
security invoker
set search_path = ''
as $$
declare
  v_rows integer;
begin
  if p_decision not in ('applied', 'edited', 'rejected', 'undone') then
    raise exception 'coach_invalid_decision' using errcode = '22023';
  end if;
  update public.coach_messages
     set proposal = proposal || jsonb_build_object('decision', p_decision, 'decided_at', now())
   where user_id = (select auth.uid()) and deleted_at is null and proposal ->> 'id' = p_proposal_id;
  get diagnostics v_rows = row_count;
  return v_rows > 0;
end
$$;

-- The last decisions of a thread (newest 5), for the context. kind + decision only, never the proposal body.
create function public.coach_recent_decisions(p_thread_id uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('kind', kind, 'decision', decision) order by created_at), '[]'::jsonb)
  from (
    select m.proposal ->> 'kind' as kind, m.proposal ->> 'decision' as decision, m.created_at
    from public.coach_messages m
    where m.thread_id = p_thread_id and m.user_id = (select auth.uid()) and m.deleted_at is null
      and m.proposal ->> 'decision' is not null and m.proposal ->> 'kind' <> 'memory_saved'
    order by m.created_at desc limit 5
  ) d;
$$;

revoke all on function public.coach_record_decision(text, text) from public, anon;
revoke all on function public.coach_recent_decisions(uuid) from public, anon;
grant execute on function public.coach_record_decision(text, text) to authenticated;
grant execute on function public.coach_recent_decisions(uuid) to authenticated;
