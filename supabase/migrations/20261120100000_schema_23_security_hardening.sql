-- P102 · Security review fix: the two relationship helpers were executable by every signed-in user with
-- arbitrary uuid pairs, which made them an oracle ("are A and B friends / has A blocked B?") about third parties.
-- RLS policies and the social functions only ever pass the caller as the first argument, so the helpers now answer
-- only for the caller; any other pair gets false.
create or replace function public.social_is_blocked(p_a uuid, p_b uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select p_a is not distinct from (select auth.uid()) and exists (
    select 1 from public.friendships f
    where f.status = 'blocked'
      and ((f.requester_id = p_a and f.addressee_id = p_b) or (f.requester_id = p_b and f.addressee_id = p_a)))
$$;

create or replace function public.social_are_friends(p_a uuid, p_b uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select p_a is not distinct from (select auth.uid()) and exists (
    select 1 from public.friendships f
    where f.status = 'accepted'
      and ((f.requester_id = p_a and f.addressee_id = p_b) or (f.requester_id = p_b and f.addressee_id = p_a)))
$$;

revoke all on function public.social_is_blocked(uuid, uuid), public.social_are_friends(uuid, uuid) from public, anon;
grant execute on function public.social_is_blocked(uuid, uuid), public.social_are_friends(uuid, uuid) to authenticated;
