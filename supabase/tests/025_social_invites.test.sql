-- P088 · resolve_invite: exact username, works for hidden profiles, respects blocks, needs a profile of your own.
begin;
select plan(6);

select tests.create_two_users();
select tests.authenticate_as(tests.user_a());
select public.upsert_my_profile('alice', 'Alice', '🔥', 'sky', false, false);
select tests.authenticate_as(tests.user_b());
select public.upsert_my_profile('bob', 'Bob', '💪', 'ember', false, false);

select is((select count(*) from public.search_users('alice')), 0::bigint, 'a hidden profile is not in search');
select is((select username from public.resolve_invite('Alice ')), 'alice', 'the invite link still resolves it (case and spaces ignored)');
select is((select relation from public.resolve_invite('alice')), 'none', 'relation is reported');
select is((select count(*) from public.resolve_invite('bob')), 0::bigint, 'your own link resolves to nobody');
select public.block_user(tests.user_a());
select is((select count(*) from public.resolve_invite('alice')), 0::bigint, 'a blocked person does not resolve');
select tests.authenticate_as_anon();
select throws_ok($$select * from public.resolve_invite('alice')$$, '42501', null, 'anon cannot resolve invites');

select finish();
rollback;
