-- D008: let the coach find the user's own custom exercises by name.
-- SECURITY INVOKER: row level security on custom_exercises limits the rows to the caller's own, so the result never
-- holds anyone else's exercises. `exercise_id` is the uuid as text, the same id get_exercise_history accepts.
create function public.search_custom_exercises(
  p_query     text,
  p_muscle    text default null,
  p_equipment text[] default null,
  p_limit     integer default 10
)
returns table (
  exercise_id     text,
  name            text,
  equipment       text,
  primary_muscles text[]
)
language sql
stable
security invoker
set search_path = public, extensions
as $$
  with q as (
    select public.normalize_search_text(btrim(coalesce(p_query, ''))) as n
  )
  select c.id::text, c.name, c.equipment, c.primary_muscles
  from public.custom_exercises c
  where c.deleted_at is null
    and ((select n from q) = ''
         or public.normalize_search_text(c.name)
              like ('%' || replace(replace(replace((select n from q), '\', '\\'), '%', '\%'), '_', '\_') || '%'))
    and (p_muscle is null or p_muscle = any (c.primary_muscles))
    and (p_equipment is null or c.equipment is null or c.equipment = any (p_equipment))
  order by c.name
  limit greatest(least(coalesce(p_limit, 10), 50), 1);
$$;

revoke all on function public.search_custom_exercises(text, text, text[], integer) from public, anon;
grant execute on function public.search_custom_exercises(text, text, text[], integer) to authenticated, service_role;
