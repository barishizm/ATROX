-- P087 · Ranking and score publishing: order, ties, privacy of the published value, monthly progress.
begin;
select plan(13);

select tests.create_two_users();

select tests.authenticate_as(tests.user_a());
select public.upsert_my_profile('alice', 'Alice', '🔥', 'sky', true, true);
select tests.authenticate_as(tests.user_b());
select public.upsert_my_profile('bob', 'Bob', '💪', 'ember', true, true);
select public.send_request(tests.user_a());
select tests.authenticate_as(tests.user_a());
select public.respond_request(tests.user_b(), true);

-- ===== only the server publishes =====
select throws_ok($$select public.social_publish(tests.user_a(), 99, false, 5)$$, '42501', null,
  'a signed-in client cannot call social_publish');
select throws_ok($$select * from public.social_score_history$$, '42501', null, 'clients cannot read score history');

-- ===== order and ties =====
select tests.clear_authentication();
select public.social_publish(tests.user_a(), 60, false, 4);
select public.social_publish(tests.user_b(), 72, true, 2);
select tests.authenticate_as(tests.user_a());
select is((select array_agg(username order by rank, username) from public.friends_leaderboard('score')),
  array['bob', 'alice'], 'score ranking: higher score first');
select is((select provisional from public.friends_leaderboard('score') where username = 'bob'), true,
  'a provisional score is flagged in the ranking');
select is((select is_me from public.friends_leaderboard('score') where username = 'alice'), true, 'own row is marked');
select is((select array_agg(username order by rank, username) from public.friends_leaderboard('weekly')),
  array['alice', 'bob'], 'weekly ranking: more workouts first');

select tests.clear_authentication();
select public.social_publish(tests.user_b(), 60, false, 4);
select tests.authenticate_as(tests.user_a());
select is((select array_agg(rank order by username) from public.friends_leaderboard('score')), array[1, 1],
  'equal scores share the same rank');

-- ===== monthly progress =====
select tests.clear_authentication();
select public.social_publish(tests.user_a(), 68, false, 4);
-- Move A's first published point of the month to the start of the month at 60.
update public.social_score_history set score = 60, day = date_trunc('month', now() at time zone 'utc')::date
  where user_id = tests.user_a();
select tests.authenticate_as(tests.user_a());
select is((select value from public.friends_leaderboard('month') where username = 'alice'), 8, 'month: score now minus first of the month');
select is((select value from public.friends_leaderboard('month') where username = 'bob'), 0, 'month: no earlier point means no change');
select throws_ok($$select * from public.friends_leaderboard('year')$$, '22023', 'invalid_period', 'unknown period rejected');

-- ===== sharing off: nothing published, history gone =====
select (public.upsert_my_profile('alice', 'Alice', '🔥', 'sky', true, false)).username;
select tests.clear_authentication();
select is((select count(*) from public.social_score_history where user_id = tests.user_a()), 0::bigint,
  'turning sharing off deletes the history');
select public.social_publish(tests.user_a(), 70, false, 4);
select is((select shared_overall_score from public.public_profiles where user_id = tests.user_a()), null,
  'publishing while sharing is off stores no score');
select is((select count(*) from public.social_score_history where user_id = tests.user_a()), 0::bigint,
  'publishing while sharing is off stores no history');

select finish();
rollback;
