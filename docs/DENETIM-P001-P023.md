# Denetim — P001–P023 (Faz 0, 1, 2)

- **Tarih:** 2026-11-12
- **Denetlenen commit:** `6963626` (`main`, PR #25 birleşmesi). `origin/main` bundan sonra 3 commit önde
  (`4cbb51b`, `27fa412`, `20a3b81` — PR #26 "Rename project to ATROX"). O fark yalnızca ad değişikliği
  (`GymAnalyzer`/`Vesania` → `ATROX`, CI önbellek anahtarı); `git diff 6963626 origin/main` içinde mantık değişikliği yok.
  Bu yüzden aşağıdaki bulgular güncel `main` için de geçerlidir; yalnızca dosya/hedef adları farklıdır.
- **Kapsam kuralı:** Hiçbir kod değiştirilmedi. Tek yeni dosya bu rapor.
- **Ortam:** macOS (Darwin 27.2), Xcode 27.2 (27B52), iPhone 14 simülatörü (iOS 27.2), OrbStack (Docker 29.8.2),
  Supabase CLI 2.120.0.

---

## 1. Özet tablo

| Adım | Durum | Gerekçe |
|---|---|---|
| P001 | Geçti | Tüm araçlar sürüm verdi; `docs/KURULUM.md` var; depoda ve geçmişte anahtar yok. Hesapların içi (Apple, OpenRouter, DeepSeek, Google, TelemetryDeck) doğrulanamadı. |
| P002 | Geçti | Dizinler, README'ler, `.gitignore`/`.editorconfig`/`.swiftlint.yml`/`.swiftformat` var; `git status` temiz. |
| P003 | Geçti | `xcodegen generate` + `build-for-testing` başarılı, `LaunchTests` simülatörde açılışı doğruladı; `.xcodeproj` izlenmiyor. Swift 6 + `complete` + uyarı=hata açık. |
| P004 | Geçti | Dört paketin `swift test`'i geçti (StrengthKit 13, DataKit 63 + 1 koşullu, DesignSystem 15, CoachKit 1); uygulama paketleri import edip derleniyor. |
| P005 | Doğrulanamadı | Tüm bileşenler, belirteçler, WCAG kontrast testi ve her bileşende açık/koyu/büyük yazı `#Preview` var; kabulün görsel kısmı (galeri, 0→73 animasyonun akıcılığı) gözle bakılmadı. |
| P006 | Geçti | AppContainer, 4 durumlu kök akış, 5 sekme + tipli rota, 9 özellik klasörü, FeatureFlags, 6 kategorili Logger; durum makinesi testleri geçti. |
| P007 | Kısmen | Katalog + TR tam, birim testleri (100 kg → 220,5 lb) geçti; ama dil değişince gezinme başlıkları değişmiyor ve Apple düğmesi sistem dilinde kalıyor (kabul "tüm metinler değişiyor" tam karşılanmıyor). |
| P008 | Geçti | `actionlint` temiz; son iOS (a819bdb) ve Core (20a3b81) koşuları yeşil; eylemler SHA ile sabit. Küçük: lint `--strict` değil, `Package.resolved` gitignore'da. |
| P009 | Kısmen | Yerel yığın çalışıyor, KURULUM akışı yazılı, staging/prod projeleri var; ama **iki uzak projeye de hiç göç uygulanmamış** ve "bağlı" durumu yerelde kanıtlanamadı. |
| P010 | Geçti | 4 tablo, RLS + sahip politikaları, delete yok, boy 100–250 / yaş ≥ 16 / kilo 20–400 CHECK'leri, `(user_id, updated_at)` indeksleri; `db reset` temiz. |
| P011 | Geçti | Katalog tabloları, CHECK'ler, herkes-okur/servis-yazar RLS, unaccent + pg_trgm araması; aksan testleri geçiyor (`'sinav'` örneği birebir yok, eşdeğer `ş/ı/ğ` testleri var). |
| P012 | Geçti | 7 tablo, `numeric(6,2)` kg, tam-biri-dolu `exercise_ref`, CHECK aralıkları, indeksler, `purge_soft_deleted`; tam ağaç ekle/oku pgTAP testi geçiyor. |
| P013 | Geçti | 232 pgTAP testi geçti; kayıt + "RLS kapalı/politikasız tablo" denetimi var; CI `database` işi var; güvenlik danışmanı (yerel ve staging) bulgu vermedi. |
| P014 | Doğrulanamadı | Entitlement, URL şemaları, şifre politikası, TR/EN e-posta şablonları depoda; panelde sağlayıcıların etkin olduğu görülemedi, Apple tarafı ILERLEME'ye göre bilerek ertelendi. |
| P015 | Geçti | Sahte servisle durum testleri geçti; yerel Supabase'e karşı e-posta kayıt → doğrula → giriş → oturum geri yükle → çıkış testi bu denetimde **geçti**. |
| P016 | Kısmen | Ekranlar ve 4 auth UI testi var; `testEmailSignUpLeadsToVerificationScreen` iOS 27.2 simülatöründe iki kez üst üste **kaldı** (CI'daki eski çalışma zamanında geçiyor); Apple/Google ile gerçek giriş hiç denenmedi. |
| P017 | Geçti | SchemaV1 + MigrationPlan, ortak protokol, 4 model, `@ModelActor` depolar, bellek içi/app-group fabrikası, fixture'lar; depo testleri ve app-group açılış testi geçti. |
| P018 | Kısmen | 5 adım, ilerleme, geri, 16 yaş engeli (taslak silinir), "belirtmek istemiyorum", taslaktan devam testleri geçti; TR çalışma zamanı görünümü elle doğrulanmadı. |
| P019 | Kısmen | 5 soru, SelectableCard, UserProfile'a yazım, UI testi ile uçtan uca akış var; "10 adım < 2 dk" ölçülmedi. |
| P020 | Geçti | §4'e birebir: kutu yok, "Anonim olarak katkı sağla" / "Şimdi değil", "Neler paylaşılır?" §3.3 alanlarıyla; AI onayı onboarding'de yok; sürüm/geri alma testleri geçti. |
| P021 | **Kaldı** | Skor ekranı, geçici motor ve TODO(P032) yerinde; ama **onboarding bitti bilgisi hiçbir yere yazılmıyor** → uygulama yeniden açılınca kullanıcı onboarding'e baştan döner (ILERLEME'de "P021'de bağlanacak" denmişti). |
| P022 | Kısmen | Profil/ölçüm/grafik/ayarlar/hakkında ve iki aşamalı "SİL" akışı sahte servisle çalışıyor (beklenen); silmede yerel veri (SwiftData, taslak, set deposu) temizlenmiyor. |
| P023 | Kısmen | HealthService + sahte, yalnız düğmeyle izin, öneri/onay, içe aktarma + yineleme ayıklama testleri; "yeni kilo Sağlık'ta görünüyor" simülatörde gerçek HealthKit ile doğrulanmadı. |

---

## 2. Bulgular (önem sırasına göre)

### Kritik

**K1 · P021 (P015/P018 ertelemesi) — Onboarding'i bitiren kullanıcı yeniden açılışta onboarding'e baştan düşüyor**
- Dosyalar: `ios/App/Sources/Core/AppRootModel.swift:44-49`, `ios/Packages/DataKit/Sources/DataKit/Auth/SupabaseAuthService.swift:181`,
  `ios/App/Sources/Onboarding/OnboardingViewModel.swift:352`
- Beklenen: Onboarding tamamlanınca bu bilgi kalıcı bir kaynağa (profil + onay kayıtları veya `user_metadata.onboarding_complete`)
  yazılmalı; kök akış açılışta `ready` durumuna gelmeli. ILERLEME P018 notu: "Gerçek `onboardingComplete` kaynağı P021'de bağlanacak."
- Bulunan: `didCompleteOnboarding()` yalnızca bellekteki `state`'i `.ready` yapıyor. Tamamlanma bilgisi yalnızca
  `user_metadata["onboarding_complete"]`'ten okunuyor ve depoda bu anahtarı **yazan hiçbir kod yok**. `finish()` taslağı da siliyor;
  dolayısıyla yeniden açılışta `restoreSession()` → `onboardingComplete == false` → `needsOnboarding` → onboarding 1. adımdan başlar.
- Kanıt:
  ```
  $ grep -rn "onboarding_complete\|onboardingComplete" App Packages/DataKit/Sources
  SupabaseAuthService.swift:181: if case .bool(let done)? = user.userMetadata["onboarding_complete"] { onboarding = done } else { onboarding = false }
  AppRootModel.swift:44:     func didCompleteOnboarding() { … state = .ready }      # kalıcı yazım yok
  OnboardingViewModel.swift:352: func finish() { store.clear(userId: userId) }
  ```
  ILERLEME.md:200 bunu kendisi de not ediyor ("uygulama yeniden açılınca onboarding yeniden başlar"), ama P021 kutusu işaretli.
- Etki: Gerçek her kullanıcı her soğuk açılışta onboarding'i tekrar görür; ikinci geçişte profil yeniden yazılır. UI testleri bunu
  yakalamaz çünkü `-uitest-onboarded` bayrağıyla doğrudan `ready` başlıyorlar.

### Önemli

**Ö1 · P009/P010–P012 — Staging ve prod veritabanlarında hiç göç yok**
- Beklenen: KURULUM.md göç akışı "yerelde yaz → db reset → staging'e push → prod'a push". P009 kabulü "staging projesi bağlı".
- Bulunan: Supabase MCP `list_migrations` her iki proje için boş döndü. Uzak şemada `profiles`, `consents` vb. yok.
  Staging bağlantısı (`supabase/.temp/project-ref`) bu çalışma ağacında yok; "bağlı" durumu doğrulanamadı.
- Kanıt: `list_migrations(yjcfdntilceqndkwiwdn) → {"migrations":[]}`, `list_migrations(wafbrnsfxrwknczgkjkh) → {"migrations":[]}`.
- Not: ILERLEME "Ertelenenler"de "PR birleşince `supabase db push`" olarak 3 kez yazılı; birleşmeler yapıldı ama push yapılmadı.

**Ö2 · P022 — Üretim derlemesinde de sahte hesap servisi; silmede yerel veri kalıyor**
- Dosyalar: `ios/App/Sources/Core/AppContainer.swift:33` (`accountService: any AccountService = FakeAccountService()`),
  `ios/App/Sources/Profile/AccountModel.swift:91-106`
- Beklenen (prompt): şimdilik sahte servis — **bu beklenen durum**. Ancak sahte servis `#if DEBUG` ile sınırlı değil, Release'te de
  "Hesabım silindi" deyip yalnızca çıkış yaptırıyor; yerel SwiftData satırları, `onboarding.draft.<uid>` ve `onboarding.sets.<uid>`
  silinmiyor (ILERLEME:203 de not ediyor).
- Risk: P045 gelmeden bir TestFlight/Release derlemesi çıkarsa, App Store 5.1.1(v) (gerçek hesap silme) ihlali ve kullanıcıya yanlış bilgi.
  Yayın kontrol listesine engel olarak eklenmeli; yerel temizlik şimdi yapılabilir.

**Ö3 · P007 — Uygulama içi dil değişince metinlerin bir kısmı değişmiyor**
- Beklenen (kabul): "Dil değişince tüm metinler değişiyor."
- Bulunan: ILERLEME:153 ve :173 — gezinme başlıkları yeniden yerelleşmiyor; Apple giriş düğmesi sistem dilini izliyor; ILERLEME:185
  "karşılama ekranı TR bölgede de İngilizce kaldı". Tüm UI testleri `-AppleLanguages (en)` ile koşuyor; TR çalışma zamanı hiçbir
  adımda (P016–P021) doğrulanmamış.
- Kanıt: `ios/Tests/UITests/*UITests.swift` içinde tek dil `(en)`; TR'de koşan test yok.

**Ö4 · P014/P016 — Apple ve Google ile giriş hiçbir ortamda etkin değil**
- `supabase/config.toml:335,353` — `[auth.external.apple] enabled = false`, `[auth.external.google] enabled = false` (yerel; yer tutucu).
  ILERLEME:167 — Apple Developer üyeliği ve sağlayıcı yapılandırması ertelendi. Uzak panel durumu doğrulanamadı.
- Kabul P014 "Üç sağlayıcı Supabase panelinde etkin" ve P016 "üç yöntemle giriş tamamlanıyor" bu haliyle karşılanmıyor.
- Ek: Google için `skip_nonce_check = true` (`supabase/config.toml:356`), ILERLEME:168'de "gerçek cihazda doğrulanınca kapat" notuyla.

**Ö5 · P016 — E-posta ile kayıt UI testi güncel simülatörde kalıyor**
- Dosya: `ios/Tests/UITests/AuthFlowUITests.swift:40` (şifre yazımı), `:119` (`XCTFail`)
- Beklenen: P016 kabulü "UI testleri geçiyor".
- Bulunan: iPhone 14 / iOS 27.2 simülatöründe test, kayıt ekranındaki şifre alanına yazamıyor; tam koşuda ve tek başına
  yeniden koşuda (2/2) aynı hata. Giriş ekranındaki şifre alanı (`testWrongPasswordShowsErrorMessage`) geçiyor; fark kayıt
  alanının yeni şifre (güçlü şifre önerisi) içerik türünde olması. CI (macos-26 koşucusu, iPhone 17) yeşil, ayrıca
  `-retry-tests-on-failure -test-iterations 2` ile koşuyor; yani sorun CI'da görünmüyor ama Xcode 27 / iOS 27 imajlarına geçince çıkacak.
- Kanıt:
  ```
  AuthFlowUITests.swift:119: error: -[GymAnalyzerUITests.AuthFlowUITests testEmailSignUpLeadsToVerificationScreen] : failed - Could not type into auth-password-field
  Executed 16 tests, with 1 failure (0 unexpected) in 466.673 seconds
  (tek başına yeniden koşu) Executed 1 test, with 1 failure (0 unexpected) in 72.721 seconds
  ```
- Kullanıcıya etkisi doğrulanmadı: aynı alanın gerçek kullanıcıda iOS 27'de güçlü şifre önerisiyle doğru çalışıp çalışmadığı elle denenmeli (§5).

### Küçük

- **k1 · P008** `.gitignore` `Package.resolved`'ı yok sayıyor; uygulama/paket bağımlılıkları (supabase-swift'in geçişli
  bağımlılıkları) sabitlenmiyor. `core.yml` önbellek anahtarı hiç var olmayan `Package.resolved`'ı hash'liyor.
- **k2 · P008/P017** SwiftLint: 65 uyarı, 0 hata (`--strict` çıkış kodu 2). Dağılım: identifier_name 47, line_length 7,
  sorted_imports 6, diğerleri 5. CI bilerek `--strict` değil (ILERLEME:154, :181).
- **k3 · P005** Bileşen galerisi ve `#Preview` demo metinleri (≈36 sabit Türkçe metin, ör.
  `ComponentGalleryView.swift:28 "0 → 73 animasyonunu oynat"`, `Buttons.swift:141`) katalog dışında. Yalnızca Debug galerisinde
  ve önizlemelerde görünüyor; `ComponentGalleryView` `#if DEBUG` ile sarılı değil (yalnızca Debug menüsünden erişiliyor).
- **k4 · P011** Kabulde istenen `search_exercises('sinav')` → "Şınav" testi birebir yok; aynı katlamayı `'sirt'`, `'gogus'`,
  `'genis tutus'` testleri (`supabase/tests/011_exercise_catalog.test.sql:77-79`) kanıtlıyor.
- **k5 · P010** `profiles_min_age_check` `CURRENT_DATE` kullanan bir CHECK; yalnızca yazma anında değerlendirilir (beklenen) ama
  değişmez (immutable) olmayan CHECK, ileride `pg_dump`/geri yükleme veya tarih kayması senaryolarında sürpriz yaratabilir.
- **k6 · P010** `consents` tablosunda `deleted_at` yok (yalnızca ekleme yapılan tablo için bilinçli görünüyor; MIMARI §3.1'deki
  "ortak sütunlar" ile farkı belgelenmemiş).
- **k7 · P018** 16 yaş altı engelinde kalıcı taslak siliniyor ama bellekteki taslakta ad duruyor
  (`OnboardingViewModel.swift:191-195`); "Tarihi değiştir" ile devam edilirse ad yeniden kaydedilir. Yorum "not even the name"
  diyor; davranış bununla tam örtüşmüyor.
- **k8 · Adlandırma (denetlenen commit)** Görünen ad `Vesania`, proje `GymAnalyzer`, HealthKit izin metinleri "GymAnalyzer" diyor.
  `origin/main`'deki PR #26 bunu `ATROX` olarak birleştirdi; ancak SwiftData mağaza dosyası adı da değişti
  (`Vesania.store` → `ATROX.store`), mevcut kurulumlarda yerel veri yeni mağazaya taşınmaz (henüz kullanıcı yok, risk düşük).
- **k9 · Ortam (depo dışı)** Yerel Supabase yığını silinmiş eski bir çalışma ağacından başlatılmıştı; Kong 8 saattir kapalıydı
  (`supabase_kong_gymanalyzer Exited (127)`). `supabase stop && supabase start` ile düzeldi.

Sorun bulunmayan adımlar: P002, P003, P004, P006, P010–P013, P015, P017, P020 — yukarıdaki küçük notlar dışında bulgu yok.

---

## 3. Çalıştırılan komutlar ve sonuçlar

| Komut | Sonuç |
|---|---|
| `xcodebuild -version`, `xcodegen/swiftlint/swiftformat/supabase/deno/uv --version` | Geçti — Xcode 27.2, XcodeGen 2.46.0, SwiftLint 0.65.1, SwiftFormat 0.64.6, Supabase 2.120.0, Deno 2.9.8, uv 0.12.24 |
| `git ls-files \| grep xcodeproj/.env/Secrets.xcconfig` | Hiçbiri izlenmiyor; `ios/*.xcodeproj` `.gitignore:7` ile yok sayılıyor |
| `actionlint .github/workflows/*.yml` | Geçti (çıktı yok, çıkış 0) |
| `swiftlint lint` | Geçti — 65 uyarı, 0 hata; `--strict` → çıkış 2 |
| `swift test` StrengthKit | Geçti — 13 test / 2 suite |
| `swift test` CoachKit | Geçti — 1 test / 1 suite |
| `swift test` DesignSystem | Geçti — 15 test / 3 suite |
| `swift test` DataKit | Geçti — 63 test / 12 suite; 1 suite koşullu atlandı (`LocalSupabaseIntegrationTests`, env yoksa) |
| `swift test --filter LocalSupabaseIntegrationTests` (yerel Supabase env ile) | Geçti — 1/1 (`emailSignUpConfirmSignInRestoreSignOut`) |
| `supabase start` | Geçti (Kong için yığın yeniden başlatıldı, bkz. k9) |
| `supabase db reset` | Geçti — 3 göç uygulandı |
| `supabase test db` | Geçti — 6 dosya, 232 test, PASS |
| `supabase db advisors --local --type security --fail-on warn` | Geçti — "No issues found" |
| Supabase MCP `get_advisors(staging, security)` | Bulgu yok (şema boş olduğu için anlamı sınırlı) |
| Supabase MCP `list_migrations(staging/prod)` | Her ikisi boş (Ö1) |
| `psql`: public tablolarda RLS + politika sayısı | 15/15 tabloda RLS açık, hepsinde ≥ 1 politika; sahip tablolarında delete politikası yok |
| `psql`: CHECK ve indeksler | yaş ≥ 16, boy 100–250, kilo 20–400, set aralıkları ve 12 sahip tablosunda `(user_id, updated_at)` indeksi mevcut |
| `cd ios && xcodegen generate` | Geçti |
| `xcodebuild build-for-testing` (iPhone 14, iOS 27.2) | Geçti — `** TEST BUILD SUCCEEDED **` |
| `xcodebuild test-without-building -only-testing:GymAnalyzerTests -parallel-testing-enabled NO` | Geçti — 151 test / 25 suite, `** TEST EXECUTE SUCCEEDED **` |
| `xcodebuild test-without-building -only-testing:GymAnalyzerUITests -parallel-testing-enabled NO` | İlk deneme: çalıştırıcı hiç başlamadı (`Timed out waiting for AX loaded notification`, ortam). İkinci deneme: **Kaldı** — 16 testten 15 geçti, 1 kaldı (`AuthFlowUITests.testEmailSignUpLeadsToVerificationScreen`, Ö5). Auth 3/4, Launch 1/1, Onboarding 4/4, Profile 7/7 |
| Aynı UI testini tek başına yeniden koşma | Kaldı — 1/1 başarısız, aynı hata |
| GitHub Actions (`gh run list`) | iOS `a819bdb` (PR #25): SwiftLint ✓, Build & test ✓; Core `20a3b81` (main): ✓. P022/P023 birleşmelerinde iOS kırmızıydı, PR #25 düzeltti |
| Gizli anahtar taraması (ağaç + `git log --all -p`) | Bulgu yok: `.env`, `Secrets.xcconfig`, `.p8/.pem`, JWT/`sb_secret_`/`sk-or-`/Google API anahtarı ne ağaçta ne geçmişte |
| `ObservableObject/Combine/@Published/@StateObject` taraması | Bulgu yok |
| Test gövdesi taraması (41 test dosyası) | Boş veya assert'siz test yok; tek koşullu test `LocalSupabaseIntegrationTests` (bilinçli) |
| String Catalog analizi (4 katalog, 327 anahtar) | TR çevirisi eksik anahtar 0, `needs_review` 0, `stale` 0 |

**Test sayıları (toplam):** paketler 92 (+1 koşullu, ayrıca koşturulup geçti) · uygulama birim 151 · UI 16 (15 geçti, 1 kaldı) · pgTAP 232. Genel: 492 testten 491 geçti, 1 kaldı.

---

## 4. Çapraz denetimler

| Konu | Sonuç | Kanıt |
|---|---|---|
| Swift 6 dil modu | Açık | `ios/project.yml` `SWIFT_VERSION: "6.0"`; paketlerde `.swiftLanguageMode(.v6)` |
| `SWIFT_STRICT_CONCURRENCY=complete` | Açık | `ios/project.yml` settings.base; uyarı=hata da açık |
| Minimum iOS 26 | Evet | `deploymentTarget iOS "26.0"`, `IPHONEOS_DEPLOYMENT_TARGET 26.0`, paketler `.iOS(.v26)` |
| `.xcodeproj` commit edilmiş mi | Hayır | `git ls-files` boş; geçmişte de eklenmemiş |
| ObservableObject / Combine | Yok | grep boş |
| Gizli anahtar | Yok | §3 |
| RLS + politika | 15/15 | §3 |
| Her kullanıcı tablosunun pgTAP testi | Var | `tests.owner_tables()` 12 tablo + `001_rls_audit` kayıt dışı tabloda başarısız oluyor; `020_rls_matrix` sahip/yabancı/anonim/sahte user_id matrisi |
| Yaş/boy/kilo CHECK | Var | §3 |
| `(user_id, updated_at)` indeksleri | 12/12 sahip tablosu | §3 |
| Yerelleştirme | Uygulama kodunda katalog dışı metin yok; yalnızca Debug galerisi/önizleme (k3). `Text(verbatim:)` kullanımları sayı/birim/ad/e-posta gibi çevrilmeyecek değerler | §3 |
| Onay ekranı §4 | Uyumlu | `OnboardingConsentSteps.swift`: `Toggle` yok; `PrimaryButton("onboarding.contribution.accept")`, `"…skip"`, `DisclosureGroup` "Neler paylaşılır?"; `ConsentService.swift:23` AI onayı P081'e bırakılmış |
| 16 yaş altı engeli | Çalışıyor (birim testi) | `underSixteenIsBlockedAndNothingIsKept`, `blockedScreenGoesBackToTheDateAndAllowsACorrection`; küçük not k7 |
| Yarıda bırakıp devam | Çalışıyor (birim testi), ama bitirdikten sonra yeniden başlıyor (K1) | `resumesFromTheSavedDraft`, `draftsOfDifferentUsersDoNotMix` |
| "Belirtmek istemiyorum" | Var | `OnboardingSteps.swift:110` `.unspecified`; DB `sex in (male,female,unspecified)` |
| Birimler | Yalnızca kg/cm yazılıyor | Onboarding tekerleri `WeightUnit.pounds.kilograms(from:)` / `LengthFormat.centimeters(feet:inches:)`; ölçüm ekleme `WeightFormat.kilograms(from:unit:)`; set kartı `weightUnit.kilograms(from:)`; HealthKit `HKUnit` kg; modeller `heightCm`/`weightKg` |
| Geçici ScoreEngine | Açıkça işaretli | `PlaceholderScoreEngine.swift:3` "TEMPORARY … NOT calibrated … delete this file then" |
| TODO(P032) | Yerinde | `OnboardingLifts.swift:42` (depodaki tek TODO) |
| P022 sahte servis | Beklendiği gibi | `AccountService.swift` `FakeAccountService`; Ö2'ye bakın |
| ILERLEME tutarlılığı | P021 işaretli ama kendi notu (satır 200) adımın temel bir parçasının eksik kaldığını söylüyor; P009/P014/P016 kabulleri tam değil ama işaretli | K1, Ö1, Ö4 |

---

## 5. Elle doğrulaman gerekenler

1. **Galeri ve ScoreRing (P005):** Debug derlemesinde Profil → Debug menüsü → Bileşen Galerisi'ni aç, 0→73 düğmesine bas ve animasyonun takılmadığını gör.
2. **TR çalışma zamanı (P007, P016–P021):** Ayarlar'dan dili Türkçe yap, karşılama ekranından sonuç ekranına kadar ilerle; her ekranda ve sekme başlıklarında İngilizce metin kalmadığını kontrol et.
3. **Apple/Google sağlayıcıları (P014):** Supabase panelinde staging ve prod için Authentication → Providers'ta Apple, Google ve Email'in "Enabled" olduğunu gör.
4. **Üç yöntemle giriş (P016):** Gerçek cihazda staging derlemesiyle Apple, Google ve e-posta ile ayrı ayrı giriş yap.
5. **Staging bağlantısı (P009):** Ana depoda `supabase projects list` çalıştırıp staging satırında bağlı işaretini gör.
6. **10 adım < 2 dk (P019):** Onboarding'i kronometreyle baştan sona doldur.
7. **HealthKit (P023):** Simülatörde Sağlık uygulamasına bir kilo ve boy gir, onboarding'de "Apple Sağlık'tan doldur"a bas; sonra Profil → Kilo'dan yeni ölçüm ekleyip Sağlık uygulamasında göründüğünü kontrol et.
8. **Hesaplar (P001):** Apple Developer Team ID, OpenRouter limiti, DeepSeek, Google Cloud ve TelemetryDeck kayıtlarının şifre yöneticinde olduğunu kontrol et.
9. **Kayıt şifre alanı iOS 27'de (P016, Ö5):** iOS 27 simülatörde veya cihazda e-posta ile kayıt ekranında şifre alanına elle yazıp (güçlü şifre önerisini de deneyerek) "Hesap oluştur"un etkinleştiğini kontrol et.
10. **XcodeBuildMCP (P001):** `claude mcp list` çıktısında XcodeBuildMCP'nin bağlı göründüğünü kontrol et (bu denetimde kontrol edilmedi).

---

## 6. Önerilen düzeltme sırası (her biri ayrı oturum için prompt taslağı)

### 1) K1 — Onboarding tamamlanma bilgisini kalıcı yap

```text
Onboarding'i bitiren kullanıcı uygulama yeniden açılınca onboarding'e baştan dönüyor (docs/DENETIM-P001-P023.md K1).
Kök akışın `onboardingComplete` bilgisini kalıcı bir kaynaktan okumasını sağla:
- Kaynak: yerel SwiftData'da kullanıcının UserProfile'ı + güncel terms onayı (ConsentService) varsa onboarding tamam say;
  ayrıca OnboardingViewModel.finish() sırasında Supabase `user_metadata.onboarding_complete = true` yaz (ağ yoksa sessizce atla,
  yerel kaynak belirleyici olsun).
- AppRootModel.restore() ve didSignIn() bu kaynağı kullansın; SupabaseAuthService yalnızca metadata'yı yedek olarak okusun.
- Birim testi: bitir → yeni AppRootModel ile restore → state == .ready. Profil var ama terms onayı yoksa → needsOnboarding.
- UI testi: onboarding'i bitir, uygulamayı terminate + launch et, sekmelerin açıldığını doğrula (-uitest-onboarded kullanmadan).
docs/ILERLEME.md "Ertelenenler"deki ilgili satırları güncelle. Tek commit: "Fix: persist onboarding completion".
```

### 2) Ö1 — Göçleri staging ve prod'a uygula `[MANUEL onaylı]`

```text
docs/KURULUM.md "Göç iş akışı"nı izleyerek P010–P012 göçlerini önce staging'e, doğrulamadan sonra prod'a uygula.
Her ortam için: supabase link --project-ref <REF> → supabase db push --dry-run (çıktıyı bana göster, onayımı bekle) → supabase db push.
Ardından Supabase MCP ile list_migrations (3 göç), list_tables (15 tablo) ve get_advisors(security) çalıştır ve raporla.
Kod değiştirme. docs/ILERLEME.md "Ertelenenler"deki üç "db push" satırını tamamlandı olarak güncelle.
```

### 3) Ö2 — Hesap silmede yerel temizlik ve sahte servisin Release'te kullanılmaması

```text
P022 hesap silme akışında (docs/DENETIM-P001-P023.md Ö2):
- Silme başarılı olunca yerel veriyi temizle: kullanıcının SwiftData satırları (profil, ölçümler, ayarlar, onaylar),
  OnboardingDraftStore ve OnboardingSetStore kayıtları. Bunu DataKit'te bir `LocalDataEraser` (protokol + @ModelActor) ile yap.
- AppContainer'da FakeAccountService'i yalnızca DEBUG ve UI testlerinde kullan; Release/Staging'de gerçek servis gelene kadar
  dışa aktar/sil düğmeleri "yakında" bilgisi göstersin ya da FeatureFlags ile gizlensin (hangisi olacağını önce bana sor).
- Birim testleri: silme sonrası depolar boş; başarısız silmede hiçbir şey silinmez.
docs/ILERLEME.md'ye "P045 gelmeden yayın yok" notunu yayın engeli olarak ekle.
```

### 4) Ö3 — Uygulama içi dil değişiminin tamamlanması ve TR UI testi

```text
Uygulama içi dil değişince tüm metinlerin değişmesini sağla (docs/DENETIM-P001-P023.md Ö3):
- Gezinme başlıkları ve sekme etiketleri `.environment(\.locale)` değişimine tepki versin (gerekirse kök görünüme `.id(locale)`).
- Karşılama ekranının sistem TR iken İngilizce kalma sebebini bul (AppLanguage.system → Locale çözümü) ve düzelt.
- Apple düğmesi sistem dilini izler (UIKit kısıtı); bunu docs/YERELLESTIRME.md'ye bilinen kısıt olarak yaz.
- XCUITest: `-AppleLanguages (tr) -AppleLocale tr_TR` ile karşılama → onboarding ilk 3 adım → Türkçe metin ve "SİL" kelimesi kontrolü;
  ayrıca Ayarlar'dan dil değiştirip sekme başlıklarının değiştiğini doğrula.
Testleri CI'a bırak; yerelde yalnızca ilgili test sınıfını tek simülatörde çalıştır.
```

### 5) Ö5 — E-posta kayıt UI testini iOS 27'de geçir

```text
ios/Tests/UITests/AuthFlowUITests.swift testEmailSignUpLeadsToVerificationScreen, iPhone 14 / iOS 27.2 simülatöründe
"Could not type into auth-password-field" ile kalıyor (docs/DENETIM-P001-P023.md Ö5); CI'da eski çalışma zamanında geçiyor.
Önce systematic-debugging ile kök nedeni bul: güçlü şifre önerisi katmanı mı (dismissStrongPasswordSuggestion), alanın
textContentType'ı mı, yoksa odak/klavye zamanlaması mı. Uygulama davranışı yanlışsa (kullanıcı da yazamıyorsa) EmailSignUpView'u düzelt;
yalnızca test yardımcısıysa onu sağlamlaştır. Yalnızca bu test sınıfını tek simülatörde, paralel olmadan çalıştır; 3 kez üst üste geçsin.
CI'da iOS 27 runtime'ı da deneyen bir matris satırı eklemeyi öner (eklemeden önce bana sor).
```

### 6) Ö4 — Apple ve Google sağlayıcılarını etkinleştir `[MANUEL]`

```text
docs/KURULUM.md "Kimlik sağlayıcıları (P014)" bölümünü benimle adım adım uygula: Apple Developer'da App ID'lere Sign in with Apple,
Supabase staging/prod'da Apple (Client IDs = 3 bundle ID) ve Google sağlayıcıları, Secrets.xcconfig'te Google iOS istemci kimlikleri.
Her adımdan sonra panelde "Enabled" durumunu bana doğrulat. Sonunda gerçek cihazda staging derlemesiyle Apple, Google ve e-posta
girişlerini dene; Google girişi çalışırsa "Skip nonce checks"i kapat ve tekrar dene. Sonucu docs/ILERLEME.md'ye yaz. Kod değiştirme.
```
