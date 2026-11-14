-- P072 · AI coach storage (docs/04-AI-KOC.md §2, §3).
--   coach_threads   one conversation
--   coach_messages  its messages; assistant rows carry tool_calls and an optional proposal (jsonb)
--   coach_memory    short notes the coach keeps about the user (the user can edit or delete them)
--   coach_usage     one row per LLM call: provider, tokens, cost, latency. Written only by the Edge Function with the
--                   service role; the owner can read it.
-- The coach-chat function writes messages and usage with the service role; the owner policies below also let the app
-- read its own history and manage notes and threads.

create table public.coach_threads (
  id          uuid primary key,
  user_id     uuid not null references auth.users (id) on delete cascade,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  deleted_at  timestamptz,
  title       text,

  constraint coach_threads_id_user_id_key unique (id, user_id),
  constraint coach_threads_title_check check (title is null or length(title) <= 200)
);
create index coach_threads_user_id_updated_at_idx on public.coach_threads (user_id, updated_at);

create table public.coach_messages (
  id                 uuid primary key,
  user_id            uuid not null references auth.users (id) on delete cascade,
  thread_id          uuid not null,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now(),
  deleted_at         timestamptz,
  role               text not null,
  content            text not null default '',
  tool_calls         jsonb,
  proposal           jsonb,
  prompt_tokens      integer,
  completion_tokens  integer,

  constraint coach_messages_thread_fk foreign key (thread_id, user_id)
    references public.coach_threads (id, user_id) on delete cascade,
  constraint coach_messages_role_check check (role in ('user', 'assistant', 'tool')),
  constraint coach_messages_content_check check (length(content) <= 20000),
  constraint coach_messages_tool_calls_check check (tool_calls is null or jsonb_typeof(tool_calls) = 'array'),
  constraint coach_messages_proposal_check check (proposal is null or jsonb_typeof(proposal) = 'object'),
  constraint coach_messages_tokens_check check (
    coalesce(prompt_tokens, 0) >= 0 and coalesce(completion_tokens, 0) >= 0)
);
create index coach_messages_thread_idx on public.coach_messages (user_id, thread_id, created_at);
create index coach_messages_user_id_updated_at_idx on public.coach_messages (user_id, updated_at);

create table public.coach_memory (
  id          uuid primary key,
  user_id     uuid not null references auth.users (id) on delete cascade,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  deleted_at  timestamptz,
  note        text not null,
  source      text not null default 'coach',

  constraint coach_memory_note_check check (length(note) between 1 and 500),
  constraint coach_memory_source_check check (source in ('coach', 'user'))
);
create index coach_memory_user_id_updated_at_idx on public.coach_memory (user_id, updated_at);

create table public.coach_usage (
  id                 uuid primary key default gen_random_uuid(),
  user_id            uuid not null references auth.users (id) on delete cascade,
  created_at         timestamptz not null default now(),
  thread_id          uuid,
  provider           text not null,
  model              text not null,
  prompt_tokens      integer not null default 0,
  cached_tokens      integer not null default 0,
  completion_tokens  integer not null default 0,
  cost_usd           numeric(12, 6) not null default 0,
  latency_ms         integer not null default 0,
  agent_steps        integer not null default 0,
  status             text not null default 'ok',

  constraint coach_usage_provider_check check (provider in ('openrouter', 'deepseek', 'fake')),
  constraint coach_usage_status_check check (status in ('ok', 'error', 'timeout', 'refused', 'rate_limited')),
  constraint coach_usage_numbers_check check (
    prompt_tokens >= 0 and cached_tokens >= 0 and completion_tokens >= 0
    and cost_usd >= 0 and latency_ms >= 0 and agent_steps >= 0)
);
create index coach_usage_user_created_idx on public.coach_usage (user_id, created_at desc);

create trigger coach_threads_set_updated_at before insert or update on public.coach_threads
  for each row execute function public.set_updated_at();
create trigger coach_messages_set_updated_at before insert or update on public.coach_messages
  for each row execute function public.set_updated_at();
create trigger coach_memory_set_updated_at before insert or update on public.coach_memory
  for each row execute function public.set_updated_at();

alter table public.coach_threads enable row level security;
alter table public.coach_messages enable row level security;
alter table public.coach_memory enable row level security;
alter table public.coach_usage enable row level security;
revoke all on public.coach_threads, public.coach_messages, public.coach_memory, public.coach_usage
  from anon, authenticated;

-- Threads, messages and notes: the owner reads, creates and updates (soft delete); no hard delete.
grant select, insert, update on public.coach_threads, public.coach_messages, public.coach_memory to authenticated;
-- Usage: the owner only reads; inserts come from the service role.
grant select on public.coach_usage to authenticated;

create policy coach_threads_select_own on public.coach_threads
  for select to authenticated using (user_id = (select auth.uid()));
create policy coach_threads_insert_own on public.coach_threads
  for insert to authenticated with check (user_id = (select auth.uid()));
create policy coach_threads_update_own on public.coach_threads
  for update to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));

create policy coach_messages_select_own on public.coach_messages
  for select to authenticated using (user_id = (select auth.uid()));
create policy coach_messages_insert_own on public.coach_messages
  for insert to authenticated with check (user_id = (select auth.uid()));
create policy coach_messages_update_own on public.coach_messages
  for update to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));

create policy coach_memory_select_own on public.coach_memory
  for select to authenticated using (user_id = (select auth.uid()));
create policy coach_memory_insert_own on public.coach_memory
  for insert to authenticated with check (user_id = (select auth.uid()));
create policy coach_memory_update_own on public.coach_memory
  for update to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));

create policy coach_usage_select_own on public.coach_usage
  for select to authenticated using (user_id = (select auth.uid()));
