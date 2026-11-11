# supabase/

Backend: Postgres şeması, Auth, Edge Functions ve Storage. Tüm tablolarda RLS zorunludur.

| Dizin | Amaç |
|---|---|
| `migrations/` | SQL göçleri |
| `functions/` | Edge Functions (AI Koç proxy vb.; Deno) |
| `seed/` | Yerel/test tohum verisi |
| `tests/` | pgTAP şema + RLS testleri |

Komutlar: `supabase db reset && supabase test db`, `deno test supabase/functions/`.
Gizli anahtarlar yalnızca Edge Function secrets'ta tutulur. Tasarım: [`docs/02-MIMARI.md`](../docs/02-MIMARI.md).
