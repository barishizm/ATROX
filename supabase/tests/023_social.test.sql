-- P085 · Social layer: username policy, visibility (discoverable / friends / blocks), request flow, impersonation.
begin;
select plan(32);

select tests.create_two_users();
select tests.create_user('00000000-0000-0000-0000-0000000000c3', 'c@example.test');

-- ===== username and text policy =====
select ok(public.social_username_ok('iron_mike'), 'username: plain handle ok');
select ok(not public.social_username_ok('ab'), 'username: too short');
select ok(not public.social_username_ok('Upper'), 'username: uppercase rejected (stored lowercase)');
select ok(not public.social_username_ok('admin'), 'username: reserved word rejected');
select ok(not public.social_username_ok('f_u_c_k'), 'username: separators do not hide a blocked word');
select ok(not public.social_text_ok('SİKTİR'), 'text: Turkish blocklist applies to normalised text');
select ok(public.social_text_ok('Ayşe Yılmaz'), 'text: ordinary Turkish name passes');

-- ===== profiles =====
select tests.authenticate_as(tests.user_a());
select is((public.upsert_my_profile('alice', 'Alice', '🔥', 'sky', true, true)).username, 'alice', 'A creates a profile');
select tests.authenticate_as(tests.user_b());
select throws_ok($$select public.upsert_my_profile('Alice', 'Bob', '💪', 'ember', true, false)$$, '23505', 'username_taken',
  'username is unique case-insensitively');
select is((public.upsert_my_profile('bob', 'Bob', '💪', 'ember', false, false)).is_discoverable, false, 'B creates a hidden profile');
select is(public.username_available('alice'), false, 'username_available: taken');
select is(public.username_available('bobby'), true, 'username_available: free');

-- ===== visibility =====
select tests.authenticate_as(tests.user_a());
select is((select count(*) from public.public_profiles where user_id = tests.user_b()), 0::bigint,
  'A cannot read B: not discoverable, not friends');
select tests.authenticate_as(tests.user_b());
select is((select count(*) from public.public_profiles where user_id = tests.user_a()), 1::bigint,
  'B can read A: discoverable');
select is((select count(*) from public.search_users('ali')), 1::bigint, 'search finds a discoverable user by prefix');
select is((select count(*) from public.search_users('lice')), 0::bigint, 'search is prefix based, not substring');
select is((select count(*) from public.search_users('a')), 0::bigint, 'search needs at least two characters');

-- ===== requests =====
select is(public.send_request(tests.user_a()), 'outgoing', 'B asks A');
select tests.authenticate_as(tests.user_a());
select is((select count(*) from public.list_social() where relation = 'incoming'), 1::bigint, 'A sees the incoming request');
select is(public.respond_request(tests.user_b(), true), 'friend', 'A accepts');
select is((select count(*) from public.public_profiles where user_id = tests.user_b()), 1::bigint,
  'friends can read a non-discoverable profile');

-- ===== score visibility =====
select tests.clear_authentication();
select public.social_publish(tests.user_a(), 61, false, 3);
select tests.authenticate_as(tests.user_b());
select is((select value from public.friends_leaderboard('score') where username = 'alice'), 61, 'friend sees the shared score');
select tests.authenticate_as(tests.user_a());
select is((select (public.upsert_my_profile('alice', 'Alice', '🔥', 'sky', true, false)).shared_overall_score), null,
  'turning sharing off withdraws the published score');
select tests.authenticate_as(tests.user_b());
select is((select value from public.friends_leaderboard('score') where username = 'alice'), null,
  'friend no longer sees the score');

-- ===== blocking cuts both ways =====
select public.block_user(tests.user_a());
select is((select count(*) from public.public_profiles where user_id = tests.user_a()), 0::bigint, 'blocker cannot read the blocked profile');
select is((select count(*) from public.search_users('ali')), 0::bigint, 'blocked user is not in search results');
select tests.authenticate_as(tests.user_a());
select is((select count(*) from public.public_profiles where user_id = tests.user_b()), 0::bigint, 'blocked side cannot read the blocker either');
select is((select count(*) from public.list_social()), 0::bigint, 'blocked side sees nothing about the block');
select throws_ok($$select public.send_request(tests.user_b())$$, '42501', 'blocked', 'blocked side cannot send a request');

-- ===== impersonation / anon =====
select throws_ok($$insert into public.friendships (requester_id, addressee_id) values (tests.user_a(), tests.user_b())$$, '42501', null,
  'clients cannot insert friendships directly');
select tests.authenticate_as_anon();
select throws_ok($$select * from public.list_social()$$, '42501', null, 'anon cannot call social functions');
select tests.clear_authentication();
select throws_ok($$select public.send_request(tests.user_b())$$, '28000', 'not_authenticated', 'no JWT, no social');
select finish();
rollback;
