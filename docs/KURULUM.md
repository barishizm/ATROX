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


## Kimlik sağlayıcıları (P014)

### Sabitler

| Ne | Değer |
|---|---|
| Bundle ID'ler | Release `com.barishizm.vesania` · Staging `com.barishizm.vesania.staging` · Debug `com.barishizm.vesania.debug` |
| Derin bağlantı şeması | `vesania` (`APP_URL_SCHEME`, `ios/Config/Base.xcconfig`) |
| Auth dönüş URL'si | `vesania://auth-callback` |
| Supabase Auth callback (Google web istemcisi için) | `https://<PROJE_REF>.supabase.co/auth/v1/callback` |
| Uzak ortamlar | staging `yjcfdntilceqndkwiwdn`, prod `wafbrnsfxrwknczgkjkh` — **her adım iki projede de yapılır** |

Depoda yapılanlar (elle dokunma): `ios/project.yml` (Sign in with Apple entitlement'ı, `CFBundleURLTypes`,
`GIDClientID`, `GIDServerClientID`), `ios/Config/Base.xcconfig` (yer tutucular), `ios/Config/Secrets.example.xcconfig`
(Google değerleri şablonu), `supabase/config.toml` (şifre politikası, şablon yolları), `supabase/templates/*.html`.

### 1. Sign in with Apple

> **ERTELENDİ:** Apple Developer Program üyeliği release öncesine bırakıldı. Entitlement ve proje ayarı depoda hazır; App ID'ler,
> Supabase Apple sağlayıcısı ve `DEVELOPMENT_TEAM` release öncesi aşağıdaki adımlarla yapılır.

Yerel (native) akış: uygulama `ASAuthorization` ile Apple'dan `id_token` alır, Supabase'e `signInWithIdToken` ile verir.
Bu akış için **Services ID ve `.p8` anahtarı gerekmez**; Supabase yalnızca token'ın hedef kitlesini (bundle ID) doğrular.

1. <https://developer.apple.com/account> → **Certificates, Identifiers & Profiles** → **Identifiers**.
2. Üç App ID için (Release, Staging, Debug bundle ID'leri) `+` → **App IDs** → **App** ile oluştur, ya da mevcutsa aç.
   **Capabilities** listesinde **Sign in with Apple**'ı işaretle → **Edit** → *Enable as a primary App ID* → Save → Continue → Register.
3. Supabase paneli (her proje için) → **Authentication** → **Sign In / Providers** → **Apple**:
   - **Enable Sign in with Apple** açık.
   - **Client IDs**: üç bundle ID'yi virgülle yaz (`com.barishizm.vesania,com.barishizm.vesania.staging,com.barishizm.vesania.debug`).
   - **Secret Key** boş kalır (yalnızca web OAuth için gerekir). Save.
4. Xcode imzalaması için Team ID gerekir: developer.apple.com → **Membership details** → *Team ID*. Değeri `ios/Config/Base.xcconfig`
   içine `DEVELOPMENT_TEAM = <TEAM_ID>` olarak ekle (gizli değil, commit edilir).

> Hesap silme akışı (`delete-account`) Apple token'ını iptal edecekse o adımda **Sign in with Apple anahtarı** (`.p8`, Key ID)
> oluşturulur; şimdilik gerekmez.

### 2. Google Sign-In

1. <https://console.cloud.google.com> → proje oluştur/seç → **Google Auth Platform** (veya *APIs & Services → OAuth consent screen*):
   uygulama adı, destek e-postası, **External**, yayın durumu *Testing* (lansmandan önce *In production*).
2. **Clients** (Credentials) → **Create client** → *Web application* (her Supabase projesi için ayrı önerilir):
   - **Authorized redirect URIs**: `https://<PROJE_REF>.supabase.co/auth/v1/callback`.
   - Oluşunca **Client ID** ve **Client secret**'ı şifre yöneticisine kaydet.
3. **Create client** → *iOS* — her bundle ID için ayrı bir istemci (Debug / Staging / Release). **Bundle ID** alanına ilgili ID'yi yaz.
   Her istemcinin sayfasındaki **Client ID** ve **iOS URL scheme** (`com.googleusercontent.apps.…`) değerlerini not et.
4. `ios/Config/Secrets.xcconfig` (gitignored; şablon `Secrets.example.xcconfig`): `GOOGLE_WEB_CLIENT_ID`,
   ve her konfigürasyon için `GOOGLE_IOS_CLIENT_ID[config=…]` + `GOOGLE_REVERSED_CLIENT_ID[config=…]` değerlerini doldur.
   `project.yml` bu değerleri `GIDClientID`/`GIDServerClientID` ve URL şeması olarak Info.plist'e taşır.
5. Supabase paneli → **Authentication → Sign In / Providers → Google**:
   - **Enable** açık; **Client IDs**: web Client ID **ilk** sırada, ardından iOS Client ID'leri (virgülle).
   - **Client Secret**: web istemcisinin secret'ı.
   - **Skip nonce checks**: açık (GoogleSignIn SDK'sı P015'te nonce ile doğrulanırsa kapatılır). Save.

### 3. E-posta ile giriş

Politika (`supabase/config.toml`, yerel olarak doğrulandı): doğrulama zorunlu (`enable_confirmations = true`), şifre en az 8 karakter,
küçük + büyük harf + rakam içermeli.

Her uzak projede **Authentication → Sign In / Providers → Email**: *Confirm email* açık. Şifre politikası aynı sayfadaki
*Minimum password length = 8* ve *Password Requirements = Lowercase, uppercase letters and digits* alanlarıdır.

**Şablonlar** (`supabase/templates/`): `confirmation.html` (kayıt doğrulama), `recovery.html` (şifre sıfırlama), `email_change.html`.
Dil, kullanıcının `user_metadata.locale` değerinden seçilir: `en` → İngilizce, aksi halde Türkçe. AuthService (P015),
kayıt sırasında `data: {"locale": "tr" | "en"}` göndermelidir. Konu satırı dile göre dallanamadığı için iki dillidir.
E-postada hem düğme (`{{ .ConfirmationURL }}`) hem 6 haneli kod (`{{ .Token }}`) bulunur; posta istemcisi özel şemayı açmazsa kod kullanılır.

> **BEKLİYOR:** Supabase, şablon düzenlemek için önce özel SMTP istiyor. Alan adı + SMTP sağlayıcısı hazır olunca
> SMTP bağlanır, ardından şablonlar yüklenir. O zamana kadar uzak projeler varsayılan (İngilizce) e-postaları gönderir.

Uzak projelere uygulama: **Authentication → Emails → Templates** → *Confirm sign up*, *Reset password*, *Change email address*;
her birine ilgili dosyanın içeriğini ve konu satırını (config.toml'daki `subject`) yapıştır.

> **`supabase config push` kullanma.** `config.toml` sağlayıcıları yerelde `enabled = false` tuttuğu için push, panelde açtığın
> Apple/Google sağlayıcılarını kapatır.

> **Lansmandan önce:** Supabase'in yerleşik e-posta servisi uzak projede saatte çok düşük sayıda e-posta gönderir.
> Kendi SMTP sağlayıcını (Resend, Postmark vb.) **Authentication → Emails → SMTP Settings**'e bağla. (Ertelenenler'e eklendi.)

### 4. Derin bağlantı ve yönlendirme URL'leri

Her uzak projede **Authentication → URL Configuration**:

- **Site URL**: `vesania://auth-callback`
- **Redirect URLs**: `vesania://auth-callback`

Yerelde aynı değerler `supabase/config.toml` içindedir (`site_url`, `additional_redirect_urls`). Uygulama `onOpenURL`
ile `vesania://auth-callback#…` bağlantılarını yakalayıp Supabase istemcisine verir (P015).
Debug ve Staging aynı şemayı paylaşır; aynı cihazda ikisi birden kuruluysa iOS birini seçer — test ederken birini sil.

### 5. Doğrulama

```bash
cd ios && xcodegen generate
xcodebuild build -project ios/GymAnalyzer.xcodeproj -scheme GymAnalyzer \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO
```

Panel kontrolü: her projede Apple, Google ve Email sağlayıcıları **Enabled** görünür; URL Configuration yukarıdaki değerleri içerir.
