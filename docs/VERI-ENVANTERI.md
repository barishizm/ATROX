# ATROX — Veri envanteri (P101)

> **TASLAK — hukuki tavsiye değildir.** Bu belge kod ve şema okunarak hazırlandı; bir hukukçu tarafından incelenmeden
> yayımlanmamalı. Hukukçunun bakması gereken maddeler `docs/YAYIN-KONTROL.md` → "P101 — hukukçu incelemesi" bölümünde.
> Hukuki dayanak sütunu bir **öneridir**; nihai karar veri sorumlusunun ve hukukçunun.

Kaynaklar: `supabase/migrations/*`, `supabase/functions/*`, `ios/App/**`, `ios/Packages/DataKit/**`,
`docs/ANALITIK.md`, `docs/04-AI-KOC.md`. Son kod denetimi: P101 (bkz. §5).

## 1. Taraflar ve alıcılar

| Alıcı | Rol | Ne alır | Konum / aktarım |
|---|---|---|---|
| **Supabase** (Postgres, Auth, Edge Functions, Storage) | Veri işleyen | Hesap + tüm senkronize veri (§2) | Bölge proje kurulumunda seçilir; **yayın öncesi AB bölgesi önerilir**, seçilen bölge buraya yazılmalı `[MANUEL]`. AB dışıysa yurt dışı aktarım. |
| **DeepSeek** (resmi API, `deepseek-flash`) | Veri işleyen / bağımsız sağlayıcı (sözleşmeye bağlı) | Yalnızca AI Koç onayı varken: profil özeti, skorlar, antrenman geçmişi, koça yazılan mesajlar ve koç notları (§2, "Koç") | **Yurt dışı aktarım** — sağlayıcının sunucuları ve saklama/eğitim politikası doğrulanmalı `[HUKUKÇU]`. OpenRouter ve başka aracı **kullanılmıyor** (karar 2026-11-14, `docs/04-AI-KOC.md`). |
| **DeepSeek** (aynı API, yemek analizi) | Veri işleyen / bağımsız sağlayıcı | Yalnızca **yemek fotoğrafı analizi onayı** (`food_ai_sharing`) varken: kullanıcının analiz etmeyi seçtiği yemek fotoğrafı (küçültülmüş kopya) veya yazdığı yemek açıklaması, isteğe bağlı not ve uygulama dili | Koçla aynı yurt dışı aktarım koşulları `[HUKUKÇU]`. Fotoğraf ATROX sunucusunda **saklanmaz** (`food-analyze` yalnızca iletir); sağlayıcının saklama politikası doğrulanmalı. |
| **Open Food Facts** (açık veritabanı) | Bağımsız (açık veri projesi) | Barkod numarası veya ürün arama kelimeleri; cihazdan doğrudan HTTPS ile, genel `User-Agent` (hesap verisi yok) | Yapay zekâ onayı gerekmez; uygulama tarama ekranında bunu yazar. Hesapla ilişkilendirilmez. |
| **Apple** | Bağımsız veri sorumlusu (kendi rolleri için) | Sign in with Apple (e-posta/ad, isteğe bağlı gizli e-posta), StoreKit satın alma, HealthKit (yalnızca cihazda), App Store bildirimleri, çökme raporları (kullanıcı Apple'a izin verdiyse) | Apple politikası |
| **Google** (Google Sign-In) | Bağımsız veri sorumlusu | Google ile girişte kimlik doğrulama | Google politikası |
| **TelemetryDeck** | Veri işleyen | Anonim kullanım olayları (§2, "Analitik") | AB'de barındırır (sağlayıcı beyanı; doğrula `[HUKUKÇU]`) |
| **E-posta sağlayıcısı** (Supabase Auth SMTP) | Veri işleyen | E-posta adresi (doğrulama/sıfırlama) | Yayın öncesi seçilecek `[MANUEL]` |
| **Instagram** (Meta) | Kullanıcı eylemiyle | Yalnızca kullanıcı "Stories'te paylaş"a dokununca, kullanıcının oluşturduğu kart görseli | Veri ATROX'tan Meta'ya sunucu üzerinden **gitmez**; cihazdaki paylaşım köprüsü |

Reklam ağı, veri komisyoncusu, izleme (ATT) **yok**. `NSPrivacyTracking = false`.

## 2. Toplanan veri

Saklama sütunu: "hesap ömrü" = hesap silinene kadar (`delete-account` tüm satırları ve Auth kaydını siler).

### Hesap ve profil

| Veri | Amaç | Hukuki dayanak (öneri) | Saklama | Alıcı | Konum |
|---|---|---|---|---|---|
| E-posta, kimlik sağlayıcı (apple/google/email), kullanıcı kimliği (UUID) | Hesap, giriş, senkronizasyon | Sözleşmenin ifası (KVKK m.5/2-c; GDPR m.6/1-b) | Hesap ömrü | Supabase Auth | `auth.users` |
| Ad, soyad (isteğe bağlı) | Kişiselleştirme | Sözleşme | Hesap ömrü | Supabase | `profiles.first_name/last_name` |
| Doğum tarihi, cinsiyet (`male/female/unspecified`), boy | Güç Skoru hesabı (yaş/cinsiyet normu), 16+ denetimi | Sözleşme | Hesap ömrü | Supabase | `profiles` |
| Hedef, deneyim, haftalık sıklık, ekipman, sınırlamalar (`limitations text[]`), dil, birimler | Program/skor kişiselleştirme | Sözleşme | Hesap ömrü | Supabase | `profiles`, `user_settings` |
| Onay kayıtları (kullanım koşulları, gizlilik, AI paylaşımı, model katkısı: sürüm + verildi/geri alındı + zaman) | İspat ve rıza yönetimi | Hukuki yükümlülük / meşru menfaat | Hesap ömrü | Supabase | `consents` |

> `limitations` (sakatlık/kısıt etiketleri) sağlık verisi niteliğinde olabilir → **özel nitelikli** kabul edilmeli (§4).

### Antrenman ve beden verisi

| Veri | Amaç | Dayanak | Saklama | Alıcı |
|---|---|---|---|---|
| Vücut ağırlığı ölçümleri (`body_measurements`) | Skor (kilo normu), takip | **Açık rıza** önerisi (sağlık verisi sayılabilir) | Hesap ömrü | Supabase |
| Programlar, günler, hareketler, notlar (`routines*`, `notes`) | Uygulama işlevi | Sözleşme | Hesap ömrü | Supabase |
| Antrenmanlar, hareketler, setler (ağırlık/tekrar/RIR/süre), kişisel rekorlar | Takip, skor | Sözleşme (+ açık rıza, sağlık/egzersiz verisi sayılırsa) | Hesap ömrü | Supabase |
| Özel hareketler (`custom_exercises`) | Uygulama işlevi | Sözleşme | Hesap ömrü | Supabase |
| Skor özetleri ve görüşler (`score_snapshots`, `insights`) | Güç Skoru geçmişi, haftalık özet | Sözleşme | Hesap ömrü (FK cascade) | Supabase |
| Yerel kopya (SwiftData, app group) | Çevrimdışı çalışma, widget | — (cihazda) | Çıkışta/silmede temizlenir | Yok |

### Beslenme (yemek takibi)

| Veri | Amaç | Dayanak | Saklama | Alıcı |
|---|---|---|---|---|
| Yemek kayıtları (`food_entries`: zaman, öğün, ad, kalori, makrolar, porsiyon, kaynak, yiyecek listesi) | Günlük kalori/makro takibi, koç | **Açık rıza** önerisi (beslenme/sağlık verisi sayılabilir) | Hesap ömrü (yumuşak silme + gece temizliği) | Supabase |
| Günlük kayıtlar (`diary_logs`: su, aktivite, adım, not, oruç, hedef kilo) | Günlük takip ekranı | Sözleşme / açık rıza (not ve oruç sağlık verisi sayılabilir) | Hesap ömrü (yumuşak silme + gece temizliği) | Supabase |
| Günlük hedef (`nutrition_targets`: mod, kalori, makrolar, aktivite) | Hedefle karşılaştırma | Sözleşme / açık rıza | Hesap ömrü | Supabase |
| Analiz sayacı (`food_analyses`: zaman, tür) | Günlük hak (ücretsiz 3 / Pro 60) | Meşru menfaat | Hesap ömrü | Supabase (yalnızca servis rolü yazar) |
| Yemek fotoğrafı | Analiz | Açık rıza (`food_ai_sharing`) | **Sunucuda saklanmaz**; cihazda yalnızca küçük önizleme (`FoodEntry.thumbnail`, senkronize edilmez) | DeepSeek (yalnızca analiz anında) |

Koç yalnızca `get_nutrition_summary` ile günlük toplamları ve hedefi okur (yemek adları gitmez). Beslenme verisi dışa aktarmaya
(`export-data`) ve hesap silmeye (`delete-account`) dahildir (`USER_TABLES`). Hedef, 18 yaş altında açık içermez; tabanlar 1500 kcal (erkek) / 1200 kcal.

### Apple Sağlık (HealthKit) — yalnızca cihazda

Okunan: boy, kilo, doğum tarihi, biyolojik cinsiyet (profili doldurmak ve tartıları içe aktarmak için).
Yazılan: kilo, antrenmanlar. **HealthKit verisi sunucuya HealthKit kaynağı olarak gönderilmez**; kullanıcı onayladığında
profile/ölçüme kopyalanan değerler §2'deki profil/ölçüm verisi olarak senkronize olur. **Koça ham Apple Sağlık verisi
gitmez** (onay ekranında yazıyor). Reklam/veri komisyoncusuna kullanım yok (App Store 5.1.3).

### AI Koç (yalnızca "AI veri paylaşımı" onayı varken)

| Veri | Amaç | Dayanak | Saklama | Alıcı |
|---|---|---|---|---|
| Profil özeti (yaş, cinsiyet, kilo, hedef, deneyim, sıklık, ekipman), skorlar, antrenman geçmişi, rekorlar | Koç yanıtı/program önerisi | **Açık rıza** (`ai_sharing`, sürümlü) | İstek süresince DeepSeek'te (sağlayıcı saklaması `[HUKUKÇU]`) | Supabase Edge Function → DeepSeek |
| Koça yazılan mesajlar, koç yanıtları, öneri/araç çağrıları | Sohbet geçmişi | Açık rıza | Kullanıcı silene veya hesap silinene kadar (sert silme) | Supabase (`coach_threads/messages`); metin DeepSeek'e gider |
| Koç belleği notları (`coach_memory`) | Kişiselleştirilmiş yanıt | Açık rıza | Kullanıcı silene kadar | Supabase; DeepSeek'e gider |
| Kullanım kaydı: sağlayıcı, model, token, maliyet, gecikme, durum (`coach_usage`), kota (`coach_quota`) | Maliyet, kota, hata izleme, kötüye kullanım | Meşru menfaat | Hesap ömrü | Supabase; **mesaj içeriği içermez** |
| Haftalık/antrenman özeti (`coach_digests`) | Proaktif yorum | Açık rıza | Hesap ömrü | Supabase |

Gönderilmeyenler: ad, e-posta, hesap kimlikleri, ham Apple Sağlık verisi. Koç kapalıyken hiçbir şey gönderilmez.

### Sosyal (isteğe bağlı, varsayılan kapalı)

| Veri | Amaç | Dayanak | Saklama | Alıcı |
|---|---|---|---|---|
| Kullanıcı adı, görünen ad, avatar emoji/renk, "bulunabilir" ve "skoru paylaş" bayrakları, paylaşılan genel skor, haftalık antrenman sayısı, skor geçmişi (`public_profiles`, `social_score_history`) | Arkadaşlar, sıralama | Açık rıza (kullanıcı profil oluşturur ve seçer) | Sosyali kapatınca veya hesap silinince silinir | Supabase; **diğer kullanıcılar** seçilen alanları görür |
| Arkadaşlık/istek/engel kayıtları (`friendships`) | Sosyal işlev | Sözleşme | Silinince/hesap kapanınca cascade | Supabase; karşı taraf |
| Şikâyetler (`reports`: bildiren, bildirilen, neden, not) | Kullanıcı içeriği moderasyonu (App Store 1.2) | Meşru menfaat | **Süre belirlenmedi** `[HUKUKÇU]` | Supabase; ekip |
| Hız sınırı sayaçları (`social_rate_limits`) | Kötüye kullanım önleme | Meşru menfaat | Kısa ömürlü | Supabase |

Kilo ve kaldırışlar arkadaşlara **görünmez** (arayüz metni ve RLS).

### Anonim model katkısı (isteğe bağlı, `ml_contribution` onayı)

Ayda bir, onay açıkken: cinsiyet, 5 yıllık yaş aralığı, tam kg'a yuvarlı vücut ağırlığı, 5 cm'lik boy aralığı, deneyim ve
sıklık aralığı, ay, hareket başına en iyi tahmini 1TM / en iyi set tekrarı / o ayki antrenman sayısı, model sürümü,
**cihazda üretilen rastgele katkı anahtarı (hesapla eşlenmez, 12 ayda bir yenilenir)**.
`ml_contributions` tablosunda kullanıcı sütunu ve yabancı anahtar **yok**; istemci rolüne erişim kapalı; dışa aktarım
için k-anonimlik eşiği (k=20). Onay geri alınınca sunucudaki satırlar anahtarla silinir ve anahtar yok edilir
(`ContributionService.withdraw`; başarısızsa yeniden denenir). Dayanak: açık rıza. Anonimleştirme yeterliliği
(yeniden kimliklendirme riski) hukukçu tarafından değerlendirilmeli: **anonimse KVKK/GDPR kapsamı dışında**, değilse
özel nitelikli veri işlenmiş olur `[HUKUKÇU]`.

### Satın alma

| Veri | Amaç | Dayanak | Saklama | Alıcı |
|---|---|---|---|---|
| Abonelik durumu/ürün/bitiş/yenileme, orijinal işlem kimliği (`entitlements`) | Pro erişim | Sözleşme | Hesap ömrü | Supabase |
| App Store sunucu bildirimleri (`billing.app_store_events`), hesap eşleme jetonu (`billing.app_account_tokens`) | Aboneliği doğru hesaba bağlamak | Sözleşme / meşru menfaat | Hesap silinince kullanıcı bağı kopar (`on delete set null`); **olay satırları kalır — süre belirlenmedi** `[HUKUKÇU]` | Supabase |
| Ödeme bilgisi | — | — | **ATROX almaz**; Apple işler | Apple |

### Analitik ve tanılama (anonim, kapatılabilir)

- **TelemetryDeck olayları:** `docs/ANALITIK.md` sözlüğündeki kapalı küme (kayıt yöntemi, huni adımları, koç mesajı gönderildi,
  öneri uygulandı/reddedildi, paylaşım hedefi, referans grubu, ödeme duvarı kaynağı, deneme/abonelik planı). Kişisel veri, ağırlık,
  skor, mesaj içeriği yok. Ayarlar → Gizlilik → "Anonim kullanım istatistiklerini paylaş" (varsayılan **açık**).
- **SDK'nın kendi eklediği alanlar:** TelemetryDeck SDK varsayılan olarak uygulama sürümü, işletim sistemi sürümü, cihaz modeli,
  dil/bölge ve **cihaz tabanlı, tuzlanıp özetlenmiş (hash) bir kullanıcı tanıtıcısı** ekler. Bu bir **Device ID** sayılır
  (kişiyle ilişkilendirilmez, izleme için kullanılmaz). `PrivacyInfo.xcprivacy`'de bu yüzden `DeviceID` (bağlantısız, analitik) vardır.
  Saklama: sağlayıcı beyanına göre `[HUKUKÇU]`.
- **MetricKit:** çökme/takılma **sayıları** cihazda `OSLog`'a yazılır; sunucuya gönderilmez. Ayrıntılı çökme yığınları
  yalnızca kullanıcı Apple'a paylaşım izni verdiyse App Store Connect'te görünür (Apple'ın verisi).
- **Sunucu panoları:** `coach_usage` üzerinden toplu metrikler (mesaj içeriği yok).
- Analitik kapalıyken hiçbir olay gitmez; `TELEMETRYDECK_APP_ID` boşsa (yerel/UI testi) hiçbir yere gitmez.

### Cihazda kalan veri

| Veri | Yer | Not |
|---|---|---|
| Tercihler (tema, dil, birimler, plak seti, dinlenme süresi, analitik anahtarı, ilk-açılış kaydı) | `UserDefaults` | Gerekçe kodları: `CA92.1`, `1C8F.1` |
| Widget özeti (skor, bugünün günü, haftalık hedef/seri) | App group `UserDefaults` | Çıkışta temizlenir |
| Oturum belirteçleri | Keychain (Supabase SDK) | |
| Bildirim izni ve zamanlama (dinlenme sayacı, haftalık özet) | Yerel bildirimler | Sunucuya bildirim jetonu **gönderilmez** (uzaktan push yok) |
| Paylaşım kartı görseli | Bellekte üretilir | Yalnızca kullanıcı paylaş/kaydet derse sistem paylaşım sayfasına verilir |

Kamera ve fotoğraf seçici **yalnızca yemek fotoğrafı ve barkod için, kullanıcı dokununca** açılır (`NSCameraUsageDescription`; fotoğraf
seçici izin istemez). Konum, mikrofon, kişiler, fotoğraf kitaplığına toplu erişim, reklam tanıtıcısı (IDFA), cihaz parmak izi **kullanılmıyor**.

## 3. Haklar ve süreçler

| Hak | Uygulamada nerede | Durum |
|---|---|---|
| Erişim / taşınabilirlik | Ayarlar → Verilerimi dışa aktar (`export-data`: JSON, `USER_TABLES`) | Var |
| Silme | Ayarlar → Hesabımı sil (`delete-account`: tüm satırlar + Auth + Apple belirteç iptali) | Var |
| Rıza geri alma | Ayarlar → AI Koç, Gizlilik (katkı, analitik); onay geçmişi görünür | Var |
| Koç sohbetlerini silme | Ayarlar → AI Koç → konuşma geçmişini sil (sunucuda sert silme) | Var |
| Düzeltme | Profil/ölçüm düzenleme | Var |
| Şikâyet / başvuru kanalı | `/support` sayfası, e-posta | Sayfa hazır; **gerçek adres `[MANUEL]`** |
| 16 yaş altı | Doğum tarihi 16'dan küçükse hiçbir şey kaydedilmez; DB kısıtı `birth_date <= bugün − 16 yıl` | Var |

## 4. Özel nitelikli veri değerlendirmesi (KVKK m.6 / GDPR m.9)

Vücut ağırlığı, antrenman performansı, boy, doğum tarihi ve `limitations` etiketleri **sağlık verisi** sayılabilir.
Bu yüzden: (a) uygulama içi açık rıza ekranları (AI paylaşımı, model katkısı) vardır; (b) hesap açma sırasında
Kullanım Koşulları + Gizlilik onayı alınır; (c) KVKK aydınlatma metni özel nitelikli veriyi ve yurt dışı aktarımı
(DeepSeek, olası Supabase bölgesi) ayrıca belirtir. **Hesap açılışında sağlık verisinin Supabase'de işlenmesi için de
ayrı açık rıza gerekip gerekmediği hukukçu kararı** `[HUKUKÇU]` (taslak metin `docs/HUKUK-TASLAKLARI.md` §3'te).

## 5. Kod ↔ envanter tutarlılık denetimi (P101)

Yöntem: tüm tablolar (`create table`), Edge Function'lar, `Info.plist` izinleri, HealthKit türleri, bağımlılıklar ve
gerekçe gerektiren API kullanımları tarandı; her biri yukarıdaki tablolarla eşlendi.

| # | Bulgu | Sonuç |
|---|---|---|
| 1 | Envanterde olmayan toplanan veri aranırken: `limitations`, `coach_usage`, `billing.*`, `reports`, `social_rate_limits`, TelemetryDeck SDK'nın otomatik alanları | Hepsi §2'ye eklendi. |
| 2 | **TelemetryDeck hash'li cihaz tanıtıcısı gönderir**, ama `docs/ANALITIK.md` "cihaz tanıtıcısı gönderilmez" diyordu | `ANALITIK.md` düzeltildi; manifestte `DeviceID` var. Kullanıcıya gösterilen metin (`settings.analytics.footer`) "seninle ilişkilendirilmez" diyor ve doğru; yine de hukukçu bakmalı. |
| 3 | `onboarding.contribution.details.cadence` "silinmesini **isteriz**" derken kod (`ContributionService.withdraw`) ve ayar ekranı **siler** | Metin koda göre düzeltildi (EN/TR). |
| 4 | `delete-account`, `USER_TABLES` dışında kalan tabloları (`insights`, `score_snapshots`, `entitlements`, `coach_quota`, `friendships`, `reports`, `social_score_history`) FK `on delete cascade` ile siliyor | Doğrulandı: hepsi `auth.users` veya `public_profiles`'a cascade. `billing.app_store_events` **kalır** (`user_id` null olur) → saklama süresi belirlenmeli. |
| 5 | `export-data` sosyal kayıtları (başkalarının verisi) ve `ml_contributions`'ı (kimliksiz) içermiyor | Bilinçli; metinlerde belirtildi. |
| 6 | `reports` ve `billing.app_store_events` için saklama süresi yok | Açık madde → `YAYIN-KONTROL.md`. |
| 7 | OpenRouter: P101 istemi anıyor, ama kod/karar yalnızca DeepSeek | Envanter kodla uyumlu: yalnızca DeepSeek. |
| 8 | Coach Edge Function loglarında kişisel veri/anahtar | Bu adımda **taranmadı**; P102 (güvenlik incelemesi) kapsamında. |
| 9 | Üçüncü taraf SDK manifestleri | §6. |

## 6. Üçüncü taraf SDK manifest denetimi

| Paket | Sürüm | Manifest | Not |
|---|---|---|---|
| GoogleSignIn-iOS | 10.1.0 | Bağımlılıklarla (GTMAppAuth, GTMSessionFetcher, AppAuth, GoogleUtilities, swift-crypto…) manifest taşıyor | Yerel `SourcePackages` içinde manifestler görüldü. |
| supabase-swift | 2.55.6 | Manifest yok | Kaynakta `UserDefaults`/dosya zaman damgası/disk alanı/açılış zamanı API'si **bulunmadı** → bildirim gerekmiyor. |
| TelemetryDeck SwiftSDK | 2.14.2 | Yerelde çıkarılmamış | **`[MANUEL]`**: Xcode'da arşivle → *Generate Privacy Report* ile birleşik rapor al; TelemetryDeck manifestini doğrula. |

`tools/check_privacy_manifest.py` (CI'da) uygulamanın kendi manifestlerini denetler: izleme yok, veri türleri/amaçlar geçerli,
gerekçe gerektiren API kullanımı kodla eşleşiyor. Yeni bir gerekçeli API (ör. dosya zaman damgası) eklenirse CI kırılır.
