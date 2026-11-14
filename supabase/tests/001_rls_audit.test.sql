-- P013 · RLS audit. Fails when a public table has RLS off, has no policy, or is not registered in
-- tests.owner_tables() / tests.catalog_tables() (supabase/tests/000_rls_helpers.test.sql), which forces
-- whoever adds a table to also add its RLS tests.
begin;
select plan(7);

create temp table _pub_tables on commit drop as
select c.oid, c.relname::text as name, c.relrowsecurity as rls
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public' and c.relkind in ('r', 'p');

select is(
  (select string_agg(name, ', ' order by name) from _pub_tables
    where name <> all (tests.owner_tables() || tests.owner_readonly_tables() || tests.catalog_tables() || tests.social_tables() || tests.anonymous_tables())),
  null,
  'every public table is registered in tests.owner_tables() or tests.catalog_tables() (add RLS tests for new tables)');

select is(
  (select string_agg(t, ', ' order by t) from unnest(tests.owner_tables() || tests.owner_readonly_tables() || tests.catalog_tables() || tests.social_tables() || tests.anonymous_tables()) t
    where t not in (select name from _pub_tables)),
  null,
  'registry lists no table that does not exist');

select is(
  (select string_agg(name, ', ' order by name) from _pub_tables where not rls),
  null,
  'RLS is enabled on every public table');

select is(
  (select string_agg(p.name, ', ' order by p.name) from _pub_tables p
    where not exists (select 1 from pg_policy pol where pol.polrelid = p.oid)),
  null,
  'every public table has at least one policy');

-- Owner tables: policies must be scoped to the caller (auth.uid()) and never grant anything to anon/public.
select is(
  (select string_agg(p.name || '.' || pol.polname, ', ' order by p.name, pol.polname)
     from _pub_tables p join pg_policy pol on pol.polrelid = p.oid
    where p.name = any (tests.owner_tables() || tests.owner_readonly_tables())
      and (coalesce(pg_get_expr(pol.polqual, pol.polrelid), '') || coalesce(pg_get_expr(pol.polwithcheck, pol.polrelid), ''))
          not like '%auth.uid()%'),
  null,
  'owner-table policies are all scoped with auth.uid()');

select is(
  (select string_agg(p.name || '.' || pol.polname, ', ' order by p.name, pol.polname)
     from _pub_tables p join pg_policy pol on pol.polrelid = p.oid
    where p.name = any (tests.owner_tables() || tests.owner_readonly_tables())
      and (pol.polroles = '{0}' or pol.polroles @> array[(select oid from pg_roles where rolname = 'anon')])),
  null,
  'no owner-table policy applies to public/anon');

-- Catalog tables: no write policies at all.
select is(
  (select string_agg(p.name || '.' || pol.polname, ', ' order by p.name, pol.polname)
     from _pub_tables p join pg_policy pol on pol.polrelid = p.oid
    where p.name = any (tests.catalog_tables()) and pol.polcmd <> 'r'),
  null,
  'catalog tables have no write policies');

select * from finish();
rollback;
