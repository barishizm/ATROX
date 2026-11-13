-- P063 · model_versions: constraints, public read, service-role-only writes, model-bundles bucket.
begin;
create extension if not exists pgtap with schema extensions;
select plan(12);

select has_table('public', 'model_versions', 'model_versions exists');
select ok((select relrowsecurity from pg_class where oid = 'public.model_versions'::regclass), 'RLS enabled');

-- Superuser (like the service role / publish script) can insert; defaults keep a new version inactive.
select lives_ok($$
  insert into public.model_versions (version, schema_version, min_app_version, storage_path, manifest_sha256)
  values ('1.1.0', 1, '1.0.0', 'v1.1.0', repeat('a', 64))
$$, 'service role inserts a version');
select is((select is_active from public.model_versions where version = '1.1.0'), false, 'new versions start inactive');
select is((select rollout_percent from public.model_versions where version = '1.1.0'), 100, 'rollout defaults to 100');

select throws_ok($$ insert into public.model_versions (version, schema_version, min_app_version, storage_path, manifest_sha256)
  values ('1.2', 1, '1.0.0', 'v1.2', repeat('a', 64)) $$, '23514', null, 'non-semver version rejected');
select throws_ok($$ insert into public.model_versions (version, schema_version, min_app_version, storage_path, manifest_sha256)
  values ('1.2.0', 1, '1.0.0', 'v1.2.0', 'XYZ') $$, '23514', null, 'malformed digest rejected');
select throws_ok($$ insert into public.model_versions (version, schema_version, min_app_version, storage_path, manifest_sha256, rollout_percent)
  values ('1.2.0', 1, '1.0.0', 'v1.2.0', repeat('b', 64), 101) $$, '23514', null, 'rollout above 100 rejected');
select throws_ok($$ insert into public.model_versions (version, schema_version, min_app_version, storage_path, manifest_sha256)
  values ('1.2.0', 1, '1.0.0', '../etc', repeat('b', 64)) $$, '23514', null, 'path traversal in storage_path rejected');

set local role anon;
select is((select count(*)::int from public.model_versions), 1, 'anon can read model_versions');
select throws_ok($$ update public.model_versions set is_active = true $$, '42501', null, 'anon cannot activate a version');
reset role;

select is((select public from storage.buckets where id = 'model-bundles'), true, 'model-bundles bucket is public-read');

select * from finish();
rollback;
