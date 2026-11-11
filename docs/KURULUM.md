# KURULUM — Hangi anahtar nerede saklanır

> Bu dosya yalnızca **saklama yerlerini** listeler. Gerçek değerler depoya, bu dosyaya, commit mesajlarına
> veya sohbet/issue metinlerine **asla** yazılmaz.

Saklama yerleri:

- **PM** = Şifre yöneticisi (1Password/Bitwarden vb.). Tek doğruluk kaynağı.
- **EF** = Supabase Edge Function secrets (`supabase secrets set NAME=…`). Uygulamaya girmez.
- **xcconfig** = `ios/Config/*.xcconfig` (yerel, `.gitignore`'da; depoda yalnızca `*.example`).
- **Depo** = Gizli olmayan değer; commit edilebilir.

| Hesap | Değer | Gizli mi? | Nerede saklanır |
|---|---|---|---|
| Apple Developer Program | Team ID | Hayır | Depo (`ios/project.yml` → `DEVELOPMENT_TEAM`) + PM notu |
| Apple Developer Program | Bundle ID, App ID | Hayır | Depo (`ios/project.yml`) |
| Apple Developer Program | Sign in with Apple Services ID, Key ID | Hayır | PM notu |
| Apple Developer Program | Sign in with Apple `.p8` özel anahtarı | **Evet** | PM (dosya eki) + Supabase Auth paneli; depoya girmez |
| Apple Developer Program | App Store Connect API anahtarı (`.p8`, Issuer ID) | **Evet** | PM; CI kullanılırsa CI secret'ı |
| Supabase (staging) | Proje referansı, proje URL'si | Hayır | Depo (`docs/KURULUM.md` altına eklenecek; anahtar değil) |
| Supabase (staging) | `anon` / publishable anahtar | Hayır (RLS korur) | xcconfig (`Staging.xcconfig`) |
| Supabase (staging) | `service_role` anahtarı | **Evet** | PM; yalnızca sunucu tarafı, uygulamaya asla girmez |
| Supabase (staging) | Veritabanı parolası | **Evet** | PM |
| Supabase (prod) | Proje referansı, proje URL'si | Hayır | Depo (referans) |
| Supabase (prod) | `anon` / publishable anahtar | Hayır (RLS korur) | xcconfig (`Production.xcconfig`) |
| Supabase (prod) | `service_role` anahtarı | **Evet** | PM; yalnızca sunucu tarafı |
| Supabase (prod) | Veritabanı parolası | **Evet** | PM |
| Supabase (her ikisi) | Kişisel erişim jetonu (CLI/MCP) | **Evet** | PM; `supabase login` ile macOS anahtar zincirine yazılır |
| Supabase (her ikisi) | Model paketi Ed25519 **özel** anahtarı | **Evet** | PM (çevrimdışı yedekle); **açık** anahtar uygulamaya gömülür (Depo) |
| OpenRouter | API anahtarı | **Evet** | EF (`OPENROUTER_API_KEY`, staging ve prod ayrı) + PM |
| OpenRouter | Aylık harcama limiti | Hayır | OpenRouter panelinde anahtar başına ayarlanır; değeri PM notuna yaz |
| DeepSeek platformu | Yedek API anahtarı | **Evet** | EF (`DEEPSEEK_API_KEY`) + PM |
| Google Cloud | iOS OAuth istemci kimliği (Client ID) | Hayır | xcconfig / Info.plist (`GIDClientID`) |
| Google Cloud | Reversed Client ID (URL scheme) | Hayır | Info.plist (`project.yml` üzerinden) |
| Google Cloud | Web OAuth istemcisi — Client ID + **Secret** | Secret **evet** | Secret: PM + Supabase Auth paneli; ID: PM notu |
| TelemetryDeck | Uygulama kimliği (App ID) | Hayır | xcconfig / Depo |

## Kurallar

1. Depoya yalnızca `*.example` şablonları girer; gerçek `*.xcconfig` ve `.env*` dosyaları `.gitignore`'dadır.
2. Her ortam (staging / prod) için ayrı anahtar kullan; anahtarları ortamlar arasında paylaşma.
3. Bir anahtar sohbete, ekran görüntüsüne veya commit'e sızarsa hemen yenile (rotate) ve eskisini iptal et.

## Supabase kurulumu (P009)

### Ön koşullar

- Supabase CLI (`brew install supabase/tap/supabase`) ve Docker uyumlu bir çalışma zamanı (Docker Desktop, OrbStack veya Colima).
- Yerel yığın için Docker en az ~7 GB bellek ile çalışmalıdır.

### Yerel yığın

```bash
supabase start        # yığını başlatır; URL ve yerel anahtarları yazdırır
supabase status       # çalışan servisler ve adresler
supabase db reset     # veritabanını sıfırlar: göçler + supabase/seed/*.sql
supabase test db      # pgTAP testleri (supabase/tests/)
supabase stop         # durdurur (veriyi korur); --no-backup ile veriyi de siler
```

Yerel portlar (`supabase/config.toml`): API `54321`, DB `54322`, Studio `54323`, e-posta test kutusu (Mailpit) `54324`.
Yerel kayıt e-postaları Mailpit'te okunur: <http://127.0.0.1:54324>.

Auth ayarları: e-posta doğrulaması **açık** (`enable_confirmations = true`); Apple ve Google sağlayıcıları
`enabled = false` yer tutucusudur. Sırlar `env(SUPABASE_AUTH_EXTERNAL_*_SECRET)` ile okunur, dosyaya yazılmaz.
Sağlayıcı açılırken: ilgili `client_id` doldurulur, `enabled = true` yapılır ve sır `supabase/.env` içine konur (gitignored).

### Uzak projeler

| Ortam | Proje adı | Proje referansı | Bölge |
|---|---|---|---|
| staging | `gymanalyzer-staging` | `yjcfdntilceqndkwiwdn` | eu-central-1 (Frankfurt) |
| prod | `gymanalyzer-prod` | `wafbrnsfxrwknczgkjkh` | eu-central-1 (Frankfurt) |

Referanslar gizli değildir; anahtarlar ve veritabanı parolaları yalnızca şifre yöneticisinde tutulur (yukarıdaki tablo).

```bash
supabase login                              # jeton macOS anahtar zincirine yazılır
supabase link --project-ref <STAGING_REF>   # staging'e bağla (parola sorulur)
supabase link --project-ref <PROD_REF>      # prod'a bağlamak için aynı komut; bağlantı tek seferde birine yapılır
```

Aynı anda tek proje bağlı olur (`supabase/.temp/`, gitignored). Push öncesi `supabase projects list` ile
bağlı projenin doğru olduğunu doğrula.

### Göç (migration) iş akışı

1. **Yerelde yaz:** `supabase migration new <ad>` → `supabase/migrations/<zaman>_<ad>.sql` düzenle.
2. **Yerelde dene:** `supabase db reset && supabase test db`. Hata varsa göçü düzelt (henüz push edilmediyse yerinde düzenlenebilir).
3. **Staging'e push:** `supabase link --project-ref <STAGING_REF>` → `supabase db push --dry-run` → `supabase db push`.
4. **Staging'de doğrula** (uygulama + RLS testleri).
5. **Prod'a push:** `supabase link --project-ref <PROD_REF>` → `supabase db push --dry-run` → `supabase db push`.

Kurallar: push edilmiş bir göç asla düzenlenmez, yeni göç eklenir. Tüm tablolarda RLS zorunludur.
Panelden elle şema değişikliği yapılmaz. Prod push'ları yalnızca staging'de doğrulanmış göçler için yapılır.

