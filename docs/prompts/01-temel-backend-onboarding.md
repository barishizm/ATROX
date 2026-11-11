# Faz 0–2 · Temel, Backend, Onboarding (P001–P023)

---

## Faz 0 — Kurulum ve temeller

### P001 · Hesaplar ve araç zinciri `[MANUEL]`

```text
Bu projeyi Mac'imde geliştireceğim. Sırayla kontrol et, eksik olanı kurmamda bana adım adım yardım et, her birini
bir komutla doğrula:
- Xcode 27 ve iOS 26+ simülatörü (xcodebuild -version, xcrun simctl list)
- Homebrew ile: xcodegen, swiftlint, swiftformat, supabase (CLI), deno, uv
- Claude Code için XcodeBuildMCP (claude mcp add XcodeBuildMCP -- npx -y xcodebuildmcp@latest mcp) ve Supabase MCP
Ardından açmam gereken hesapları ve her birinden hangi bilgiyi saklamam gerektiğini listele:
Apple Developer Program (Team ID), Supabase (staging ve prod için iki proje), OpenRouter (API anahtarı + harcama
limiti), DeepSeek platformu (yedek API anahtarı), Google Cloud (iOS OAuth istemcisi), TelemetryDeck.
Hiçbir anahtarı depoya yazma; docs/KURULUM.md dosyasına yalnızca "hangi anahtar nerede saklanır" tablosunu yaz.
```

Kabul: Tüm araçlar sürüm çıktısı veriyor; `docs/KURULUM.md` var; depoda anahtar yok.

### P002 · Monorepo iskeleti

```text
CLAUDE.md'deki "Depo yapısı"nı oluştur: ios/, ml/, supabase/, tools/, docs/ dizinleri ve her birinde amacını
anlatan kısa README. Kök dizine .gitignore (Xcode, SwiftPM, Python, uv, Deno, Supabase yerel dosyaları, .env*,
*.xcodeproj, DerivedData, ml/data/raw, ml/runs), .editorconfig, .swiftlint.yml ve .swiftformat ekle.
README.md'yi proje özeti, hızlı başlangıç ve doküman bağlantılarıyla yeniden yaz.
docs/ILERLEME.md dosyasının mevcut olduğunu doğrula ve P001–P002'yi işaretle.
```

Kabul: Dizinler ve yapılandırma dosyaları var; `git status` temiz.

### P003 · XcodeGen projesi

```text
ios/project.yml oluştur (docs/02-MIMARI.md §2 ve §4):
- Uygulama hedefi "GymAnalyzer", iOS 26.0, Swift 6, SWIFT_STRICT_CONCURRENCY=complete, uyarılar hata sayılır.
- Bundle ID ve görünen ad tek bir xcconfig değişkeninden gelsin (çalışma adı; sonradan tek yerden değişecek).
- Üç yapılandırma: Debug, Staging, Release. Config/*.xcconfig dosyaları; gizli olmayan değerler commit edilir,
  Config/Secrets.xcconfig gitignore'da olur ve Secrets.example.xcconfig şablonu bulunur (SUPABASE_URL, SUPABASE_ANON_KEY).
- Birim test ve UI test hedefleri (Swift Testing + XCUITest).
- Yetenekler şimdilik boş; ileride eklenecekleri project.yml'de yorum olarak listele.
Minimal bir SwiftUI App + boş ContentView ekle. xcodegen generate çalıştır, simülatörde derleyip açıldığını doğrula.
```

Kabul: `xcodegen generate` + derleme + simülatörde açılış başarılı; `.xcodeproj` commit edilmemiş.

### P004 · Yerel Swift paketleri

```text
ios/Packages altında dört yerel paket oluştur ve project.yml'e bağla: StrengthKit, DataKit, DesignSystem, CoachKit
(sorumluluklar docs/02-MIMARI.md §2.1). Her pakette Swift 6 dil modu, katı eşzamanlılık, bir örnek public tip ve
Swift Testing ile bir örnek test olsun. StrengthKit yalnızca Foundation'a bağlı olmalı ve Linux'ta da derlenmeli;
Core ML kullanan kod ileride #if canImport(CoreML) arkasına girecek, bunu Package.swift'te not et.
DataKit'e supabase-swift bağımlılığını ekle (güncel kararlı sürümü belgelerden doğrula).
Her paket için swift test çalıştır.
```

Kabul: Dört paketin testleri geçiyor; uygulama paketleri import edip derleniyor.

### P005 · Tasarım sistemi

```text
DesignSystem paketini kur. Yön: koyu, atletik, veri odaklı (docs/00-KARARLAR.md karar 16).
- Renk belirteçleri: arka plan katmanları, metin düzeyleri, tek canlı vurgu rengi, skor için 6 seviyeli ölçek
  (Başlangıç→Elit), başarı/uyarı/hata. Koyu varsayılan; açık tema da tanımlı. Karşıtlık WCAG AA.
- Tipografi: SF Pro; büyük rakamlar için rounded/monospaced-digit stiller. Dynamic Type destekli.
- Boşluk, köşe yarıçapı, gölge belirteçleri. Liquid Glass'ı yalnızca gezinme/üst katman yüzeylerinde kullan.
- Bileşenler: PrimaryButton, SecondaryButton, Card, StatTile, ScoreRing (animasyonlu, 0–100), TagChip,
  SectionHeader, EmptyState, LoadingState, ErrorState. Haptics yardımcı tipi.
- Uygulamada yalnızca Debug'da görünen bir "Bileşen Galerisi" ekranı.
Her bileşen için #Preview (açık/koyu, büyük yazı tipi).
```

Kabul: Galeri simülatörde tüm bileşenleri gösteriyor; ScoreRing 0→73 animasyonu akıcı.

### P006 · Uygulama kabuğu

```text
Uygulama kabuğunu kur (docs/02-MIMARI.md §2.2):
- AppContainer: bağımlılıkları tutan ve Environment ile dağıtılan kompozisyon kökü; testte sahteleri takılabilir.
- Kök akış: oturum durumu (yükleniyor / girişsiz / onboarding eksik / hazır) → uygun görünüm.
- 5 sekme: Bugün, Antrenman, Analiz, Koç, Profil. Her sekmede NavigationStack ve tipli Route enum'ı.
- Özellik klasörleri: ios/App/Features/{Auth,Onboarding,Library,Workout,Analysis,Coach,Social,Profile,Paywall},
  her biri şimdilik yer tutucu ekranla.
- FeatureFlags tipi (yerel varsayılanlar; ileride uzaktan beslenecek).
- OSLog tabanlı Logger sarmalayıcısı; kategoriler: app, data, sync, score, coach, purchase.
Kök akışın durum geçişleri için birim testi yaz.
```

Kabul: Sekmeler arasında gezinilebiliyor; durum makinesi testleri geçiyor.

### P007 · Yerelleştirme ve birimler

```text
Yerelleştirme altyapısını kur:
- String Catalog (Localizable.xcstrings), kaynak dil İngilizce, Türkçe çeviri. Anahtar adlandırma kuralını
  docs/YERELLESTIRME.md'ye yaz (özellik.ekran.öğe).
- Mevcut tüm sabit metinleri kataloğa taşı. Çoğul kuralları için örnek ekle.
- Units modülü (DesignSystem veya StrengthKit dışında, uygulama katmanında): ağırlık (kg/lb) ve uzunluk (cm/ft-in)
  için Measurement tabanlı dönüştürme ve biçimlendirme; depolama her zaman kg/cm. Plaka adımına yuvarlama
  (2.5 kg / 5 lb) yardımcıları.
- Uygulama içi dil seçimi (sistem / TR / EN) için ayar altyapısı.
Dönüşüm ve yuvarlama için birim testleri; TR ve EN ekran görüntüsüyle doğrulama.
```

Kabul: Dil değişince tüm metinler değişiyor; 100 kg ↔ 220.5 lb testleri geçiyor.

### P008 · CI

```text
.github/workflows altında CI kur:
- ios.yml (macOS çalıştırıcı): xcodegen generate, SwiftLint, xcodebuild test (iPhone simülatörü), paket testleri.
- core.yml (ubuntu): StrengthKit için swift test; ml/ için uv + pytest (dizin boşsa atla); supabase/functions
  için deno test ve deno lint (dizin boşsa atla).
- Eşzamanlı çalışmaları iptal et, SwiftPM ve uv önbelleği kullan, yalnızca ilgili yollar değişince tetikle.
Secrets gerektiren adım olmasın; Secrets.xcconfig yoksa CI örnek dosyayı kopyalasın.
İş akışlarını yerelde act veya sözdizimi denetimiyle doğrula; kullanılan eylem sürümlerini sabitle.
```

Kabul: İş akışları sözdizimi denetiminden geçiyor; push sonrası iki iş de yeşil.

---

## Faz 1 — Backend temeli ve kimlik

### P009 · Supabase projesi ve yerel yığın

```text
supabase/ dizinini başlat (supabase init). config.toml'u ayarla: Auth'ta e-posta doğrulama açık, Apple ve Google
sağlayıcıları için yer tutucular, yerel portlar. supabase start ile yerel yığını ayağa kaldır ve doğrula.
docs/KURULUM.md'ye ekle: yerel yığını başlatma/sıfırlama, staging ve prod projelerine bağlanma (supabase link),
göç (migration) iş akışı (yerelde yaz → db reset ile dene → staging'e push → prod'a push).
Uzak projeleri benimle birlikte oluştur ve bağla; proje referanslarını KURULUM.md'ye yaz (anahtarları değil).
supabase/seed/ ve supabase/tests/ dizinlerini README ile oluştur.
```

Kabul: `supabase start` çalışıyor; staging projesi bağlı.

### P010 · Şema 1 — profil, ayarlar, onaylar, ölçümler

```text
İlk göçü yaz (docs/02-MIMARI.md §3.1): profiles, user_settings, consents, body_measurements.
- Ortak sütunlar: id uuid (istemci üretir), user_id uuid → auth.users (on delete cascade), created_at, updated_at,
  deleted_at. updated_at için tetikleyici fonksiyonu (set_updated_at) tek yerde tanımla.
- profiles: first_name, last_name (null olabilir), birth_date, sex ('male'|'female'|'unspecified'), height_cm,
  unit_system, experience, goal, weekly_frequency, equipment_access, limitations (text[]), locale.
  CHECK kısıtları: boy 100–250, yaş ≥ 16.
- consents: kind ('terms'|'privacy'|'ai_sharing'|'ml_contribution'), version, granted bool, created_at. Yalnızca
  ekleme yapılır; güncel durum en son satırdır.
- body_measurements: date, weight_kg (20–400), body_fat_pct, source.
- Her tabloda RLS: yalnızca sahibi select/insert/update edebilir; delete yok (yumuşak silme).
- (user_id, updated_at) indeksleri.
supabase db reset ile doğrula.
```

Kabul: Göç temiz uygulanıyor; RLS tüm tablolarda açık.

### P011 · Şema 2 — hareket kataloğu

```text
Katalog göçünü yaz: exercises, exercise_translations, catalog_versions, custom_exercises.
- exercises: id text (kararlı slug), equipment, mechanic, force, level, category, primary_muscles text[],
  secondary_muscles text[], movement_pattern, scoring_type, anchor_lift, load_convention, ratio, tau,
  ratio_confidence, bw_fraction, is_core bool, image_paths text[], created_at, updated_at.
  Enum benzeri alanlar için CHECK kısıtları (değerler docs/00-KARARLAR.md §5.4 ve docs/03-ML-MODEL.md §6).
- exercise_translations: exercise_id, locale, name, aliases text[], instructions text[]; (exercise_id, locale) tekil.
- catalog_versions: version int, published_at, checksum.
- custom_exercises: kullanıcıya özel, senkronize edilen, exercises ile aynı tanımlayıcı alanlar.
- RLS: exercises/translations/catalog_versions herkes okur, yalnızca servis rolü yazar; custom_exercises sahibine özel.
- Türkçe ve İngilizce için aksan duyarsız arama: unaccent + pg_trgm indeksleri ve search_exercises SQL fonksiyonu.
```

Kabul: Göç uygulanıyor; `search_exercises('sinav')` ileride "Şınav"ı bulacak biçimde test edilmiş.

### P012 · Şema 3 — program ve antrenman

```text
Antrenman göçünü yaz: routines, routine_days, routine_exercises, workouts, workout_exercises, sets, personal_records
(alanlar docs/02-MIMARI.md §2.3 ile bire bir eşleşsin).
- Tüm ağırlıklar kg, numeric(6,2). sets: weight_kg, reps, rpe, rir, set_type, is_completed, position.
- Her alt tabloda user_id tekrar edilsin (RLS'i basit ve hızlı tutar); üst kayda yabancı anahtar.
- exercise_ref: ya katalog id'si ya custom_exercises id'si (iki sütun + CHECK ile tam biri dolu).
- CHECK'ler: reps 0–100, weight 0–1000, rpe 1–10, rir 0–10.
- RLS sahibine özel. İndeksler: (user_id, updated_at), workouts(user_id, started_at desc),
  sets(workout_exercise_id, position).
- 90 günden eski yumuşak silinmiş kayıtları temizleyen fonksiyon (zamanlama sonraya).
```

Kabul: Göç uygulanıyor; örnek veriyle bir antrenmanın tam ağacı eklenip okunabiliyor.

### P013 · RLS test paketi

```text
supabase/tests altında pgTAP test paketi kur. Her kullanıcı tablosu için şunları doğrulayan testleri yaz:
(1) sahip kendi satırını okur/yazar, (2) başka kullanıcı okuyamaz/yazamaz, (3) anonim rol hiçbir şey okuyamaz,
(4) user_id başkasının kimliğiyle eklenemez, (5) katalog tabloları herkese açık okunur ama yazılamaz.
Testlerde iki sahte kullanıcı oluşturan yardımcı fonksiyonlar tanımla. Yeni tablo eklendiğinde test eklemeyi
zorunlu kılan bir denetim yaz: RLS'i kapalı veya politikasız public tablo varsa test başarısız olsun.
supabase test db çalıştır; CI core.yml'e ekle. Supabase güvenlik danışmanı çıktısını incele ve bulguları düzelt.
```

Kabul: Tüm RLS testleri geçiyor; "politikasız tablo" denetimi çalışıyor.

### P014 · Kimlik sağlayıcılarının yapılandırılması `[MANUEL]`

```text
Giriş sağlayıcılarını benimle birlikte yapılandır, her adımda neye tıklayacağımı söyle:
- Apple: App ID'de Sign in with Apple yeteneği; Supabase Auth'ta Apple sağlayıcısı (yerel id_token akışı için
  bundle ID'yi yetkili istemci olarak ekle).
- Google: Google Cloud'da iOS OAuth istemcisi; Supabase'te Google sağlayıcısı; ters istemci kimliğini URL şeması
  olarak project.yml'e ekle.
- E-posta: doğrulama zorunlu, şifre politikası, şifre sıfırlama ve doğrulama e-posta şablonları (TR/EN).
- Uygulama için derin bağlantı şeması ve Supabase yönlendirme URL'leri.
project.yml'e gerekli yetenekleri ve Info.plist anahtarlarını ekle. Her şeyi docs/KURULUM.md'de belgele.
```

Kabul: Üç sağlayıcı Supabase panelinde etkin; proje yeniden üretilip derleniyor.

### P015 · AuthService

```text
DataKit içinde kimlik katmanını yaz:
- SupabaseClient'ı xcconfig değerlerinden kuran fabrika.
- AuthService (actor veya @MainActor @Observable): signInWithApple (yerel ASAuthorization → id_token + nonce →
  signInWithIdToken), signInWithGoogle (GoogleSignIn SDK → id_token), signUp/signIn e-posta, şifre sıfırlama,
  signOut, oturum akışını dinleyen AsyncStream.
- Oturum Keychain'de kalıcı (SDK varsayılanını doğrula). Token yenileme hatasında temiz çıkış.
- Hata eşlemesi: ağ yok, geçersiz kimlik bilgisi, e-posta doğrulanmamış, iptal edildi → yerelleştirilmiş AuthError.
- Protokol + sahte uygulama; P006'daki kök akışı gerçek servise bağla.
Sahte servisle durum geçişlerini test et.
```

Kabul: Testler geçiyor; yerel Supabase'e e-posta ile kayıt olunup giriş yapılabiliyor.

### P016 · Giriş ekranları

```text
Auth özelliğinin arayüzünü yaz: karşılama ekranı (değer önerisi + üç giriş düğmesi; Apple düğmesi Apple'ın
tasarım kurallarına uygun ve en üstte), e-posta ile kayıt, e-posta ile giriş, doğrulama bekleniyor ekranı,
şifre sıfırlama. Yükleniyor/hata durumları, klavye yönetimi, şifre alanında güçlü şifre önerisi ve AutoFill
içerik türleri. Kullanım Koşulları ve Gizlilik Politikası bağlantıları (URL'ler yapılandırmadan).
Tüm metinler String Catalog'da (TR/EN). VoiceOver etiketleri eksiksiz.
XCUITest: e-posta ile kayıt → doğrulama ekranı; hatalı şifre → hata mesajı (yerel Supabase'e karşı veya sahte servisle).
```

Kabul: Simülatörde üç yöntemle giriş akışı tamamlanıyor; UI testleri geçiyor.

---

## Faz 2 — Onboarding ve profil

### P017 · Yerel veri katmanı (SwiftData)

```text
DataKit'te yerel veri temelini kur (docs/02-MIMARI.md §2.3):
- VersionedSchema (SchemaV1) + SchemaMigrationPlan iskeleti.
- Ortak alanlar için protokol (id, createdAt, updatedAt, deletedAt, syncState).
- Modeller: UserProfile, BodyMeasurement, UserSettings, ConsentRecord.
- ModelContainer fabrikası: üretim (uygulama grubu konteyneri — widget'lar için), bellek içi (test/önizleme).
- Depo protokolleri ve @ModelActor uygulamaları: ProfileRepository, MeasurementRepository, ConsentRepository.
  Her yazma updatedAt'i günceller ve syncState = pending yapar.
- Önizleme ve testler için örnek veri üreticileri (fixtures).
Depolar için birim testleri (bellek içi konteyner).
```

Kabul: Depo testleri geçiyor; uygulama grubu konteyneri simülatörde açılıyor.

### P018 · Onboarding 1 — kimlik ve vücut bilgileri

```text
Onboarding'in ilk bölümünü yaz. Adım başına tek soru, üstte ilerleme çubuğu, geri dönüş, ilerleme kaydedilir
(uygulama kapanırsa kaldığı yerden devam eder):
1. Ad (zorunlu), soyad (isteğe bağlı).
2. Doğum tarihi. 16 yaş altı için nazik bir engel ekranı; veri kaydedilmez.
3. Cinsiyet: Erkek / Kadın / Belirtmek istemiyorum. Altında neden sorduğumuzu açıklayan kısa metin: güç
   karşılaştırması aynı cinsiyetteki kişilerle yapılır; belirtilmezse karma referans kullanılır.
4. Birim sistemi (metrik/imperyal), cihaz bölgesinden varsayılan.
5. Boy ve kilo: tekerlek seçiciler, seçilen birimde; makul aralık doğrulaması.
"Apple Sağlık'tan doldur" düğmesi için yer bırak (P023'te bağlanacak).
OnboardingViewModel'in doğrulama ve gezinme mantığını test et.
```

Kabul: Akış TR/EN çalışıyor; 15 yaş girilince engelleniyor; yarıda kapatınca devam ediyor.

### P019 · Onboarding 2 — antrenman profili

```text
Onboarding'in ikinci bölümünü ekle:
6. Deneyim: hiç / 6 aydan az / 6 ay–2 yıl / 2–5 yıl / 5 yıl+ (her biri tek satır açıklamalı).
7. Ana hedef: kuvvet / kas kazanımı / yağ kaybı / genel sağlık.
8. Haftalık antrenman günü (1–7).
9. Ekipman erişimi: tam donanımlı salon / ev (barbell) / ev (dumbbell) / yalnızca vücut ağırlığı.
10. Kısıtlar: çoklu seçim (omuz, bel, diz, dirsek, bilek, kalça, yok) + serbest not.
Tümü UserProfile'a yazılır. Seçim kartları için DesignSystem'e SelectableCard bileşeni ekle.
Bu veriler hem skor güvenine (deneyim) hem koçun bağlamına girecek; alan adlarını docs/02-MIMARI.md ile hizala.
```

Kabul: 10 adım 2 dakikanın altında tamamlanıyor; veriler SwiftData'da.

### P020 · Onay ekranları

```text
Onay akışını docs/00-KARARLAR.md §4'e birebir uyarak yaz:
- Koşullar ve Gizlilik: bağlantılar + tek "Kabul ediyorum ve devam et" düğmesi; kabul ConsentRecord olarak
  sürümüyle kaydedilir.
- "Modeli birlikte geliştirelim" ekranı: önceden işaretli kutu KULLANMA. Üç güvence satırı, birincil düğme
  "Anonim olarak katkı sağla", ikincil bağlantı "Şimdi değil". Tam olarak hangi alanların gönderildiğini gösteren
  "Neler paylaşılır?" açılır bölümü (docs/02-MIMARI.md §3.3'teki alan listesi).
- AI veri paylaşımı onayı burada sorulmaz; koç ilk açıldığında sorulacak (P081).
ConsentService: güncel durumu, sürüm değişince yeniden sorma mantığını ve geri almayı yönetir.
Sürüm yükseltme ve geri alma senaryolarını test et.
```

Kabul: Her iki seçim de kaydediliyor; sürüm artınca yeniden soruluyor.

### P021 · Onboarding 3 — ilk güç profili

```text
Onboarding'in son bölümü: "Bildiğin en iyi setlerini gir, hemen skorunu gör".
- 4 temel hareket kartı: bench press, squat, deadlift, overhead press (kullanıcının ekipmanına göre dumbbell
  alternatifleri). Her biri için ağırlık + tekrar; "Bilmiyorum / yapmıyorum" ile atlanabilir.
- StrengthKit'e geçici bir ScoreEngine protokolü ve YER TUTUCU uygulama ekle (basit vücut ağırlığı oranı tabanlı,
  açıkça "geçici" işaretli). Gerçek model P061–P062'de bu protokolün arkasına takılacak.
- Sonuç ekranı: hareket başına ScoreRing, tek cümlelik yorum, "Bu ilk tahmin; antrenman kaydettikçe netleşir".
- Girilen setler "onboarding" kaynaklı tek bir antrenman olarak saklanacak (model P032'de gelecek; şimdilik
  geçici bir depoda tut ve TODO(P032) bırak).
Hepsini atlayan kullanıcı için boş durum.
```

Kabul: Girilen setlerle anında skor görünüyor; atlanınca akış bozulmuyor.

### P022 · Profil ve ayarlar

```text
Profil sekmesini yaz:
- Profil özeti ve düzenleme (onboarding alanlarının tümü).
- Vücut ölçümleri: kilo geçmişi listesi, yeni ölçüm ekleme, Swift Charts ile eğilim grafiği.
- Ayarlar: birim, dil, tema (sistem/koyu/açık), bildirimler (yer tutucu), gizlilik (katkı izni aç/kapat, onay geçmişi).
- Hesap: çıkış; "Verilerimi dışa aktar" ve "Hesabımı sil" (ikisi de P045 sonrası Edge Function'a bağlanacak;
  şimdilik onay akışları ve sahte servis).
- Hakkında: sürüm, model sürümü (yer tutucu), açık kaynak lisansları ve atıflar ekranı.
Hesap silme için iki aşamalı onay (açıklama + "SİL" yazarak doğrulama).
```

Kabul: Profil düzenlenebiliyor; kilo grafiği çiziliyor; silme akışı sahte servisle tamamlanıyor.

### P023 · HealthKit entegrasyonu

```text
HealthKit'i ekle (project.yml yeteneği + kullanım açıklamaları TR/EN):
- HealthService protokolü ve uygulaması: yetki iste (okuma: boy, kilo, doğum tarihi, biyolojik cinsiyet;
  yazma: kilo, antrenman). Yetki yalnızca kullanıcı ilgili düğmeye bastığında istenir.
- Onboarding'deki "Apple Sağlık'tan doldur" düğmesini bağla: mevcut değerleri öner, kullanıcı onaylar.
- Profildeki kilo ekranı: yeni ölçümü Sağlık'a yaz (izin varsa); Sağlık'taki daha yeni ölçümleri içe aktar
  (kaynak = healthkit, yinelenenleri ele).
- HealthKit yoksa veya reddedildiyse sessizce elle girişe düş.
Sahte HealthService ile içe aktarma ve yinelenen ayıklama mantığını test et.
HealthKit verisi LLM'e veya anonim katkıya ham haliyle gitmez; bunu docs/02-MIMARI.md §3.4'e not düş.
```

Kabul: Simülatörde örnek Sağlık verisi onboarding'e doluyor; yeni kilo Sağlık'ta görünüyor.
