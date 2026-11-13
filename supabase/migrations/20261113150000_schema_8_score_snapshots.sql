-- P064 · score_snapshots: point-in-time scores that feed the score-over-time charts (docs/02-MIMARI.md §2.3).
--
-- One row per (scope, key, reference group, day). The client derives a deterministic id from that tuple, so two
-- devices that compute the same snapshot write the same row and last-write-wins resolves them. Rows are owner-only
-- with soft delete, like every synced table.
--   scope            exercise | muscle | overall
--   key              exercise id (catalog) / muscle group key / 'overall'
--   reference_group  gym | general | competitor

create table public.score_snapshots (
  id               uuid primary key,
  user_id          uuid not null references auth.users (id) on delete cascade,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  deleted_at       timestamptz,

  scope            text not null,
  key              text not null,
  reference_group  text not null default 'gym',
  score            numeric(5, 2) not null,
  z                numeric(7, 4) not null,
  confidence       text not null,
  model_version    text not null,
  date             date not null,

  constraint score_snapshots_id_user_id_key unique (id, user_id),
  constraint score_snapshots_scope_check check (scope in ('exercise', 'muscle', 'overall')),
  constraint score_snapshots_key_check check (length(key) between 1 and 200),
  constraint score_snapshots_reference_group_check check (reference_group in ('gym', 'general', 'competitor')),
  constraint score_snapshots_score_check check (score between 0 and 100),
  constraint score_snapshots_confidence_check check (confidence in ('high', 'medium', 'low')),
  constraint score_snapshots_model_version_check check (length(model_version) between 1 and 40)
);

create index score_snapshots_user_id_updated_at_idx on public.score_snapshots (user_id, updated_at);
create index score_snapshots_user_series_idx
  on public.score_snapshots (user_id, scope, key, reference_group, date desc);

create trigger score_snapshots_set_updated_at
  before insert or update on public.score_snapshots
  for each row execute function public.set_updated_at();

alter table public.score_snapshots enable row level security;
revoke all on public.score_snapshots from anon, authenticated;
grant select, insert, update on public.score_snapshots to authenticated;

create policy score_snapshots_select_own on public.score_snapshots
  for select to authenticated using (user_id = (select auth.uid()));
create policy score_snapshots_insert_own on public.score_snapshots
  for insert to authenticated with check (user_id = (select auth.uid()));
create policy score_snapshots_update_own on public.score_snapshots
  for update to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
