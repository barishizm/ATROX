-- P085 · Social layer: public profiles, friendships, reports and the security definer functions around them.
--   public_profiles     one opt-in row per user; the only place a score ever leaves the owner's data (no photos,
--                       avatar is an emoji + colour, so there is no moderation backlog).
--   friendships         one row per unordered pair: pending | accepted | blocked (requester = the blocker).
--   reports             user reports (App Store user-generated-content rule); the reporter reads their own.
--   social_rate_limits  per-user fixed-window counters (search, username checks).
-- Clients never write these tables directly: every write goes through a function that checks auth.uid().

-- ---------------------------------------------------------------- username / text policy
-- Reserved handles and a small TR/EN blocklist. The same list ships in the app (SocialTextPolicy) for instant
-- feedback; this one is the authority. Matching is on a normalised form (lowercase, leetspeak and Turkish letters
-- folded, separators removed).
create function public.social_normalize(p_text text)
returns text
language sql
immutable
set search_path = ''
as $$
  select regexp_replace(
    translate(lower(p_text), '0134578@$ıİğüşöç', 'oieastbasiigusoc'),
    '[^a-z0-9]', '', 'g')
$$;

create function public.social_text_ok(p_text text)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select not exists (
    select 1
    from unnest(array[
      'fuck', 'shit', 'bitch', 'cunt', 'nigg', 'faggot', 'whore', 'rapist', 'nazi', 'hitler',
      'amk', 'aq', 'orospu', 'sikik', 'siktir', 'yarrak', 'amcik', 'pezevenk', 'ibne', 'gavat', 'got'
    ]) w
    where w in ('amk', 'aq', 'got')
        and public.social_normalize(p_text) ~ ('(^|[^a-z])' || w || '([^a-z]|$)')
       or (w not in ('amk', 'aq', 'got') and public.social_normalize(p_text) like '%' || w || '%')
  )
$$;

create function public.social_username_ok(p_username text)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select p_username ~ '^[a-z0-9_]{3,20}$'
     and p_username <> all (array[
       'admin', 'administrator', 'atrox', 'support', 'help', 'moderator', 'mod', 'staff', 'team', 'official',
       'system', 'root', 'null', 'undefined', 'anonymous', 'coach', 'ai', 'apple', 'google', 'security', 'billing'
     ])
     and public.social_text_ok(p_username)
$$;

-- ---------------------------------------------------------------- tables
create table public.public_profiles (
  user_id                 uuid primary key references auth.users (id) on delete cascade,
  id                      uuid not null default gen_random_uuid() unique,
  created_at              timestamptz not null default now(),
  updated_at              timestamptz not null default now(),
  username                text not null,
  display_name            text not null,
  avatar_emoji            text not null default '💪',
  avatar_color            text not null default 'ember',
  is_discoverable         boolean not null default false,
  share_score             boolean not null default false,
  shared_overall_score    integer,
  shared_score_provisional boolean not null default false,
  shared_score_updated_at timestamptz,
  weekly_workouts         integer not null default 0,

  constraint public_profiles_username_check check (public.social_username_ok(username)),
  constraint public_profiles_display_name_check
    check (char_length(display_name) between 1 and 30 and public.social_text_ok(display_name)),
  constraint public_profiles_avatar_emoji_check check (char_length(avatar_emoji) between 1 and 8),
  constraint public_profiles_avatar_color_check
    check (avatar_color in ('ember', 'sky', 'mint', 'violet', 'gold', 'rose', 'slate')),
  constraint public_profiles_score_check check (shared_overall_score is null or shared_overall_score between 1 and 99),
  constraint public_profiles_share_check check (share_score or shared_overall_score is null),
  constraint public_profiles_weekly_check check (weekly_workouts between 0 and 50)
);
create unique index public_profiles_username_key on public.public_profiles (username);
create index public_profiles_username_prefix_idx on public.public_profiles (username text_pattern_ops);

create table public.friendships (
  id            uuid primary key default gen_random_uuid(),
  requester_id  uuid not null references auth.users (id) on delete cascade,
  addressee_id  uuid not null references auth.users (id) on delete cascade,
  status        text not null default 'pending',
  created_at    timestamptz not null default now(),
  responded_at  timestamptz,

  constraint friendships_status_check check (status in ('pending', 'accepted', 'blocked')),
  constraint friendships_distinct_check check (requester_id <> addressee_id)
);
-- One row per unordered pair, so A→B and B→A can never both exist.
create unique index friendships_pair_key on public.friendships (least(requester_id, addressee_id), greatest(requester_id, addressee_id));
create index friendships_addressee_idx on public.friendships (addressee_id, status);
create index friendships_requester_idx on public.friendships (requester_id, status);

create table public.reports (
  id           uuid primary key default gen_random_uuid(),
  created_at   timestamptz not null default now(),
  reporter_id  uuid not null references auth.users (id) on delete cascade,
  reported_id  uuid not null references auth.users (id) on delete cascade,
  reason       text not null,
  note         text,

  constraint reports_reason_check check (reason in ('inappropriate_name', 'harassment', 'spam', 'fake_score', 'other')),
  constraint reports_note_check check (note is null or char_length(note) <= 500),
  constraint reports_distinct_check check (reporter_id <> reported_id)
);
create index reports_reported_idx on public.reports (reported_id, created_at desc);

create table public.social_rate_limits (
  user_id       uuid not null references auth.users (id) on delete cascade,
  bucket        text not null default 'search',
  window_start  timestamptz not null default now(),
  hits          integer not null default 0,
  primary key (user_id, bucket)
);

-- ---------------------------------------------------------------- helpers (security definer: no RLS recursion)
create function public.social_is_blocked(p_a uuid, p_b uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.friendships f
    where f.status = 'blocked'
      and ((f.requester_id = p_a and f.addressee_id = p_b) or (f.requester_id = p_b and f.addressee_id = p_a)))
$$;

create function public.social_are_friends(p_a uuid, p_b uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.friendships f
    where f.status = 'accepted'
      and ((f.requester_id = p_a and f.addressee_id = p_b) or (f.requester_id = p_b and f.addressee_id = p_a)))
$$;

-- Fixed-window counter; raises 'rate_limited' (P0001-style custom code 54000) once the window is used up.
create function public.social_hit(p_user uuid, p_bucket text, p_limit integer, p_window interval)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare v_hits integer;
begin
  insert into public.social_rate_limits as r (user_id, bucket, window_start, hits)
  values (p_user, p_bucket, now(), 1)
  on conflict (user_id, bucket) do update
    set window_start = case when r.window_start <= now() - p_window then now() else r.window_start end,
        hits = case when r.window_start <= now() - p_window then 1 else r.hits + 1 end
  returning hits into v_hits;
  if v_hits > p_limit then
    raise exception 'rate_limited' using errcode = '54000';
  end if;
end
$$;

create function public.social_uid()
returns uuid
language plpgsql
stable
set search_path = ''
as $$
declare v uuid := (select auth.uid());
begin
  if v is null then raise exception 'not_authenticated' using errcode = '28000'; end if;
  return v;
end
$$;

-- ---------------------------------------------------------------- RLS
alter table public.public_profiles enable row level security;
alter table public.friendships enable row level security;
alter table public.reports enable row level security;
alter table public.social_rate_limits enable row level security;

revoke all on public.public_profiles, public.friendships, public.reports, public.social_rate_limits from anon, authenticated;
grant select on public.public_profiles, public.friendships, public.reports, public.social_rate_limits to authenticated;

-- A profile is readable by its owner, by accepted friends, and by anyone when it is discoverable; a block cuts both ways.
create policy public_profiles_select on public.public_profiles
  for select to authenticated
  using (
    user_id = (select auth.uid())
    or (
      not public.social_is_blocked((select auth.uid()), user_id)
      and (is_discoverable or public.social_are_friends((select auth.uid()), user_id))
    )
  );

create policy friendships_select_parties on public.friendships
  for select to authenticated
  using (requester_id = (select auth.uid()) or addressee_id = (select auth.uid()));

create policy reports_select_own on public.reports
  for select to authenticated using (reporter_id = (select auth.uid()));

create policy social_rate_limits_select_own on public.social_rate_limits
  for select to authenticated using (user_id = (select auth.uid()));

-- ---------------------------------------------------------------- functions the app calls
-- Shape returned by the list/search functions.
create type public.social_person as (
  user_id       uuid,
  username      text,
  display_name  text,
  avatar_emoji  text,
  avatar_color  text,
  relation      text,      -- none | friend | incoming | outgoing | blocked
  shared_overall_score integer,
  shared_score_provisional boolean,
  weekly_workouts integer
);

create function public.username_available(p_username text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare v_me uuid := public.social_uid(); v_name text := lower(btrim(p_username));
begin
  perform public.social_hit(v_me, 'username_check', 60, interval '1 minute');
  if not public.social_username_ok(v_name) then return false; end if;
  return not exists (select 1 from public.public_profiles p where p.username = v_name and p.user_id <> v_me);
end
$$;

create function public.upsert_my_profile(
  p_username text, p_display_name text, p_avatar_emoji text, p_avatar_color text,
  p_is_discoverable boolean, p_share_score boolean)
returns public.public_profiles
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_me   uuid := public.social_uid();
  v_name text := lower(btrim(p_username));
  v_disp text := btrim(p_display_name);
  v_row  public.public_profiles;
begin
  if not public.social_username_ok(v_name) then raise exception 'invalid_username' using errcode = '22023'; end if;
  if char_length(v_disp) not between 1 and 30 or not public.social_text_ok(v_disp) then
    raise exception 'invalid_display_name' using errcode = '22023';
  end if;
  begin
    insert into public.public_profiles as p (user_id, username, display_name, avatar_emoji, avatar_color,
                                              is_discoverable, share_score)
    values (v_me, v_name, v_disp, coalesce(nullif(p_avatar_emoji, ''), '💪'), coalesce(nullif(p_avatar_color, ''), 'ember'),
            coalesce(p_is_discoverable, false), coalesce(p_share_score, false))
    on conflict (user_id) do update
      set username = excluded.username, display_name = excluded.display_name,
          avatar_emoji = excluded.avatar_emoji, avatar_color = excluded.avatar_color,
          is_discoverable = excluded.is_discoverable, share_score = excluded.share_score,
          -- turning sharing off withdraws the published score immediately
          shared_overall_score = case when excluded.share_score then p.shared_overall_score end,
          shared_score_provisional = case when excluded.share_score then p.shared_score_provisional else false end,
          shared_score_updated_at = case when excluded.share_score then p.shared_score_updated_at end,
          updated_at = now()
    returning * into v_row;
  exception when unique_violation then
    raise exception 'username_taken' using errcode = '23505';
  end;
  return v_row;
end
$$;

-- "Turn social off": removes the profile and every friendship / request / block involving the caller.
-- Reports are kept (moderation evidence); they disappear with the account.
create function public.delete_my_profile()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare v_me uuid := public.social_uid();
begin
  delete from public.friendships where requester_id = v_me or addressee_id = v_me;
  delete from public.public_profiles where user_id = v_me;
end
$$;

create function public.search_users(p_query text)
returns setof public.social_person
language plpgsql
security definer
set search_path = ''
as $$
declare v_me uuid := public.social_uid(); v_q text := lower(btrim(p_query));
begin
  if char_length(v_q) < 2 or v_q !~ '^[a-z0-9_]+$' then return; end if;
  perform public.social_hit(v_me, 'search', 30, interval '1 minute');
  if not exists (select 1 from public.public_profiles where user_id = v_me) then return; end if;
  return query
    select p.user_id, p.username, p.display_name, p.avatar_emoji, p.avatar_color,
           case when f.id is null then 'none'
                when f.status = 'accepted' then 'friend'
                when f.requester_id = v_me then 'outgoing' else 'incoming' end,
           null::integer, false, null::integer
    from public.public_profiles p
    left join public.friendships f
      on least(f.requester_id, f.addressee_id) = least(p.user_id, v_me)
     and greatest(f.requester_id, f.addressee_id) = greatest(p.user_id, v_me)
    where p.is_discoverable
      and p.user_id <> v_me
      and p.username like v_q || '%'
      and not public.social_is_blocked(v_me, p.user_id)
    order by p.username
    limit 20;
end
$$;

create function public.send_request(p_addressee uuid)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare v_me uuid := public.social_uid(); v_f public.friendships;
begin
  perform public.social_hit(v_me, 'request', 30, interval '1 hour');
  if p_addressee = v_me then raise exception 'invalid_target' using errcode = '22023'; end if;
  if not exists (select 1 from public.public_profiles where user_id = v_me)
     or not exists (select 1 from public.public_profiles where user_id = p_addressee) then
    raise exception 'profile_required' using errcode = '22023';
  end if;
  if public.social_is_blocked(v_me, p_addressee) then raise exception 'blocked' using errcode = '42501'; end if;

  select * into v_f from public.friendships f
   where least(f.requester_id, f.addressee_id) = least(v_me, p_addressee)
     and greatest(f.requester_id, f.addressee_id) = greatest(v_me, p_addressee);
  if found then
    if v_f.status = 'accepted' then return 'friend'; end if;
    if v_f.requester_id = v_me then return 'outgoing'; end if;
    -- they already asked me: sending a request back accepts theirs
    update public.friendships set status = 'accepted', responded_at = now() where id = v_f.id;
    return 'friend';
  end if;
  insert into public.friendships (requester_id, addressee_id) values (v_me, p_addressee);
  return 'outgoing';
end
$$;

create function public.respond_request(p_requester uuid, p_accept boolean)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare v_me uuid := public.social_uid(); v_id uuid;
begin
  select f.id into v_id from public.friendships f
   where f.requester_id = p_requester and f.addressee_id = v_me and f.status = 'pending';
  if v_id is null then raise exception 'no_such_request' using errcode = '22023'; end if;
  if p_accept then
    update public.friendships set status = 'accepted', responded_at = now() where id = v_id;
    return 'friend';
  end if;
  delete from public.friendships where id = v_id;
  return 'none';
end
$$;

-- Removes a friend, cancels an outgoing request or lifts nothing (blocks are removed by unblock_user).
create function public.remove_friend(p_other uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare v_me uuid := public.social_uid();
begin
  delete from public.friendships f
   where f.status in ('accepted', 'pending')
     and ((f.requester_id = v_me and f.addressee_id = p_other) or (f.requester_id = p_other and f.addressee_id = v_me));
end
$$;

create function public.block_user(p_other uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare v_me uuid := public.social_uid();
begin
  if p_other = v_me then raise exception 'invalid_target' using errcode = '22023'; end if;
  delete from public.friendships f
   where (f.requester_id = v_me and f.addressee_id = p_other) or (f.requester_id = p_other and f.addressee_id = v_me);
  insert into public.friendships (requester_id, addressee_id, status, responded_at)
  values (v_me, p_other, 'blocked', now());
end
$$;

create function public.unblock_user(p_other uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare v_me uuid := public.social_uid();
begin
  delete from public.friendships f
   where f.status = 'blocked' and f.requester_id = v_me and f.addressee_id = p_other;
end
$$;

create function public.report_user(p_reported uuid, p_reason text, p_note text default null)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare v_me uuid := public.social_uid();
begin
  perform public.social_hit(v_me, 'report', 20, interval '1 day');
  if p_reported = v_me then raise exception 'invalid_target' using errcode = '22023'; end if;
  insert into public.reports (reporter_id, reported_id, reason, note)
  values (v_me, p_reported, p_reason, nullif(btrim(p_note), ''));
end
$$;

-- Friends, incoming/outgoing requests and my blocks, in one call. Scores only for friends who share them.
create function public.list_social()
returns setof public.social_person
language plpgsql
stable
security definer
set search_path = ''
as $$
declare v_me uuid := public.social_uid();
begin
  return query
    select p.user_id, p.username, p.display_name, p.avatar_emoji, p.avatar_color,
           case when f.status = 'accepted' then 'friend'
                when f.status = 'blocked' then 'blocked'
                when f.requester_id = v_me then 'outgoing' else 'incoming' end,
           case when f.status = 'accepted' and p.share_score then p.shared_overall_score end,
           case when f.status = 'accepted' and p.share_score then p.shared_score_provisional else false end,
           case when f.status = 'accepted' then p.weekly_workouts end
    from public.friendships f
    join public.public_profiles p
      on p.user_id = case when f.requester_id = v_me then f.addressee_id else f.requester_id end
    where (f.requester_id = v_me or f.addressee_id = v_me)
      -- a block hides me from them, never them from me
      and (f.status <> 'blocked' or f.requester_id = v_me)
    order by f.status, p.username;
end
$$;

-- Me + accepted friends ranked by period. 'month' needs published history and arrives with P087.
create type public.social_ranking_row as (
  rank integer, user_id uuid, username text, display_name text, avatar_emoji text, avatar_color text,
  value integer, provisional boolean, is_me boolean);

create function public.friends_leaderboard(p_period text)
returns setof public.social_ranking_row
language plpgsql
stable
security definer
set search_path = ''
as $$
declare v_me uuid := public.social_uid();
begin
  if p_period not in ('score', 'weekly') then raise exception 'invalid_period' using errcode = '22023'; end if;
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
               else m.weekly_workouts end as v
      from members m
    )
    select (rank() over (order by v desc nulls last))::integer,
           v.user_id, v.username, v.display_name, v.avatar_emoji, v.avatar_color,
           v.v, case when p_period = 'score' then v.shared_score_provisional else false end, v.user_id = v_me
    from valued v
    order by 1, v.username;
end
$$;

-- Server-side only: used by P087's publish-score through the service role.
create function public.social_publish(p_user uuid, p_score integer, p_provisional boolean, p_weekly integer)
returns void
language sql
security definer
set search_path = ''
as $$
  update public.public_profiles
     set shared_overall_score = case when share_score then p_score end,
         shared_score_provisional = share_score and p_provisional,
         shared_score_updated_at = case when share_score then now() end,
         weekly_workouts = least(greatest(p_weekly, 0), 50),
         updated_at = now()
   where user_id = p_user
$$;

-- ---------------------------------------------------------------- grants
revoke all on function
  public.social_normalize(text), public.social_text_ok(text), public.social_username_ok(text),
  public.social_is_blocked(uuid, uuid), public.social_are_friends(uuid, uuid),
  public.social_hit(uuid, text, integer, interval), public.social_uid(),
  public.username_available(text), public.upsert_my_profile(text, text, text, text, boolean, boolean),
  public.delete_my_profile(), public.search_users(text), public.send_request(uuid),
  public.respond_request(uuid, boolean), public.remove_friend(uuid), public.block_user(uuid),
  public.unblock_user(uuid), public.report_user(uuid, text, text), public.list_social(),
  public.friends_leaderboard(text), public.social_publish(uuid, integer, boolean, integer)
  from public, anon, authenticated;

-- RLS policies call these as the caller, so they need execute; none exposes more than a boolean.
grant execute on function public.social_is_blocked(uuid, uuid), public.social_are_friends(uuid, uuid),
  public.social_uid(), public.social_normalize(text), public.social_text_ok(text), public.social_username_ok(text)
  to authenticated;
grant execute on function
  public.username_available(text), public.upsert_my_profile(text, text, text, text, boolean, boolean),
  public.delete_my_profile(), public.search_users(text), public.send_request(uuid),
  public.respond_request(uuid, boolean), public.remove_friend(uuid), public.block_user(uuid),
  public.unblock_user(uuid), public.report_user(uuid, text, text), public.list_social(),
  public.friends_leaderboard(text)
  to authenticated;
grant execute on function public.social_publish(uuid, integer, boolean, integer), public.social_hit(uuid, text, integer, interval) to service_role;
