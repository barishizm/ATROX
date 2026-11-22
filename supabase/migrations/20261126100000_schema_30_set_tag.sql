-- Set tags: an optional colour the lifter puts on a set ("Add tag" in the exercise screen).
-- Synced like the other set columns; null = no tag. Existing RLS policies on public.sets already cover the column.

alter table public.sets
  add column tag text,
  add constraint sets_tag_check check (tag is null or tag in ('green', 'teal', 'red', 'orange'));
