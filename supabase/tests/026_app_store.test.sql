-- P090 · entitlements (completed), billing.app_account_tokens, appstore_apply / record_event, entitlement_tier.
begin;
select plan(24);

select tests.create_two_users();
select tests.create_user('00000000-0000-0000-0000-000000000001', 'vector@example.test');

-- Token mapping (trigger on auth.users) reproduces the app's AppAccountToken.
select is((select token from billing.app_account_tokens where user_id = '00000000-0000-0000-0000-000000000001'),
  'b74ace79-3051-5fbe-8b18-7a4c598b8ebf'::uuid, 'token: matches the iOS known vector');
select is((select token from billing.app_account_tokens where user_id = tests.user_a()),
  'abf9a940-2ac0-5214-8cc8-1df578d31b09'::uuid, 'token: registered for every new user');

-- Notification path: token → user.
select is(public.appstore_apply(null, 'abf9a940-2ac0-5214-8cc8-1df578d31b09', 'atrox.pro.yearly', 'active',
  now() + interval '30 days', 'otx-1', 'sandbox', true, '2026-11-14 10:00Z') ->> 'user_id', tests.user_a()::text,
  'apply: the token finds its user');
select is(public.entitlement_tier(tests.user_a()), 'pro', 'tier: active App Store row is Pro');
select is(public.coach_consume_quota(tests.user_a(), 'UTC') ->> 'tier', 'pro', 'coach quota reads the entitlement');
select is(public.coach_digest_allowance(tests.user_a(), 'workout', 'UTC') ->> 'tier', 'pro', 'coach digest reads the entitlement');

-- Ordering: an older payload never overwrites a newer one.
select is((public.appstore_apply(null, 'abf9a940-2ac0-5214-8cc8-1df578d31b09', 'atrox.pro.yearly', 'expired',
  now() - interval '1 day', 'otx-1', 'sandbox', false, '2026-11-14 09:00Z') ->> 'applied')::boolean, false,
  'apply: older payload is skipped');
select is((select status from public.entitlements where original_transaction_id = 'otx-1'), 'active',
  'apply: row keeps the newer state');

-- No token: the owner of the transaction is used.
select is((public.appstore_apply(null, null, 'atrox.pro.yearly', 'grace_period', now() + interval '3 days', 'otx-1',
  'sandbox', true, '2026-11-14 11:00Z') ->> 'matched')::boolean, true, 'apply: tokenless renewal finds the owner');
select is(public.entitlement_tier(tests.user_a()), 'pro', 'tier: grace period keeps Pro');

-- Ending states.
select public.appstore_apply(null, null, 'atrox.pro.yearly', 'billing_retry', now() - interval '1 hour', 'otx-1',
  'sandbox', true, '2026-11-14 12:00Z');
select is(public.entitlement_tier(tests.user_a()), 'free', 'tier: billing retry is not Pro');
select public.appstore_apply(null, null, 'atrox.pro.yearly', 'refunded', now() + interval '30 days', 'otx-1',
  'sandbox', false, '2026-11-14 13:00Z');
select is(public.entitlement_tier(tests.user_a()), 'free', 'tier: a refund ends Pro even before expires_at');

-- Environments are separate rows.
select public.appstore_apply(null, 'abf9a940-2ac0-5214-8cc8-1df578d31b09', 'atrox.pro.yearly', 'active',
  now() + interval '30 days', 'otx-1', 'production', true, '2026-11-14 10:00Z');
select is((select count(*) from public.entitlements where original_transaction_id = 'otx-1'), 2::bigint,
  'apply: sandbox and production are separate rows');

-- Unmatched.
select is(public.appstore_apply(null, gen_random_uuid(), 'atrox.pro.yearly', 'active', now() + interval '1 day',
  'otx-2', 'sandbox', true, now()) ->> 'reason', 'unknown_token', 'apply: unknown token is unmatched');
select is(public.appstore_apply(null, null, 'atrox.pro.yearly', 'active', now() + interval '1 day',
  'otx-3', 'sandbox', true, now()) ->> 'reason', 'no_token', 'apply: no token and no owner is unmatched');
select is((select count(*) from public.entitlements where original_transaction_id in ('otx-2', 'otx-3')), 0::bigint,
  'apply: unmatched writes nothing');

-- verify-purchase path: caller given.
select is(public.appstore_apply(tests.user_b(), 'abf9a940-2ac0-5214-8cc8-1df578d31b09', 'atrox.pro.monthly', 'active',
  now() + interval '1 day', 'otx-4', 'sandbox', true, now()) ->> 'reason', 'token_mismatch',
  'apply: another user''s token is refused');
select is(public.appstore_apply(tests.user_b(), null, 'atrox.pro.monthly', 'active', now() + interval '1 day',
  'otx-1', 'sandbox', true, now()) ->> 'reason', 'owned_by_other', 'apply: cannot take over another user''s transaction');

-- Idempotency log.
select public.appstore_record_event('notification', '7d4c1c1e-1f2a-4a8b-9c3d-000000000001', 'SUBSCRIBED', null, 'sandbox',
  'otx-1', tests.user_a(), true, null, now());
select public.appstore_record_event('notification', '7d4c1c1e-1f2a-4a8b-9c3d-000000000001', 'SUBSCRIBED', null, 'sandbox',
  'otx-1', tests.user_a(), true, null, now());
select is(public.appstore_notification_seen('7d4c1c1e-1f2a-4a8b-9c3d-000000000001'), true, 'events: seen after recording');
select is((select count(*) from billing.app_store_events), 1::bigint, 'events: a notification UUID is stored once');

-- Access.
select tests.authenticate_as(tests.user_a());
select is((select count(*) from public.entitlements), 2::bigint, 'rls: the owner reads their rows');
select throws_ok($$select public.appstore_apply(null, null, 'atrox.pro.yearly', 'active', null, 'x', 'sandbox', true, now())$$,
  '42501', null, 'rls: users cannot call the writer');
select throws_ok($$select * from billing.app_store_events$$, '42501', null, 'rls: billing schema is closed to users');
select tests.clear_authentication();

select throws_ok($$insert into public.entitlements (user_id, source) values ('00000000-0000-0000-0000-0000000000a1', 'app_store')$$,
  '23514', null, 'check: App Store rows need product, transaction and environment');

select * from finish();
rollback;
