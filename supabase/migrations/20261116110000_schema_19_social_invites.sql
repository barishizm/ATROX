-- P088: an invite link names one exact username. resolve_invite finds that person even when they are not
-- discoverable in search (sharing the link is the opt-in); blocks still hide both sides, and nothing but the
-- public profile fields is returned.
create function public.resolve_invite(p_username text)
returns setof public.social_person
language plpgsql
security definer
set search_path = ''
as $$
declare v_me uuid := public.social_uid(); v_name text := lower(btrim(p_username));
begin
  if v_name !~ '^[a-z0-9_]{3,20}$' then return; end if;
  perform public.social_hit(v_me, 'invite', 30, interval '1 minute');
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
    where p.username = v_name
      and p.user_id <> v_me
      and not public.social_is_blocked(v_me, p.user_id);
end
$$;

revoke all on function public.resolve_invite(text) from public, anon, authenticated;
grant execute on function public.resolve_invite(text) to authenticated;
