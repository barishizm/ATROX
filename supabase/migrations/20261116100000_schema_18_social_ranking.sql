-- P087: published score history (for "this month's progress"), the facts publish-score checks, and the 'month' ranking.

-- One row per user and UTC day: the last score the user published that day. Written only by social_publish.
create table public.social_score_history (
  user_id     uuid not null references public.public_profiles (user_id) on delete cascade,
  day         date not null,
  score       integer not null check (score between 1 and 99),
  provisional boolean not null default false,
  primary key (user_id, day)
);
alter table public.social_score_history enable row level security;
-- No policies and no grants: only security definer functions read or write it.
revoke all on public.social_score_history from public, anon, authenticated;

-- Turning score sharing off removes the published history together with the published score.
create function public.social_clear_history() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if not new.share_score and old.share_score then
    delete from public.social_score_history where user_id = new.user_id;
  end if;
  return new;
end $$;
create trigger public_profiles_clear_history after update of share_score on public.public_profiles
  for each row execute function public.social_clear_history();
revoke all on function public.social_clear_history() from public, anon, authenticated;

-- publish-score now also records the day's score.
create or replace function public.social_publish(p_user uuid, p_score integer, p_provisional boolean, p_weekly integer)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare v_share boolean;
begin
  update public.public_profiles
     set shared_overall_score = case when share_score then p_score end,
         shared_score_provisional = share_score and p_provisional,
         shared_score_updated_at = case when share_score then now() end,
         weekly_workouts = least(greatest(p_weekly, 0), 50),
         updated_at = now()
   where user_id = p_user
  returning share_score into v_share;
  if coalesce(v_share, false) and p_score is not null then
    insert into public.social_score_history (user_id, day, score, provisional)
    values (p_user, (now() at time zone 'utc')::date, p_score, p_provisional)
    on conflict (user_id, day) do update set score = excluded.score, provisional = excluded.provisional;
  end if;
end
$$;

-- What publish-score needs to judge a request, in one round trip. Service role only.
create function public.social_publish_facts(p_user uuid)
returns table (has_profile boolean, share_score boolean, last_score integer, last_provisional boolean,
               last_at timestamptz, workouts_7d integer, completed_sets integer)
language sql
stable
security definer
set search_path = ''
as $$
  select p.user_id is not null, coalesce(p.share_score, false), p.shared_overall_score, p.shared_score_provisional,
         p.shared_score_updated_at,
         (select count(*)::integer from public.workouts w
           where w.user_id = p_user and w.deleted_at is null and w.ended_at is not null
             and w.started_at >= now() - interval '7 days'),
         (select count(*)::integer from public.sets s
           where s.user_id = p_user and s.deleted_at is null and s.is_completed and s.set_type = 'working')
  from (select 1) one
  left join public.public_profiles p on p.user_id = p_user
$$;

-- Ranking by period; 'month' = score now minus the first score published this (UTC) month.
create or replace function public.friends_leaderboard(p_period text)
returns setof public.social_ranking_row
language plpgsql
stable
security definer
set search_path = ''
as $$
declare v_me uuid := public.social_uid();
begin
  if p_period not in ('score', 'weekly', 'month') then raise exception 'invalid_period' using errcode = '22023'; end if;
  return query
    with members as (
      select p.*
      from public.public_profiles p
      where p.user_id = v_me
         or (public.social_are_friends(v_me, p.user_id) and not public.social_is_blocked(v_me, p.user_id))
    ), valued as (
      select m.*,
             case p_period
               when 'score' then case when m.share_score or m.user_id = v_me then m.shared_overall_score end
               when 'weekly' then m.weekly_workouts
               else case when m.share_score and m.shared_overall_score is not null then
                      m.shared_overall_score - coalesce((
                        select h.score from public.social_score_history h
                         where h.user_id = m.user_id and h.day >= date_trunc('month', now() at time zone 'utc')::date
                         order by h.day limit 1), m.shared_overall_score)
                    end end as v
      from members m
    )
    -- Equal values share a rank (rank(), not row_number()); names only order the ties for display.
    select (rank() over (order by v desc nulls last))::integer,
           v.user_id, v.username, v.display_name, v.avatar_emoji, v.avatar_color,
           v.v, case when p_period = 'score' then v.shared_score_provisional else false end, v.user_id = v_me
    from valued v
    order by 1, v.username;
end
$$;

revoke all on function public.social_publish(uuid, integer, boolean, integer), public.social_publish_facts(uuid),
  public.friends_leaderboard(text) from public, anon, authenticated;
grant execute on function public.friends_leaderboard(text) to authenticated;
grant execute on function public.social_publish(uuid, integer, boolean, integer), public.social_publish_facts(uuid) to service_role;
