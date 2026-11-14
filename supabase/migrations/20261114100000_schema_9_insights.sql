-- P069 · insights: what the insight engine found, what was shown and what the user dismissed (docs/02-MIMARI.md §2.3).
--
-- One row per (kind, subject). The client derives a deterministic id from that pair, so two devices that detect the
-- same thing write the same row and last-write-wins resolves them. The coach's `get_insights` tool reads the rows with
-- `is_active`. The row carries no display text: the app renders localized templates from kind + payload.
--   kind      imbalance | plateau | progress_fast | progress_slow | neglected_muscle | push_pull | comeback |
--             bodyweight_stale | rep_range_stuck
--   subject   exercise id / muscle key / rule id / 'global'
--   payload   JSON object with the numbers and names behind the insight (text column, validated as a JSON object)

create table public.insights (
  id             uuid primary key,
  user_id        uuid not null references auth.users (id) on delete cascade,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  deleted_at     timestamptz,

  kind           text not null,
  subject        text not null,
  severity       text not null,
  priority       numeric(6, 2) not null,
  action         text not null,
  payload        text not null default '{}',
  is_active      boolean not null default true,
  detected_at    timestamptz not null,
  last_shown_at  timestamptz,
  dismissed_at   timestamptz,

  constraint insights_id_user_id_key unique (id, user_id),
  constraint insights_kind_check check (kind in (
    'imbalance', 'plateau', 'progress_fast', 'progress_slow', 'neglected_muscle', 'push_pull', 'comeback',
    'bodyweight_stale', 'rep_range_stuck'
  )),
  constraint insights_subject_check check (length(subject) between 1 and 200),
  constraint insights_severity_check check (severity in ('mild', 'moderate', 'severe')),
  constraint insights_action_check check (action in (
    'suggest_exercises', 'ask_coach', 'update_bodyweight', 'view_exercise', 'start_workout'
  )),
  constraint insights_payload_check check (length(payload) <= 4000 and payload like '{%}')
);

create index insights_user_id_updated_at_idx on public.insights (user_id, updated_at);
create index insights_user_active_idx on public.insights (user_id, priority desc) where is_active and deleted_at is null;

create trigger insights_set_updated_at
  before insert or update on public.insights
  for each row execute function public.set_updated_at();

alter table public.insights enable row level security;
revoke all on public.insights from anon, authenticated;
grant select, insert, update on public.insights to authenticated;

create policy insights_select_own on public.insights
  for select to authenticated using (user_id = (select auth.uid()));
create policy insights_insert_own on public.insights
  for insert to authenticated with check (user_id = (select auth.uid()));
create policy insights_update_own on public.insights
  for update to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
