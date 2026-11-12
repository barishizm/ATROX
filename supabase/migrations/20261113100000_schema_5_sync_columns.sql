-- P044 · Columns the sync engine needs that were local-only so far, and the server clock for skew correction.
--   workouts.source / rating / health_kit_uuid   (P035, P041)
--   (custom_exercises.is_unilateral already exists since schema_4; the sync now sends it)
--   public.server_time()                          the device measures its clock offset against it (docs/02-MIMARI.md §2.4)

alter table public.workouts
  add column source          text not null default 'manual',
  add column rating          smallint,
  add column health_kit_uuid uuid,
  add constraint workouts_source_check check (source in ('manual', 'routine', 'onboarding', 'import')),
  add constraint workouts_rating_check check (rating is null or rating between 1 and 5);

create function public.server_time()
returns timestamptz
language sql
stable
set search_path = ''
as $$
  select now();
$$;

revoke all on function public.server_time() from public, anon;
grant execute on function public.server_time() to authenticated;
