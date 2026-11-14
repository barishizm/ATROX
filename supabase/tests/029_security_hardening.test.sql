-- P102 · The relationship helpers answer only for the caller: no friendship/block oracle about third parties.
begin;
select plan(6);

select tests.create_two_users();
select tests.create_user('00000000-0000-0000-0000-0000000000c3', 'c@example.test');
insert into public.friendships (requester_id, addressee_id, status)
  values (tests.user_a(), tests.user_b(), 'accepted');
insert into public.friendships (requester_id, addressee_id, status)
  values ('00000000-0000-0000-0000-0000000000c3', tests.user_a(), 'blocked');

select tests.authenticate_as(tests.user_a());
select is(public.social_are_friends(tests.user_a(), tests.user_b()), true, 'the caller sees their own friendship');
select is(public.social_is_blocked(tests.user_a(), '00000000-0000-0000-0000-0000000000c3'), true, 'the caller sees their own block');

select tests.authenticate_as('00000000-0000-0000-0000-0000000000c3');
select is(public.social_are_friends(tests.user_a(), tests.user_b()), false, 'a third party cannot ask whether two others are friends');
select is(public.social_is_blocked('00000000-0000-0000-0000-0000000000c3', tests.user_a()), true, 'the blocker sees their block');
select is(public.social_is_blocked(tests.user_a(), '00000000-0000-0000-0000-0000000000c3'), false, 'the arguments cannot be swapped to impersonate the other side');

select tests.authenticate_as_anon();
select throws_ok($$select public.social_are_friends(tests.user_a(), tests.user_b())$$, '42501', null, 'anon cannot call the helpers');

select * from finish();
rollback;
