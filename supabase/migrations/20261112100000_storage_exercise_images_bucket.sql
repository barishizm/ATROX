-- P027: public bucket for exercise images (content-addressed WebP files, long-lived Cache-Control).
-- Public read comes from the bucket's `public` flag; writes need the service role (no insert/update/delete policies).
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('exercise-images', 'exercise-images', true, 2097152, array['image/webp'])
on conflict (id) do update
  set public = excluded.public,
      file_size_limit = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;
