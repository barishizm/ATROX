-- P011 · Catalog tables: RLS, constraints, accent-insensitive search.
begin;
create extension if not exists pgtap with schema extensions;
select plan(40);

-- Fixtures (inserted as the superuser, i.e. like the service role).
insert into auth.users (id, instance_id, aud, role, email)
values
  ('00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'a@example.test'),
  ('00000000-0000-0000-0000-0000000000b2', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'b@example.test');

insert into public.exercises
  (id, equipment, mechanic, force, level, category, primary_muscles, secondary_muscles,
   movement_pattern, scoring_type, anchor_lift, load_convention, ratio, tau, ratio_confidence, is_core, bw_fraction)
values
  ('barbell_bench_press', 'barbell', 'compound', 'push', 'beginner', 'strength', '{chest}', '{triceps,shoulders}',
   'horizontal_push', 'weighted', 'bench', 'total', 1.0, 0.05, 'A', true, null),
  ('lat_pulldown', 'cable', 'compound', 'pull', 'beginner', 'strength', '{lats}', '{biceps}',
   'vertical_pull', 'weighted', 'bench', 'machine_stack', 0.9, 0.2, 'C', true, null),
  ('pull_up', 'body only', 'compound', 'pull', 'intermediate', 'strength', '{lats}', '{biceps}',
   'vertical_pull', 'bodyweight_loaded', 'bench', null, 0.8, 0.2, 'B', true, 1.0),
  ('plank', 'body only', 'isolation', 'static', 'beginner', 'strength', '{abdominals}', '{}',
   'core', 'time', null, null, null, null, null, false, null);

insert into public.exercise_translations (exercise_id, locale, name, aliases, instructions)
values
  ('barbell_bench_press', 'en', 'Barbell Bench Press', '{bench,flat bench}', '{Lie on the bench.}'),
  ('barbell_bench_press', 'tr', 'Barbell Bench Press (Göğüs)', '{göğüs press,bench press}', '{Sehpaya uzan.}'),
  ('lat_pulldown', 'en', 'Lat Pulldown', '{pulldown}', '{}'),
  ('lat_pulldown', 'tr', 'Geniş Tutuş Sırt Çekişi', '{lat çekiş,kablo sırt}', '{}'),
  ('pull_up', 'en', 'Pull-Up', '{chin up,pullup}', '{}'),
  ('pull_up', 'tr', 'Barfiks', '{}', '{}'),
  ('plank', 'en', 'Plank', '{}', '{}');

insert into public.catalog_versions (version, checksum) values (1, 'abc123');

-- Structure
select has_table('public', 'exercises', 'exercises exists');
select has_table('public', 'exercise_translations', 'exercise_translations exists');
select has_table('public', 'catalog_versions', 'catalog_versions exists');
select has_table('public', 'custom_exercises', 'custom_exercises exists');
select ok((select relrowsecurity from pg_class where oid = 'public.exercises'::regclass), 'exercises: RLS enabled');
select ok((select relrowsecurity from pg_class where oid = 'public.exercise_translations'::regclass), 'exercise_translations: RLS enabled');
select ok((select relrowsecurity from pg_class where oid = 'public.catalog_versions'::regclass), 'catalog_versions: RLS enabled');
select ok((select relrowsecurity from pg_class where oid = 'public.custom_exercises'::regclass), 'custom_exercises: RLS enabled');

-- Constraints (as superuser)
select throws_ok($$ insert into public.exercises (id, level, category, primary_muscles) values ('Bad Slug', 'beginner', 'strength', '{chest}') $$,
  '23514', null, 'exercises: id must be a lowercase slug');
select throws_ok($$ insert into public.exercises (id, level, category, primary_muscles) values ('x1', 'god', 'strength', '{chest}') $$,
  '23514', null, 'exercises: invalid level rejected');
select throws_ok($$ insert into public.exercises (id, level, category, primary_muscles) values ('x2', 'beginner', 'strength', '{wings}') $$,
  '23514', null, 'exercises: unknown muscle rejected');
select throws_ok($$ insert into public.exercises (id, level, category, primary_muscles) values ('x3', 'beginner', 'strength', '{}') $$,
  '23514', null, 'exercises: primary muscles must not be empty');
select throws_ok($$ insert into public.exercises (id, level, category, primary_muscles, scoring_type) values ('x4', 'beginner', 'strength', '{chest}', 'weighted') $$,
  '23514', null, 'exercises: weighted scoring requires anchor/ratio/tau/convention/confidence');
select throws_ok($$ insert into public.exercises (id, level, category, primary_muscles, scoring_type, anchor_lift, ratio, tau, ratio_confidence)
                    values ('x5', 'beginner', 'strength', '{chest}', 'bodyweight_loaded', 'bench', 0.5, 0.2, 'B') $$,
  '23514', null, 'exercises: bodyweight_loaded requires bw_fraction');
select throws_ok($$ insert into public.exercises (id, level, category, primary_muscles, ratio_confidence) values ('x6', 'beginner', 'strength', '{chest}', 'D') $$,
  '23514', null, 'exercises: ratio_confidence must be A/B/C');
select throws_ok($$ insert into public.exercise_translations (exercise_id, locale, name) values ('plank', 'en', 'Dup') $$,
  '23505', null, 'translations: (exercise_id, locale) is unique');
select throws_ok($$ insert into public.exercise_translations (exercise_id, locale, name) values ('nope', 'en', 'Orphan') $$,
  '23503', null, 'translations: exercise must exist');
select throws_ok($$ insert into public.exercise_translations (exercise_id, locale, name) values ('plank', 'turkish', 'x') $$,
  '23514', null, 'translations: malformed locale rejected');

-- Search (as anon: the catalog is public)
set local role anon;
select is((select count(*)::int from public.exercises), 4, 'anon can read exercises');
select is((select count(*)::int from public.catalog_versions), 1, 'anon can read catalog_versions');

select is((select exercise_id from public.search_exercises('barfiks', 'tr') limit 1), 'pull_up', 'search: Turkish name');
select is((select exercise_id from public.search_exercises('BARFİKS', 'tr') limit 1), 'pull_up', 'search: dotted capital İ folds to i');
select is((select exercise_id from public.search_exercises('sirt', 'tr') limit 1), 'lat_pulldown', 'search: "sirt" finds "Sırt" (accent-insensitive)');
select is((select exercise_id from public.search_exercises('gogus', 'tr') limit 1), 'barbell_bench_press', 'search: "gogus" finds "Göğüs"');
select is((select exercise_id from public.search_exercises('genis tutus', 'tr') limit 1), 'lat_pulldown', 'search: ş/ı folded in multi-word query');
select is((select name from public.search_exercises('pull-up', 'tr') limit 1), 'Barfiks', 'search: result name uses the requested locale');
select is((select name from public.search_exercises('plank', 'tr') limit 1), 'Plank', 'search: falls back to English name');
select is((select exercise_id from public.search_exercises('chin up') limit 1), 'pull_up', 'search: alias match');
select is((select exercise_id from public.search_exercises('benchpress') limit 1), 'barbell_bench_press', 'search: typo tolerance (missing space)');
select is((select count(*)::int from public.search_exercises('zzzzqqq')), 0, 'search: no match returns nothing');
select is((select count(*)::int from public.search_exercises('100%')), 0, 'search: LIKE wildcards in input are escaped');
select is((select count(*)::int from public.search_exercises('', 'en', 'lats')), 2, 'search: empty query browses by muscle filter');
select is((select exercise_id from public.search_exercises('', 'en', null, array['body only']) limit 1), 'pull_up', 'search: equipment filter, core first');
select is((select count(*)::int from public.search_exercises('pull', 'en', 'chest')), 0, 'search: muscle filter excludes non-matching');

-- Catalog is read-only for anon and authenticated.
select throws_ok($$ insert into public.exercises (id, level, category, primary_muscles) values ('hack', 'beginner', 'strength', '{chest}') $$,
  '42501', null, 'anon cannot insert exercises');
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000a1","role":"authenticated"}', true);
select throws_ok($$ insert into public.catalog_versions (version, checksum) values (2, 'x') $$,
  '42501', null, 'authenticated cannot insert catalog_versions');
select throws_ok($$ update public.exercise_translations set name = 'hacked' $$,
  '42501', null, 'authenticated cannot update translations');

-- custom_exercises: owner only.
select lives_ok($$
  insert into public.custom_exercises (id, user_id, name, primary_muscles)
  values ('50000000-0000-0000-0000-00000000000a', '00000000-0000-0000-0000-0000000000a1', 'My Curl', '{biceps}')
$$, 'owner can insert own custom exercise');
select throws_ok($$
  insert into public.custom_exercises (id, user_id, name, primary_muscles)
  values ('50000000-0000-0000-0000-0000000000ff', '00000000-0000-0000-0000-0000000000b2', 'Spoof', '{biceps}')
$$, '42501', null, 'cannot insert custom exercise for another user');

select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000b2","role":"authenticated"}', true);
select is((select count(*)::int from public.custom_exercises), 0, 'other user cannot see custom exercises');

select * from finish();
rollback;
