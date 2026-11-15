-- D012: purge tombstones of score_snapshots and insights too, and schedule the nightly purge with pg_cron.
-- The function keeps its service-role-only grants (re-stated below because create or replace keeps them anyway).
-- Scheduling is skipped silently where pg_cron is not installed (local stack without the extension, tests).

create or replace function public.purge_soft_deleted(retention interval default interval '90 days')
returns table (table_name text, rows_deleted bigint)
language plpgsql
set search_path = ''
as $$
declare
  cutoff timestamptz;
  n bigint;
begin
  if retention is null or retention < interval '1 day' then
    raise exception 'retention must be at least 1 day' using errcode = '22023';
  end if;
  cutoff := now() - retention;

  with d as (delete from public.personal_records where deleted_at < cutoff returning 1)
    select count(*) into n from d;
  table_name := 'personal_records'; rows_deleted := n; return next;

  with d as (delete from public.sets where deleted_at < cutoff returning 1)
    select count(*) into n from d;
  table_name := 'sets'; rows_deleted := n; return next;

  with d as (delete from public.workout_exercises where deleted_at < cutoff returning 1)
    select count(*) into n from d;
  table_name := 'workout_exercises'; rows_deleted := n; return next;

  with d as (delete from public.workouts where deleted_at < cutoff returning 1)
    select count(*) into n from d;
  table_name := 'workouts'; rows_deleted := n; return next;

  with d as (delete from public.routine_exercises where deleted_at < cutoff returning 1)
    select count(*) into n from d;
  table_name := 'routine_exercises'; rows_deleted := n; return next;

  with d as (delete from public.routine_days where deleted_at < cutoff returning 1)
    select count(*) into n from d;
  table_name := 'routine_days'; rows_deleted := n; return next;

  with d as (delete from public.routines where deleted_at < cutoff returning 1)
    select count(*) into n from d;
  table_name := 'routines'; rows_deleted := n; return next;

  with d as (
    delete from public.custom_exercises ce
    where ce.deleted_at < cutoff
      and not exists (select 1 from public.routine_exercises r where r.custom_exercise_id = ce.id)
      and not exists (select 1 from public.workout_exercises w where w.custom_exercise_id = ce.id)
      and not exists (select 1 from public.personal_records p where p.custom_exercise_id = ce.id)
    returning 1)
    select count(*) into n from d;
  table_name := 'custom_exercises'; rows_deleted := n; return next;

  with d as (delete from public.body_measurements where deleted_at < cutoff returning 1)
    select count(*) into n from d;
  table_name := 'body_measurements'; rows_deleted := n; return next;

  with d as (delete from public.score_snapshots where deleted_at < cutoff returning 1)
    select count(*) into n from d;
  table_name := 'score_snapshots'; rows_deleted := n; return next;

  with d as (delete from public.insights where deleted_at < cutoff returning 1)
    select count(*) into n from d;
  table_name := 'insights'; rows_deleted := n; return next;
end;
$$;

revoke all on function public.purge_soft_deleted(interval) from public, anon, authenticated;
grant execute on function public.purge_soft_deleted(interval) to service_role;

do $cron$
begin
  if exists (select 1 from pg_available_extensions where name = 'pg_cron') then
    create extension if not exists pg_cron;
    perform cron.unschedule(jobid) from cron.job where jobname = 'purge-soft-deleted';
    perform cron.schedule('purge-soft-deleted', '30 3 * * *', 'select public.purge_soft_deleted()');
  end if;
end
$cron$;
