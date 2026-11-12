# 02 — Mimari

## 1. Genel görünüm

```
┌────────────────────────── iPhone ──────────────────────────┐
│  SwiftUI Features  (Auth, Onboarding, Library, Workout,     │
│                     Analysis, Coach, Social, Profile, Paywall)│
│        │                    │                    │           │
│   DesignSystem          DataKit              CoachKit        │
│                    (SwiftData + Sync)      (SSE istemcisi)   │
│                         │                                    │
│                    StrengthKit  ◄── model paketi (Core ML +  │
│                  (skor motoru)       params.json, imzalı)    │
│   HealthKit · ActivityKit · WidgetKit · StoreKit 2           │
└───────────────┬───────────────────────────┬─────────────────┘
                │ PostgREST (RLS)           │ SSE
┌───────────────▼───────────────────────────▼─────────────────┐
│ Supabase:  Postgres · Auth · Storage · Edge Functions        │
│   coach-chat ─► OpenRouter (deepseek/deepseek-v4.1-flash)    │
│               └► DeepSeek resmi API (yedek)                  │
│   appstore-notifications · delete-account · contribute       │
└───────────────▲──────────────────────────────────────────────┘
                │ SQL dışa aktarma (anonim katkılar)
┌───────────────┴──────────────┐
│ ml/  Python eğitim hattı      │──► model paketi ──► Storage
└───────────────────────────────┘
```

## 2. iOS uygulaması

### 2.1 Modüller

| Paket | Sorumluluk | Bağımlılık |
|---|---|---|
| `StrengthKit` | 1RM tahmini, dağılım fonksiyonları, kalibrasyon, hareket oranları, birleştirme, gelişim analitiği, model paketi yükleme/doğrulama | Foundation, CoreML (koşullu) |
| `DataKit` | SwiftData modelleri, depolar (repository), senkronizasyon motoru, Supabase istemcisi | supabase-swift |
| `DesignSystem` | Renk/tipografi/boşluk belirteçleri, ortak bileşenler, haptik | SwiftUI |
| `CoachKit` | SSE istemcisi, mesaj/araç olayı modelleri, akış durum makinesi | Foundation |

Uygulama hedefi yalnızca özellikleri birleştirir. `StrengthKit` içindeki saf hesaplar Linux'ta da derlenir
(Core ML kullanan dosyalar `#if canImport(CoreML)` arkasında), böylece CI'da hızlı test edilir.

### 2.2 Durum yönetimi

- Görünüm modelleri `@Observable` ve `@MainActor`.
- Depolar `actor` veya `@ModelActor`; görünümler doğrudan `ModelContext` ile yazmaz.
- Bağımlılıklar tek bir `AppContainer` üzerinden `Environment` ile verilir; testlerde sahte uygulamalar takılır.
- Gezinme: 5 sekme (Bugün · Antrenman · Analiz · Koç · Profil), sekme başına `NavigationStack` + tipli rota enum'ı.

### 2.3 Yerel veri modeli (SwiftData)

Tüm modellerde ortak alanlar: `id: UUID`, `createdAt`, `updatedAt`, `deletedAt?`, `syncState` (`synced`/`pending`/`failed`).

| Model | Önemli alanlar |
|---|---|
| `UserProfile` | firstName, lastName?, birthDate, sex (`male`/`female`/`unspecified`), heightCm, unitSystem, experience, goal, weeklyFrequency, equipmentAccess, limitations |
| `BodyMeasurement` | date, weightKg, bodyFatPct?, source (`manual`/`healthkit`) |
| `Exercise` | catalogId, names (TR/EN), aliases, equipment, mechanic, force, primaryMuscles, secondaryMuscles, movementPattern, scoringType, anchorLift, loadConvention, ratio, ratioConfidence, isCustom |
| `Routine` → `RoutineDay` → `RoutineExercise` | sıra, hedef set sayısı, tekrar aralığı, hedef RIR, süperset grubu, dinlenme süresi |
| `Workout` → `WorkoutExercise` → `SetEntry` | startedAt, endedAt, notlar; set: weightKg, reps, rpe?, rir?, setType (`warmup`/`working`/`drop`/`failure`), isCompleted |
| `PersonalRecord` | exerciseId, kind (`weight`/`reps`/`e1rm`/`volume`), value, setId, date |
| `ScoreSnapshot` | scope (`exercise`/`muscle`/`overall`), key, referenceGroup, score, z, confidence, modelVersion, date |
| `CoachThread` / `CoachMessage` | sunucudaki konuşmanın yerel önbelleği |

Şema `VersionedSchema` + `SchemaMigrationPlan` ile sürümlenir (ilk günden).

### 2.4 Senkronizasyon (çevrimdışı öncelikli)

- **Doğruluk kaynağı cihazdır.** Her yazma önce SwiftData'ya gider ve kaydı `pending` işaretler.
- **Gönderme (push):** `pending` kayıtlar tablo bağımlılık sırasına göre toplu `upsert` edilir.
- **Çekme (pull):** Tablo başına `updated_at > son_imleç` sorgusu; imleç sunucu saatidir.
- **Çakışma:** Kayıt bazında son-yazan-kazanır (`updated_at`). Aktif antrenman cihazda kilitlidir; bitene kadar çekme onu ezmez.
- **Silme:** Yumuşak silme (`deleted_at`). 90 günden eski mezar taşları sunucuda zamanlanmış işle temizlenir.
- **Tetikleyiciler:** uygulama öne gelince, antrenman bitince, ağ geri gelince, 15 dakikada bir; üstel geri çekilme.
- **İlk giriş:** Tüm veriyi sayfalı çeker; ilerleme çubuğu gösterir.

Bu bölüm bilinçli olarak basit tutuldu: tek kullanıcı kendi verisini düzenler, eşzamanlı çok cihaz düzenlemesi nadirdir.

## 3. Backend (Supabase)

### 3.1 Tablolar

**Kullanıcı verisi (RLS: `user_id = auth.uid()`)**

`profiles` · `user_settings` · `consents` (tür, sürüm, verildi/geri alındı, zaman) · `body_measurements` ·
`custom_exercises` · `routines` · `routine_days` · `routine_exercises` · `workouts` · `workout_exercises` · `sets` ·
`personal_records` · `score_snapshots` · `coach_threads` · `coach_messages` · `coach_memory` · `coach_usage` ·
`entitlements` (yalnızca servis rolü yazar)

**Herkese açık okuma**

`exercises` · `exercise_translations` · `catalog_versions` · `model_versions`

**Sosyal**

`public_profiles` (kullanıcı adı, görünen ad, avatar, paylaşılan skor) · `friendships` (istek/kabul/engel) ·
`reports` · sıralama için `security definer` fonksiyonlar

**Anonim (kullanıcı kimliği YOK)**

`ml_contributions` — bkz. §3.3

Ortak sütunlar: `id uuid`, `user_id uuid`, `created_at`, `updated_at` (tetikleyici ile), `deleted_at`.
Senkronize edilen her tabloda `(user_id, updated_at)` indeksi bulunur.

### 3.2 Edge Functions

| Fonksiyon | Görev |
|---|---|
| `coach-chat` | Kimlik doğrula → kota/yetki → bağlam kur → LLM ajan döngüsü → SSE akışı → kullanım kaydı |
| `appstore-notifications` | App Store Server Notifications V2 imzasını doğrula → `entitlements` güncelle |
| `verify-purchase` | İstemciden gelen imzalı işlemi doğrula (ilk satın almada anında yetki) |
| `delete-account` | Kullanıcının tüm verisini ve Auth kaydını sil; Apple token'ını iptal et |
| `export-data` | Kullanıcının verisini JSON olarak üret |
| `contribute` | Anonim katkıyı doğrula ve kimliksiz yaz |
| `publish-score` | Sıralama skorunu makullük kontrolünden geçirip yaz |

### 3.3 Anonim katkı tasarımı

Cihaz, katkıya izin veren kullanıcı için ayda bir kez **özet** üretir ve `contribute` fonksiyonuna gönderir:

```
{ contribution_key,        // cihazda üretilen rastgele anahtar; user_id ile eşlenmez, 12 ayda bir değişir
  sex, age_band (5 yıllık), bodyweight_kg (tam sayıya yuvarlı), height_band (5 cm),
  experience_band, frequency_band,
  month (YYYY-MM),
  lifts: [{ exercise_id, best_e1rm_kg, best_set_reps, sessions_in_month }] }
```

- Fonksiyon JWT'yi yalnızca kötüye kullanım sınırlaması için kullanır; `user_id` tabloya yazılmaz, loglanmaz.
- Eğitim dışa aktarımında bir hücrede (cinsiyet × yaş bandı × kilo bandı × hareket) 20'den az katkı varsa o hücre dışarı verilmez.
- Kullanıcı izni geri alırsa cihaz `contribution_key` ile silme isteği gönderir.

### 3.4 Güvenlik

- Her tabloda RLS açık; politika yoksa erişim yoktur. Her politikanın pgTAP testi vardır.
- Servis rolü anahtarı yalnızca Edge Function ortamında.
- Edge Function'lar girdi şemasını doğrular (Zod), kullanıcı başına hız sınırı uygular.
- Model paketleri Ed25519 ile imzalanır; açık anahtar uygulamaya gömülüdür. İmza tutmazsa paket reddedilir ve gömülü model kullanılır.
- LLM'e giden veride ad, soyad, e-posta, kullanıcı kimliği bulunmaz.
- HealthKit verisi (boy, kilo, doğum tarihi, cinsiyet, Sağlık'taki kilo geçmişi) cihazda kalır: ham haliyle ne LLM'e (AI Koç bağlamı) ne de anonim katkıya (`contribute`) gider. Yalnızca kullanıcının onayıyla profile/ölçümlere kopyalanan değerler (kaynak = `healthkit`) o akışların normal kurallarına tabidir (LLM'de bantlama/yuvarlama, katkıda `bodyweight_kg` tam sayı ve `age_band`/`height_band`).
- İsteğe bağlı sertleştirme (P102): App Attest ile yalnızca gerçek uygulamadan gelen isteklerin kabulü.

## 4. Ortamlar

| Ortam | Supabase | Uygulama yapılandırması | Amaç |
|---|---|---|---|
| Yerel | `supabase start` | Debug | Geliştirme ve testler |
| Staging | ayrı proje | Staging (TestFlight iç) | Gerçek cihaz testi, sandbox satın alma |
| Prod | ayrı proje | Release | Yayın |

Yapılandırma `.xcconfig` dosyalarından gelir; yalnızca `anon` anahtarı ve proje URL'si uygulamaya girer.

## 5. Gözlemlenebilirlik

- Uygulama: `OSLog` kategorileri, MetricKit, TelemetryDeck (kimliksiz olaylar).
- Sunucu: Edge Function logları, `coach_usage` tablosu (token, maliyet, sağlayıcı, gecikme), Supabase danışman raporları.
- ML: `model_versions` tablosunda her sürümün değerlendirme metrikleri ve model kartı bağlantısı.

## 6. Test stratejisi

| Katman | Araç | Kapsam |
|---|---|---|
| Skor motoru | Swift Testing | Altın vektör eşliği, sınır durumları, monotonluk özellik testleri |
| Veri/senkron | Swift Testing + sahte sunucu | Çakışma, çevrimdışı kuyruk, mezar taşları, geçişler |
| Arayüz | XCUITest | Giriş, onboarding, antrenman kaydı, satın alma (StoreKit test) |
| Veritabanı | pgTAP | RLS: sahip okur/yazar, yabancı okuyamaz |
| Edge Functions | `deno test` | Şema doğrulama, kota, sahte LLM ile ajan döngüsü |
| ML | pytest | Veri sözleşmeleri, metrik fonksiyonları, dışa aktarım eşliği |
| Koç kalitesi | Değerlendirme seti | Senaryo bazlı puanlama, güvenlik reddi, araç doğruluğu |
