-- P076 · What the coach's agent loop needs from Postgres (docs/04-AI-KOC.md §5, §8).
--   coach_messages.status        complete | partial (the turn failed or was cut off mid-way)
--   coach_lookup_exercises()     catalog/custom facts used to validate proposals (equipment, pattern)
--   coach_save_memory()          the save_memory tool (at most 20 active notes)
--   coach_thread_history()       last messages of a thread for the context window
--   coach_save_turn()            one turn's messages (user, assistant, tool traces) in one call
-- All SECURITY INVOKER: coach-chat calls them with the user's JWT, so RLS keeps every row the caller's own.

alter table public.coach_messages
  add column status text not null default 'complete',
  add constraint coach_messages_status_check check (status in ('complete', 'partial'));

create function public.coach_lookup_exercises(p_ids text[], p_locale text default 'en')
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(x), '[]'::jsonb)
  from (
    select jsonb_build_object('id', e.id, 'name', public.coach_exercise_name(e.id, null, p_locale),
                              'equipment', e.equipment, 'movement_pattern', e.movement_pattern, 'custom', false) as x
    from public.exercises e
    where e.id = any (p_ids) and e.archived_at is null
    union all
    select jsonb_build_object('id', c.id::text, 'name', c.name, 'equipment', c.equipment,
                              'movement_pattern', c.movement_pattern, 'custom', true)
    from public.custom_exercises c
    where c.deleted_at is null
      and c.id::text = any (p_ids)
  ) t;
$$;

create function public.coach_save_memory(p_id uuid, p_note text)
returns jsonb
language plpgsql
volatile
security invoker
set search_path = ''
as $$
declare
  v_count integer;
begin
  select count(*) into v_count from public.coach_memory m
   where m.user_id = (select auth.uid()) and m.deleted_at is null;
  if v_count >= 20 then
    raise exception 'coach_memory_full' using errcode = 'P0001';
  end if;
  insert into public.coach_memory (id, user_id, note, source)
  values (p_id, (select auth.uid()), btrim(p_note), 'coach');
  return jsonb_build_object('id', p_id, 'note', btrim(p_note), 'notes_total', v_count + 1);
end
$$;

-- Last p_limit user/assistant messages (oldest first) plus what the duplicate check needs.
create function public.coach_thread_history(p_thread_id uuid, p_limit integer default 12)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  with visible as (
    select m.role, m.content, m.status, m.created_at, m.id
    from public.coach_messages m
    where m.thread_id = p_thread_id and m.user_id = (select auth.uid()) and m.deleted_at is null
      and m.role in ('user', 'assistant') and m.content <> ''
  ),
  recent as (
    select * from visible order by created_at desc, id desc limit greatest(least(coalesce(p_limit, 12), 50), 1)
  ),
  last_user as (
    select content, created_at from visible where role = 'user' order by created_at desc, id desc limit 1
  )
  select jsonb_build_object(
    'messages', coalesce((select jsonb_agg(jsonb_build_object('role', role, 'content', content)
                                           order by created_at, id) from recent), '[]'::jsonb),
    'last_user_message', (select content from last_user),
    'last_turn_complete', coalesce((
      select v.status = 'complete' from visible v
       where v.role = 'assistant' and v.created_at > (select created_at from last_user)
       order by v.created_at desc, v.id desc limit 1), false)
  );
$$;

-- p_messages: [{id, role, content, tool_calls?, proposal?, prompt_tokens?, completion_tokens?, status?}, ...] in order.
create function public.coach_save_turn(p_thread_id uuid, p_title text, p_messages jsonb)
returns void
language plpgsql
volatile
security invoker
set search_path = ''
as $$
begin
  insert into public.coach_threads (id, user_id, title)
  values (p_thread_id, (select auth.uid()), left(p_title, 200))
  on conflict (id) do update set updated_at = now();

  insert into public.coach_messages (id, user_id, thread_id, created_at, role, content, tool_calls, proposal,
                                     prompt_tokens, completion_tokens, status)
  select (m.value ->> 'id')::uuid, (select auth.uid()), p_thread_id,
         -- one transaction shares now(); the ordinal keeps the turn's order stable
         now() + make_interval(secs => m.ordinality / 1000000.0),
         m.value ->> 'role', left(coalesce(m.value ->> 'content', ''), 20000),
         nullif(m.value -> 'tool_calls', 'null'::jsonb), nullif(m.value -> 'proposal', 'null'::jsonb),
         (m.value ->> 'prompt_tokens')::integer, (m.value ->> 'completion_tokens')::integer,
         coalesce(m.value ->> 'status', 'complete')
  from jsonb_array_elements(p_messages) with ordinality as m (value, ordinality);
end
$$;

revoke all on function public.coach_lookup_exercises(text[], text) from public, anon;
revoke all on function public.coach_save_memory(uuid, text) from public, anon;
revoke all on function public.coach_thread_history(uuid, integer) from public, anon;
revoke all on function public.coach_save_turn(uuid, text, jsonb) from public, anon;
grant execute on function public.coach_lookup_exercises(text[], text) to authenticated;
grant execute on function public.coach_save_memory(uuid, text) to authenticated;
grant execute on function public.coach_thread_history(uuid, integer) to authenticated;
grant execute on function public.coach_save_turn(uuid, text, jsonb) to authenticated;
