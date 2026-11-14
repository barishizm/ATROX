-- P013 · RLS matrix: the same five properties, asserted for every registered table.
--   owner tables : (1) owner can write own row (no RLS rejection)  (2) other user sees nothing
--                  (3) anon cannot read  (4) cannot insert with someone else's user_id
--   catalog tables: (5) readable by anon and authenticated, not writable by either
-- Row-level behaviour with real data lives in 010/011/012; this file guards every table uniformly.
begin;
select plan(
  array_length(tests.owner_tables(), 1) * 5
  + array_length(tests.owner_readonly_tables(), 1) * 4
  + array_length(tests.catalog_tables(), 1) * 6
);

select tests.create_two_users();

-- ===== Owner tables =====
-- (3) anon cannot read
select tests.authenticate_as_anon();
select throws_ok(format('select * from public.%I', t), '42501', null, t || ': anon cannot read')
from unnest(tests.owner_tables()) t;
select tests.clear_authentication();

-- (4) user A cannot insert a row owned by B (RLS WITH CHECK runs before NOT NULL checks -> 42501)
select tests.authenticate_as(tests.user_a());
select throws_ok(
  format('insert into public.%I (user_id) values (%L)', t, tests.user_b()),
  '42501', null, t || ': cannot insert a row for another user')
from unnest(tests.owner_tables()) t;

-- (1) the same insert for A's own id passes RLS (and then stops on a different, non-RLS constraint)
select isnt(
  (select state from tests.try_sql(format('insert into public.%I (user_id) values (%L)', t, tests.user_a()))),
  '42501', t || ': owner insert is not rejected by RLS')
from unnest(tests.owner_tables()) t;

-- (2) B sees no rows (and no row of A's can be matched by id)
select tests.authenticate_as(tests.user_b());
select is(tests.count_rows(t), 0::bigint, t || ': other user sees nothing')
from unnest(tests.owner_tables()) t;
select throws_ok(
  format('insert into public.%I (user_id) values (%L)', t, tests.user_a()),
  '42501', null, t || ': B cannot insert a row for A')
from unnest(tests.owner_tables()) t;
select tests.clear_authentication();

-- ===== Owner-readable, service-written tables =====
select tests.authenticate_as_anon();
select throws_ok(format('select * from public.%I', t), '42501', null, t || ': anon cannot read')
from unnest(tests.owner_readonly_tables()) t;
select tests.authenticate_as(tests.user_a());
select lives_ok(format('select * from public.%I', t), t || ': owner can read')
from unnest(tests.owner_readonly_tables()) t;
select throws_ok(format('insert into public.%I (user_id) values (%L)', t, tests.user_a()),
  '42501', null, t || ': owner cannot insert')
from unnest(tests.owner_readonly_tables()) t;
select tests.authenticate_as(tests.user_b());
select is(tests.count_rows(t), 0::bigint, t || ': other user sees nothing')
from unnest(tests.owner_readonly_tables()) t;
select tests.clear_authentication();

-- ===== Catalog tables =====
select tests.authenticate_as_anon();
select lives_ok(format('select * from public.%I', t), t || ': anon can read')
from unnest(tests.catalog_tables()) t;
select throws_ok(format('delete from public.%I', t), '42501', null, t || ': anon cannot delete')
from unnest(tests.catalog_tables()) t;
select tests.authenticate_as(tests.user_a());
select lives_ok(format('select * from public.%I', t), t || ': authenticated can read')
from unnest(tests.catalog_tables()) t;
select throws_ok(format('delete from public.%I', t), '42501', null, t || ': authenticated cannot delete')
from unnest(tests.catalog_tables()) t;
select throws_ok(format('update public.%I set %I = %I', t, tests.first_column(t), tests.first_column(t)),
  '42501', null, t || ': authenticated cannot update')
from unnest(tests.catalog_tables()) t;
select throws_ok(format('insert into public.%I default values', t), '42501', null, t || ': authenticated cannot insert')
from unnest(tests.catalog_tables()) t;

select * from finish();
rollback;
