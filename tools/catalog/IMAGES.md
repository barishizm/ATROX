# Exercise images (P027)

Pipeline: `uv run catalog-images build` → `uv run catalog-images upload`.

## Format decision: WebP

Measured on 30 random source images (mean bytes/file): source JPG 50.9 KB; WebP q75 7.7 KB (320 px) / 27.9 KB (850 px);
HEIC q60 11.2 KB / 39.4 KB. WebP is ~30% smaller, decodes natively on iOS, and Pillow produces it on any machine.

## Sizes

Thumbnail 320 px wide; full = min(source width, 960). Upstream sources are 850 px, so full images are 850 px (no upscaling).

## Names and manifest

`<sha256(recipe+source bytes)[:16]>.t.webp` / `.f.webp`. Identical sources dedupe; any recipe change renames all files, so
URLs are safe to cache forever. `out/image_manifest.json` maps exercise id → `[{thumb, full, source}]` plus per-file size and
the list of bundled files. `out/image_report.md` has totals, images per exercise and exercises without images.

## Distribution

- Core-exercise thumbnails (309 files, 2.49 MB, budget 15 MB) are copied to `ios/App/Resources/ExerciseThumbs/`.
- Everything else is served from the public Supabase Storage bucket `exercise-images` (migration `20261112100000_…`).
- Upload: `SUPABASE_URL=… SUPABASE_SERVICE_ROLE_KEY=… uv run catalog-images upload [--dry-run]`. Uploads only files that
  are not yet in the bucket (HEAD on the public URL; names are content hashes, so "present" means "unchanged") with
  `Cache-Control: max-age=31536000`.
