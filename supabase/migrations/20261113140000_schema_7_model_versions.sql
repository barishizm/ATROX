-- P063 · Model bundle versions (docs/03-ML-MODEL.md §11 "Güncelleme").
-- The app reads active rows, downloads the bundle files from the `model-bundles` bucket
-- (<storage_path>/manifest.json, manifest.sig and the files the manifest lists), verifies the Ed25519 signature and
-- digests, runs a smoke test and activates it. Rows are written by the service role only (`ml` publish script);
-- setting is_active = false rolls clients back to the newest remaining active version (or the embedded bundle).
create table public.model_versions (
  version          text primary key,
  schema_version   integer not null,
  min_app_version  text not null,
  storage_path     text not null unique,
  manifest_sha256  text not null,
  metrics          jsonb not null default '{}'::jsonb,
  is_active        boolean not null default false,
  rollout_percent  integer not null default 100,
  released_at      timestamptz not null default now(),

  constraint model_versions_version_check check (version ~ '^[0-9]+\.[0-9]+\.[0-9]+$'),
  constraint model_versions_min_app_version_check check (min_app_version ~ '^[0-9]+\.[0-9]+\.[0-9]+$'),
  constraint model_versions_schema_version_check check (schema_version > 0),
  constraint model_versions_storage_path_check check (
    storage_path ~ '^[A-Za-z0-9._-]+(/[A-Za-z0-9._-]+)*$' and storage_path !~ '(^|/)\.\.?(/|$)'),
  constraint model_versions_manifest_sha256_check check (manifest_sha256 ~ '^[0-9a-f]{64}$'),
  constraint model_versions_metrics_check check (jsonb_typeof(metrics) = 'object'),
  constraint model_versions_rollout_percent_check check (rollout_percent between 0 and 100)
);

comment on table public.model_versions is
  'P063: published model bundles. Public read; service role writes. is_active=false rolls clients back.';

alter table public.model_versions enable row level security;
revoke all on public.model_versions from anon, authenticated;
grant select on public.model_versions to anon, authenticated;
create policy model_versions_select_all on public.model_versions
  for select to anon, authenticated using (true);

-- Bundle files are signed and not secret: public bucket, writes only by the service role (no write policies).
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('model-bundles', 'model-bundles', true, 10485760, array['application/json', 'application/octet-stream'])
on conflict (id) do update
  set public = excluded.public,
      file_size_limit = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;
