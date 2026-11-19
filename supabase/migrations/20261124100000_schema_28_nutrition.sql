-- Food-photo calorie tracking (docs/superpowers/specs/2026-11-19-food-calorie-tracking-design.md).
--   food_entries       one logged meal/food per row (synced like workouts: client uuid, soft delete, LWW)
--   nutrition_targets  one row per user: calorie/macro target, auto (from goal) or manual
--   food_analyses      ledger of successful AI analyses, the source of the daily quota. Service role writes.
--   food_allowance()   free 3/day, Pro 60/day (soft cap)
--   food_has_consent() latest food_ai_sharing consent is granted for the given version
-- Photos are never stored on the server: only the numbers of the saved entry.

alter table public.consents drop constraint consents_kind_check;
alter table public.consents add constraint consents_kind_check
  check (kind in ('terms', 'privacy', 'ai_sharing', 'ml_contribution', 'food_ai_sharing'));

create table public.food_entries (
  id          uuid primary key,
  user_id     uuid not null references auth.users (id) on delete cascade,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  deleted_at  timestamptz,

  eaten_at    timestamptz not null,
  meal        text not null,
  name        text not null,
  calories    numeric(7, 1) not null,
  protein_g   numeric(6, 1) not null default 0,
  carbs_g     numeric(6, 1) not null default 0,
  fat_g       numeric(6, 1) not null default 0,
  grams       numeric(7, 1),
  source      text not null,
  -- JSON array of the foods behind the entry (names and numbers), validated as an array.
  items       text not null default '[]',

  constraint food_entries_id_user_id_key unique (id, user_id),
  constraint food_entries_meal_check check (meal in ('breakfast', 'lunch', 'dinner', 'snack')),
  constraint food_entries_name_check check (length(name) between 1 and 120),
  constraint food_entries_calories_check check (calories between 0 and 20000),
  constraint food_entries_macros_check check (
    protein_g between 0 and 2000 and carbs_g between 0 and 2000 and fat_g between 0 and 2000),
  constraint food_entries_grams_check check (grams is null or grams between 0 and 20000),
  constraint food_entries_source_check check (source in ('photo', 'text', 'barcode', 'manual')),
  constraint food_entries_items_check check (length(items) <= 8000 and items like '[%]')
);
create index food_entries_user_id_updated_at_idx on public.food_entries (user_id, updated_at);
create index food_entries_user_eaten_idx on public.food_entries (user_id, eaten_at desc) where deleted_at is null;

create table public.nutrition_targets (
  id          uuid primary key,
  user_id     uuid not null references auth.users (id) on delete cascade,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  deleted_at  timestamptz,

  mode        text not null,
  calories    integer not null,
  protein_g   integer not null,
  carbs_g     integer not null,
  fat_g       integer not null,
  activity    text not null default 'moderate',

  constraint nutrition_targets_id_user_id_key unique (id, user_id),
  constraint nutrition_targets_user_key unique (user_id),
  constraint nutrition_targets_mode_check check (mode in ('auto', 'manual')),
  constraint nutrition_targets_calories_check check (calories between 800 and 10000),
  constraint nutrition_targets_macros_check check (
    protein_g between 0 and 1000 and carbs_g between 0 and 2000 and fat_g between 0 and 1000),
  constraint nutrition_targets_activity_check check (activity in ('sedentary', 'light', 'moderate', 'active', 'very_active'))
);
create index nutrition_targets_user_id_updated_at_idx on public.nutrition_targets (user_id, updated_at);

create trigger food_entries_set_updated_at
  before insert or update on public.food_entries
  for each row execute function public.set_updated_at();
create trigger nutrition_targets_set_updated_at
  before insert or update on public.nutrition_targets
  for each row execute function public.set_updated_at();

alter table public.food_entries enable row level security;
alter table public.nutrition_targets enable row level security;
revoke all on public.food_entries, public.nutrition_targets from anon, authenticated;
grant select, insert, update on public.food_entries, public.nutrition_targets to authenticated;

create policy food_entries_select_own on public.food_entries
  for select to authenticated using (user_id = (select auth.uid()));
create policy food_entries_insert_own on public.food_entries
  for insert to authenticated with check (user_id = (select auth.uid()));
create policy food_entries_update_own on public.food_entries
  for update to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));

create policy nutrition_targets_select_own on public.nutrition_targets
  for select to authenticated using (user_id = (select auth.uid()));
create policy nutrition_targets_insert_own on public.nutrition_targets
  for insert to authenticated with check (user_id = (select auth.uid()));
create policy nutrition_targets_update_own on public.nutrition_targets
  for update to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));

create table public.food_analyses (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references auth.users (id) on delete cascade,
  created_at  timestamptz not null default now(),
  kind        text not null,

  constraint food_analyses_kind_check check (kind in ('photo', 'text'))
);
create index food_analyses_user_created_idx on public.food_analyses (user_id, created_at desc);

alter table public.food_analyses enable row level security;
revoke all on public.food_analyses from anon, authenticated;
grant select on public.food_analyses to authenticated;
create policy food_analyses_select_own on public.food_analyses
  for select to authenticated using (user_id = (select auth.uid()));

-- {tier, allowed, reason: null | 'daily', used, limit}. Free 3/day, Pro 60/day. Counted on successful analyses.
create function public.food_allowance(p_user uuid, p_time_zone text default 'UTC')
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tz    text := case when exists (select 1 from pg_catalog.pg_timezone_names where name = p_time_zone)
                       then p_time_zone else 'UTC' end;
  v_start timestamptz := date_trunc('day', now() at time zone v_tz) at time zone v_tz;
  v_tier  text;
  v_limit integer;
  v_used  integer;
begin
  select coalesce((select e.tier from public.entitlements e
                    where e.user_id = p_user and (e.expires_at is null or e.expires_at > now())), 'free')
    into v_tier;
  v_limit := case v_tier when 'pro' then 60 else 3 end;
  select count(*) into v_used from public.food_analyses a where a.user_id = p_user and a.created_at >= v_start;
  return jsonb_build_object('tier', v_tier, 'allowed', v_used < v_limit,
    'reason', case when v_used < v_limit then null else 'daily' end, 'used', v_used, 'limit', v_limit);
end
$$;

create function public.food_has_consent(p_version text)
returns boolean
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce((
    select c.granted and c.version = p_version
    from public.consents c
    where c.user_id = (select auth.uid()) and c.kind = 'food_ai_sharing'
    order by c.created_at desc, c.id desc
    limit 1), false);
$$;

revoke all on function public.food_allowance(uuid, text) from public, anon, authenticated;
grant execute on function public.food_allowance(uuid, text) to service_role;
revoke all on function public.food_has_consent(text) from public, anon;
grant execute on function public.food_has_consent(text) to authenticated;

-- Coach read tool get_nutrition_summary(days): the user's target and per-day totals. SECURITY INVOKER with the user's
-- JWT like the other coach_* functions, so RLS applies. Entry names are left out (user text, no need for the coach).
create function public.coach_nutrition_summary(p_days integer default 7, p_time_zone text default 'UTC')
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_tz    text := case when exists (select 1 from pg_catalog.pg_timezone_names where name = p_time_zone)
                       then p_time_zone else 'UTC' end;
  v_days  integer := greatest(least(coalesce(p_days, 7), 30), 1);
  v_start timestamptz := (date_trunc('day', now() at time zone v_tz) - make_interval(days => v_days - 1)) at time zone v_tz;
begin
  return jsonb_build_object(
    'target', (select jsonb_build_object('mode', t.mode, 'calories', t.calories, 'protein_g', t.protein_g,
                                          'carbs_g', t.carbs_g, 'fat_g', t.fat_g)
               from public.nutrition_targets t
               where t.user_id = (select auth.uid()) and t.deleted_at is null),
    'days', coalesce((
      select jsonb_agg(d order by d.day)
      from (
        select (f.eaten_at at time zone v_tz)::date as day,
               round(sum(f.calories), 0) as calories,
               round(sum(f.protein_g), 0) as protein_g,
               round(sum(f.carbs_g), 0) as carbs_g,
               round(sum(f.fat_g), 0) as fat_g,
               count(*) as entries
        from public.food_entries f
        where f.user_id = (select auth.uid()) and f.deleted_at is null and f.eaten_at >= v_start
        group by 1
      ) d), '[]'::jsonb));
end
$$;

revoke all on function public.coach_nutrition_summary(integer, text) from public, anon;
grant execute on function public.coach_nutrition_summary(integer, text) to authenticated;
