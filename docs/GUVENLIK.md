# Güvenlik incelemesi (P102)

Kapsam: veritabanı (RLS, fonksiyonlar, kovalar), Edge Functions, AI Koç (LLM), iOS istemcisi, kötüye kullanım, bağımlılıklar.
Yöntem: kod incelemesi + otomatik kapılar (pgTAP RLS denetimi, Supabase güvenlik danışmanı `--fail-on warn`, `tools/scan-secrets.sh`).

## Tehdit modeli (özet)

| Varlık | Tehdit | Ana savunma |
|---|---|---|
| Kullanıcı antrenman/sağlık verisi | Başka kullanıcının okuması | Her tabloda RLS + pgTAP matrisi (`020_rls_matrix`), `security definer` yalnızca `auth.uid()` ile |
| Servis rolü anahtarı, DeepSeek/Apple anahtarları | Sızıntı | Yalnızca Edge Function secrets; uygulamada anahtar yok; CI'da gizli anahtar taraması |
| AI Koç | İstem enjeksiyonu, başkasının verisi, onaysız değişiklik, maliyet tüketimi | Veri sarmalama (`<user_data>`), araçlar kullanıcının JWT'siyle (RLS), öneriler onay kartı, kota + günlük harcama tavanı |
| Anonim katkı | Yeniden kimliklendirme | `user_id` yok, yabancı anahtar yok, k ≥ 20 dışa aktarım |
| Abonelik | Sahte yetki | Sunucuda JWS doğrulama, işlem sahipliği kontrolü |
| Sosyal | Kullanıcı sızıntısı, taciz | Politikasız tablolar + fonksiyonlar, engelleme, hız sınırı |

## Bulgular ve düzeltmeler

| # | Önem | Bulgu | Durum |
|---|---|---|---|
| 1 | Orta | `social_are_friends` / `social_is_blocked` herhangi bir oturum açmış kullanıcıya rastgele iki uuid için çalışıyordu: üçüncü kişilerin arkadaşlık/engel ilişkisini sorgulama (oracle). | **Düzeltildi** — göç `schema_23`: yardımcılar yalnızca ilk argüman çağıran ise gerçek cevap verir; pgTAP `029_security_hardening`. |
| 2 | Orta | Koç yanıtındaki Markdown bağlantıları/görselleri dokunulabilirdi: istem enjeksiyonu ile `[etiket](https://kötü)` veya `atrox://start/...` derin bağlantısı üretilebilir. | **Düzeltildi** — `MarkdownInline`: bağlantı ve görsel öznitelikleri silinir, etiket düz metin kalır; birim testi. |
| 3 | Orta | CI'da gizli anahtar taraması yoktu. | **Düzeltildi** — `tools/scan-secrets.sh` + `core.yml` `secrets` işi (özel anahtar, `sk-`, JWT, AWS/GitHub/Google/Slack biçimleri, servis rolü atamaları). Depo şu an temiz. |
| 4 | Düşük | `Access-Control-Allow-Origin: *`. | **Düzeltildi** — başlık kaldırıldı; tek istemci yerel uygulama (CORS uygulanmaz), tarayıcıdaki başka kökenler reddedilir. |
| 5 | Düşük | Sahte istemciyle koç proxy'sini tüketme (App Attest yok). | **Ertelendi** (aşağıda). |
| 6 | Düşük | `contribute` hız sınırı kullanıcı kimliğiyle tutulur; katkı satırlarıyla bağ yok ama zaman bağıntısı teorik olarak mümkün. | **Kabul edildi** — sayaç tablosu istemciye kapalı, katkı tablosunda zaman damgası yok (yalnızca ay), k-anonimlik süzgeci var. |
| 7 | Düşük | `startWorkout` derin bağlantısı (`atrox://start/<id>/<id>`) başka uygulamadan/web'den tetiklenebilir. | **Kabul edildi** — yalnızca antrenman ekranını açar (UUID'ler doğrulanır, veri değiştirmez, tek dokunuşla geri alınır); bağlantı artık koç metninden de üretilemez (#2). |

### İncelenenler (bulgu yok)

- **Veritabanı:** tüm `security definer` fonksiyonlarında `set search_path = ''`; hepsinde `public`/`anon` yürütme hakkı geri alınmış, yalnızca `authenticated` veya `service_role`; her tabloda RLS + politika (`001_rls_audit`); kovalar: yalnızca katalog görselleri herkese açık (kasıtlı), kullanıcı verisi kovası yok; `supabase db advisors --fail-on warn` CI'da.
- **Edge Functions:** her uç `requireUser` (tek istisna `appstore-notifications`: Apple JWS imzası kimlik doğrulamadır, `verify_jwt=false` gerekçeli); girdi Zod/elle şema ile `strict`; hız sınırı/kota (koç, katkı, sosyal); hatalarda iç ayrıntı yok; loglarda yalnızca `error.message` (kullanıcı kimliği/yük/anahtar yok); servis rolü yalnızca kota/harcama/kullanım/abonelik ve katkı yazımında, kullanıcı verisi kullanıcının JWT'siyle.
- **LLM:** kullanıcı metinleri (not, hareket/rutin adı, bellek, özet) `asData` ile `<user_data>` içine alınır ve `<>` etkisizleştirilir; sistem istemi araç sonuçlarını da veri sayar; araçlar `CoachDb.rpc` ile kullanıcının JWT'sini kullanır (başkasının verisi RLS'ten geçmez); öneri araçları onay kartı üretir, bellek kaydı geri alınabilir; LLM'e kimlik/e-posta gitmez; koç güvenlik seti (P082) yayın kapısı.
- **İstemci:** Supabase oturumu Keychain'de, PKCE akışı; katkı anahtarı Keychain'de; derin bağlantılar yalnızca doğrulanmış kalıplara çözülür (UUID, kullanıcı adı politikası, bilinen sekmeler), yabancı ana makineler reddedilir; model paketi Ed25519 ile doğrulanır; ATS varsayılan (istisna yok); Swift paketleri `exact` sürümlü; GitHub Actions tam SHA'ya sabit; Python `uv sync --frozen`.

## Modernizasyon, gizlilik ve App Store denetimi (2026-11-16)

Kapsam: Swift/iOS API güncelliği, güvenlik, gizlilik, App Store kuralları. Sonuç: kod tabanı güncel (Swift 6 strict concurrency, iOS 26, SwiftData, `@Observable`, async/await; `ObservableObject`, Combine, `NavigationView`, `DispatchQueue` yok; gizlilik manifestleri geçerli; hesap silme, Sign in with Apple, abonelik koşulları, geri yükleme, UGC bildir/engelle, AI onayı mevcut). Düzeltilenler:

| Önem | Bulgu | Düzeltme |
|---|---|---|
| Orta | `ITSAppUsesNonExemptEncryption` yoktu: her TestFlight/App Store yüklemesinde ihracat uyumluluğu sorusu çıkıyordu. Uygulama yalnızca HTTPS ve CryptoKit kullanır (muaf). | `project.yml` + `Info.plist`: `false`. |
| Orta | Web sitesinde yalnızca `nosniff` ve `Referrer-Policy` vardı: tıklama hırsızlığı (iframe), HSTS ve CSP yoktu. | `web/vercel.json`: HSTS, `X-Frame-Options: DENY`, sıkı CSP (`/u` satır içi betiği hash ile; HSTS `preload` alan adı kesinleşince kullanıcı kararı), COOP, Permissions-Policy; `tools/test_web_csp.py` hash kaymasını yakalar. |
| Yüksek | HealthKit okuma izni metni "veriler cihazından çıkmaz" diyordu; oysa içe aktarılan boy/kilo/doğum tarihi/cinsiyet profile yazılıp hesapla senkronize ediliyor (yanıltıcı beyan, 5.1.1/5.1.3). | `NSHealthShareUsageDescription` (EN/TR; `project.yml`, `Info.plist`, `InfoPlist.xcstrings`) gerçek davranışı söylüyor: hesaba yalnızca skor için kaydedilir, reklam için kullanılmaz, satılmaz. |
| Düşük | Saf kilit kutuları `@unchecked Sendable` + `NSLock` idi (Swift 6'da derleyici denetimsiz). | `InMemoryCoachCache.Box` ve `InMemoryContributionKeyStore` `Synchronization.Mutex` ile denetimli `Sendable` oldu. |
| Düşük | Supabase `secure_password_change = false`: eski oturumla parola değiştirilebiliyordu. | `config.toml`: `true` (uzak projede de Auth ayarında açılmalı `[MANUEL]`). |

Bilinen kalan boşluk: `UserDefaults` bu SDK'da `Sendable` değil (Apple belgelerinde iş parçacığı güvenli). Dağınık 6 `@unchecked` yerine tek, gerekçesi yazılı `SendableDefaults` sarmalayıcısı kullanılıyor; `Mutex(UserDefaults)` derleyici tarafından reddedildi, suite-adı yolu ~30 test çağrısını değiştireceği için ertelendi. Kalan `@unchecked Sendable`: `SendableDefaults`, `UserDefaultsContributionStateStore`, `HKHealthStore`/`MXMetricManager`/`CatalogCache` sarmalayıcıları. Parola değişikliği yalnızca kurtarma akışında (taze oturum) olduğundan `secure_password_change` uygulama içi akışı bozmaz.

## App Attest kararı (ertelendi)

Değerlendirme: App Attest, koç proxy'sini yalnızca gerçek ATROX uygulaması çağırsın diye faydalıdır. Ancak (a) sunucuda Apple attestation doğrulaması, anahtar/sayaç saklama ve Apple geliştirici hesabında capability gerektirir, (b) simülatör/CI/Debug derlemelerinde çalışmaz, (c) saldırgan zaten geçerli, onay vermiş, kota sahibi bir hesap gerektirir: sahte istemci bile `coach_consume_quota` (dakika + gün), kullanıcı başına kota ve **küresel günlük harcama tavanı** (`coach_unavailable`) sınırlarına tabidir.

Karar: lansman için ertelendi; kalan risk "bir hesapla kota kadar tüketim + ucuz hesap açma". Hesap açma e-posta onaylı/Apple/Google girişli. Tetikleyiciler: günlük harcama tavanına tekrar eden ulaşma, `coach_usage` içinde kota sınırında duran çok sayıda yeni hesap. O zaman: `DCAppAttestService` + `attest-key` Edge Function + `coach-chat` başlığı. Ertelenenler'e yazıldı.

## Kabul edilen riskler

Bulgu #6, #7 ve App Attest ertelemesi. Yüksek önemli açık bulgu yok.

## Elle yapılacaklar (`[MANUEL]`)

- Prod'da `supabase db advisors --linked --type security` çalıştırıp çıktıyı bu belgeye ekle.
- Yayın öncesi: Supabase paneli > Auth > e-posta onayı açık, sızdırılmış parola korumasını aç (Pro planı), `functions` secrets listesini gözden geçir, DeepSeek harcama tavanı.
- Bağımlılık güncellemelerinde (supabase-swift, GoogleSignIn, zod, uv.lock) sürüm değişikliğini bu listeye karşı gözden geçir.
