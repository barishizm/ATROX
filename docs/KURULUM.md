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
