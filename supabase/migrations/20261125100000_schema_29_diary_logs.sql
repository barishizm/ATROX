-- Diary logs: the small per-day facts of the calorie diary, one table keyed by `kind` (synced like food_entries:
-- client uuid, soft delete, last write wins).
--   water        amount = millilitres
--   activity     amount = kcal burned, quantity = minutes, label = activity name
--   steps        amount = kcal burned, quantity = steps
--   note         label = mood, text = the note
--   fast         at = start, ended_at = end (null while running), quantity = planned hours, label = plan name
--   goal_weight  amount = kilograms (the newest row by `at` is the goal)

create table public.diary_logs (
  id          uuid primary key,
  user_id     uuid not null references auth.users (id) on delete cascade,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  deleted_at  timestamptz,

  kind        text not null,
  at          timestamptz not null,
  ended_at    timestamptz,
  amount      numeric(8, 1) not null default 0,
  quantity    numeric(8, 1) not null default 0,
  label       text not null default '',
  text        text not null default '',

  constraint diary_logs_id_user_id_key unique (id, user_id),
  constraint diary_logs_kind_check check (kind in ('water', 'activity', 'steps', 'note', 'fast', 'goal_weight')),
  constraint diary_logs_amount_check check (amount between 0 and 10000),
  constraint diary_logs_quantity_check check (quantity between 0 and 100000),
  constraint diary_logs_label_check check (length(label) <= 80),
  constraint diary_logs_text_check check (length(text) <= 2000),
  constraint diary_logs_ended_check check (ended_at is null or ended_at >= at),
  constraint diary_logs_water_check check (kind <> 'water' or (amount > 0 and amount <= 5000)),
  constraint diary_logs_goal_weight_check check (kind <> 'goal_weight' or amount between 20 and 400)
);
create index diary_logs_user_id_updated_at_idx on public.diary_logs (user_id, updated_at);
create index diary_logs_user_kind_at_idx on public.diary_logs (user_id, kind, at desc) where deleted_at is null;

create trigger diary_logs_set_updated_at
  before insert or update on public.diary_logs
  for each row execute function public.set_updated_at();

alter table public.diary_logs enable row level security;
revoke all on public.diary_logs from anon, authenticated;
grant select, insert, update on public.diary_logs to authenticated;

create policy diary_logs_select_own on public.diary_logs
  for select to authenticated using (user_id = (select auth.uid()));
create policy diary_logs_insert_own on public.diary_logs
  for insert to authenticated with check (user_id = (select auth.uid()));
create policy diary_logs_update_own on public.diary_logs
  for update to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
