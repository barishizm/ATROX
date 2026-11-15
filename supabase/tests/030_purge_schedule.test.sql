-- D012 · purge_soft_deleted also covers score_snapshots and insights.
begin;
select plan(3);

select ok(exists (select 1 from public.purge_soft_deleted(interval '365 days') where table_name = 'score_snapshots'),
  'purge reports score_snapshots');
select ok(exists (select 1 from public.purge_soft_deleted(interval '365 days') where table_name = 'insights'),
  'purge reports insights');
select throws_ok($$ select * from public.purge_soft_deleted(interval '0 days') $$, '22023', null, 'retention guard still applies');

select * from finish();
rollback;
