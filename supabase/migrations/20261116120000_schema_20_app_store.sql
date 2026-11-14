-- P090 · Server-side subscription verification (App Store Server Notifications V2 + verify-purchase).
--   entitlements              completed: one row per (original transaction, environment) for App Store subscriptions,
--                             plus manual/promo grants. The owner reads; only the service role writes.
--   billing.app_account_tokens  appAccountToken (UUIDv5 of the user id, same namespace as the app) → user, filled by a
--                             trigger on auth.users. Lets a notification find its user without the app.
--   billing.app_store_events  every notification / client verification: idempotency (notification UUID unique) and the
--                             log of transactions that matched no user.
--   entitlement_tier()        the single "is this user Pro now" rule; coach_consume_quota() and
--                             coach_digest_allowance() read it (completes the P077 link).
--   appstore_*()              service-role-only writers used by the two Edge Functions.
-- The billing schema is not exposed to anon/authenticated at all (no usage grant); RLS is on as a second fence.

create extension if not exists "uuid-ossp" with schema extensions;

-- ===== entitlements =====
alter table public.entitlements drop constraint entitlements_user_id_key;
alter table public.entitlements
  add column product_id              text,
  add column status                  text not null default 'active',
  add column original_transaction_id text,
  add column environment             text,
  add column will_renew              boolean not null default false,
  -- signedDate of the newest Apple payload applied; older payloads never overwrite newer ones.
  add column signed_at               timestamptz,
  add constraint entitlements_status_check check (
    status in ('active', 'trial', 'grace_period', 'billing_retry', 'expired', 'refunded', 'revoked')),
  add constraint entitlements_environment_check check (environment is null or environment in ('sandbox', 'production')),
  add constraint entitlements_app_store_check check (
    source <> 'app_store' or (product_id is not null and original_transaction_id is not null and environment is not null)),
  add constraint entitlements_transaction_key unique (original_transaction_id, environment);
create index entitlements_user_id_idx on public.entitlements (user_id);

-- Pro right now: a Pro row whose status grants access and that has not run out.
create function public.entitlement_tier(p_user uuid)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select case when exists (
    select 1 from public.entitlements e
     where e.user_id = p_user and e.tier = 'pro'
       and e.status in ('active', 'trial', 'grace_period')
       and (e.expires_at is null or e.expires_at > now()))
  then 'pro' else 'free' end;
$$;
revoke all on function public.entitlement_tier(uuid) from public, anon, authenticated;
grant execute on function public.entitlement_tier(uuid) to service_role;

-- ===== billing schema =====
create schema billing;
revoke all on schema billing from public, anon, authenticated;
grant usage on schema billing to service_role;

-- Must match ios/App/Sources/Purchases/AppAccountToken.swift (namespace and lowercase user id string).
create function billing.app_account_token(p_user uuid)
returns uuid
language sql
immutable
set search_path = ''
as $$ select extensions.uuid_generate_v5('6f1c7a52-3b0e-5d44-9a1e-0a7c2e9b41d8'::uuid, p_user::text) $$;

create table billing.app_account_tokens (
  token    uuid primary key,
  user_id  uuid not null unique references auth.users (id) on delete cascade
);

create table billing.app_store_events (
  id                       uuid primary key default gen_random_uuid(),
  received_at              timestamptz not null default now(),
  source                   text not null,
  notification_uuid        uuid unique,
  notification_type        text,
  subtype                  text,
  environment              text,
  original_transaction_id  text,
  user_id                  uuid references auth.users (id) on delete set null,
  matched                  boolean not null,
  reason                   text,
  signed_at                timestamptz,

  constraint app_store_events_source_check check (source in ('notification', 'verify'))
);
create index app_store_events_unmatched_idx on billing.app_store_events (received_at) where not matched;

alter table billing.app_account_tokens enable row level security;
alter table billing.app_store_events enable row level security;
revoke all on billing.app_account_tokens, billing.app_store_events from public, anon, authenticated;
grant all on billing.app_account_tokens, billing.app_store_events to service_role;

create function billing.register_app_account_token()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into billing.app_account_tokens (token, user_id) values (billing.app_account_token(new.id), new.id)
  on conflict do nothing;
  return new;
end
$$;
create trigger register_app_account_token after insert on auth.users
  for each row execute function billing.register_app_account_token();

insert into billing.app_account_tokens (token, user_id)
select billing.app_account_token(u.id), u.id from auth.users u
on conflict do nothing;

-- ===== writers (service role only) =====

-- Whether a notification was already processed (Apple retries until it gets a 200).
create function public.appstore_notification_seen(p_uuid uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$ select exists (select 1 from billing.app_store_events e where e.notification_uuid = p_uuid) $$;

create function public.appstore_record_event(
  p_source text, p_uuid uuid, p_type text, p_subtype text, p_environment text, p_original_transaction_id text,
  p_user uuid, p_matched boolean, p_reason text, p_signed_at timestamptz)
returns void
language sql
volatile
security definer
set search_path = ''
as $$
  insert into billing.app_store_events (source, notification_uuid, notification_type, subtype, environment,
                                        original_transaction_id, user_id, matched, reason, signed_at)
  values (p_source, p_uuid, p_type, p_subtype, p_environment, p_original_transaction_id, p_user, p_matched, p_reason,
          p_signed_at)
  on conflict (notification_uuid) do nothing;
$$;

-- Writes one subscription state. The user is resolved here:
--   p_user given (verify-purchase, the caller): the token, when present, must be the caller's, and the transaction
--     must not already belong to someone else.
--   p_user null (notification): the token's user, else the user who already owns the transaction.
-- Returns { matched, reason, user_id, applied }. applied = false when a newer payload was already stored.
create function public.appstore_apply(
  p_user uuid, p_token uuid, p_product text, p_status text, p_expires_at timestamptz, p_original_transaction_id text,
  p_environment text, p_will_renew boolean, p_signed_at timestamptz)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_token_user uuid;
  v_owner      uuid;
  v_user       uuid;
  v_rows       integer;
begin
  if p_token is not null then
    select t.user_id into v_token_user from billing.app_account_tokens t where t.token = p_token;
  end if;
  select e.user_id into v_owner from public.entitlements e
   where e.original_transaction_id = p_original_transaction_id and e.environment = p_environment;

  if p_user is not null then
    if p_token is not null and v_token_user is distinct from p_user then
      return jsonb_build_object('matched', false, 'reason', 'token_mismatch', 'user_id', null, 'applied', false);
    end if;
    if v_owner is not null and v_owner <> p_user then
      return jsonb_build_object('matched', false, 'reason', 'owned_by_other', 'user_id', null, 'applied', false);
    end if;
    v_user := p_user;
  else
    v_user := coalesce(v_token_user, v_owner);
    if v_user is null then
      return jsonb_build_object('matched', false,
        'reason', case when p_token is null then 'no_token' else 'unknown_token' end, 'user_id', null, 'applied', false);
    end if;
  end if;

  insert into public.entitlements (user_id, tier, source, product_id, status, expires_at, original_transaction_id,
                                   environment, will_renew, signed_at)
  values (v_user, 'pro', 'app_store', p_product, p_status, p_expires_at, p_original_transaction_id, p_environment,
          p_will_renew, p_signed_at)
  on conflict (original_transaction_id, environment) do update
     set product_id = excluded.product_id, status = excluded.status, expires_at = excluded.expires_at,
         will_renew = excluded.will_renew, signed_at = excluded.signed_at
   where public.entitlements.signed_at is null or excluded.signed_at >= public.entitlements.signed_at;
  get diagnostics v_rows = row_count;
  return jsonb_build_object('matched', true, 'reason', null, 'user_id', v_user, 'applied', v_rows > 0);
end
$$;

revoke all on function public.appstore_notification_seen(uuid) from public, anon, authenticated;
revoke all on function public.appstore_record_event(text, uuid, text, text, text, text, uuid, boolean, text, timestamptz)
  from public, anon, authenticated;
revoke all on function public.appstore_apply(uuid, uuid, text, text, timestamptz, text, text, boolean, timestamptz)
  from public, anon, authenticated;
grant execute on function public.appstore_notification_seen(uuid) to service_role;
grant execute on function public.appstore_record_event(text, uuid, text, text, text, text, uuid, boolean, text, timestamptz)
  to service_role;
grant execute on function public.appstore_apply(uuid, uuid, text, text, timestamptz, text, text, boolean, timestamptz)
  to service_role;
revoke all on function billing.app_account_token(uuid) from public;
grant execute on function billing.app_account_token(uuid) to service_role;

-- ===== coach functions read the tier through entitlement_tier() =====

create or replace function public.coach_consume_quota(p_user uuid, p_time_zone text default 'UTC')
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_tz      text := case when exists (select 1 from pg_catalog.pg_timezone_names where name = p_time_zone)
                         then p_time_zone else 'UTC' end;
  v_today   date := (now() at time zone v_tz)::date;
  v_tier    text;
  v_limits  public.coach_limits;
  v_quota   public.coach_quota;
begin
  v_tier := public.entitlement_tier(p_user);
  select * into v_limits from public.coach_limits where tier = v_tier;
  if not found then
    raise exception 'coach_limits row missing for tier %', v_tier;
  end if;

  insert into public.coach_quota (user_id, day) values (p_user, v_today) on conflict (user_id) do nothing;
  -- The row lock serialises concurrent requests of the same user: check and increment happen as one step.
  select * into v_quota from public.coach_quota where user_id = p_user for update;

  if v_quota.day <> v_today then
    v_quota.day := v_today;
    v_quota.messages := 0;
  end if;
  if v_quota.minute_start <= now() - interval '1 minute' then
    v_quota.minute_start := now();
    v_quota.minute_count := 0;
  end if;

  if v_quota.minute_count >= v_limits.requests_per_minute then
    update public.coach_quota set day = v_quota.day, messages = v_quota.messages, updated_at = now()
     where user_id = p_user;
    return jsonb_build_object('allowed', false, 'reason', 'rate_minute', 'tier', v_tier,
      'remaining', greatest(v_limits.daily_messages - v_quota.messages, 0),
      'reset_at', v_quota.minute_start + interval '1 minute', 'limits', to_jsonb(v_limits) - 'updated_at');
  end if;
  if v_quota.messages >= v_limits.daily_messages then
    update public.coach_quota set day = v_quota.day, messages = v_quota.messages,
           minute_start = v_quota.minute_start, minute_count = v_quota.minute_count, updated_at = now()
     where user_id = p_user;
    return jsonb_build_object('allowed', false, 'reason', 'daily', 'tier', v_tier, 'remaining', 0,
      'reset_at', ((v_today + 1)::timestamp at time zone v_tz), 'limits', to_jsonb(v_limits) - 'updated_at');
  end if;

  update public.coach_quota
     set day = v_quota.day, messages = v_quota.messages + 1,
         minute_start = v_quota.minute_start, minute_count = v_quota.minute_count + 1, updated_at = now()
   where user_id = p_user;
  return jsonb_build_object('allowed', true, 'reason', null, 'tier', v_tier,
    'remaining', v_limits.daily_messages - v_quota.messages - 1,
    'reset_at', ((v_today + 1)::timestamp at time zone v_tz), 'limits', to_jsonb(v_limits) - 'updated_at');
end
$$;

create or replace function public.coach_digest_allowance(p_user uuid, p_kind text, p_time_zone text default 'UTC')
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
  v_limit integer := case p_kind when 'workout' then 10 when 'weekly' then 3 else 0 end;
  v_used  integer;
begin
  v_tier := public.entitlement_tier(p_user);
  select count(*) into v_used from public.coach_digests d
   where d.user_id = p_user and d.kind = p_kind and d.created_at >= v_start;
  if v_tier <> 'pro' then
    return jsonb_build_object('tier', v_tier, 'allowed', false, 'reason', 'not_pro', 'used', v_used, 'limit', v_limit);
  end if;
  if v_used >= v_limit then
    return jsonb_build_object('tier', v_tier, 'allowed', false, 'reason', 'daily', 'used', v_used, 'limit', v_limit);
  end if;
  return jsonb_build_object('tier', v_tier, 'allowed', true, 'reason', null, 'used', v_used, 'limit', v_limit);
end
$$;
