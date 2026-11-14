# Yayın öncesi kontrol listesi

Yayına çıkmadan önce yapılması gereken incelemeler. Her adım bir önceki listeye ekleme yapar.

## Hukuk incelemesi — kullanıcıya gösterilen metinler

Aşağıdaki metinler hukuk/uyum gözünden okunmalı (TR + EN). Anahtarlar `ios/App/Resources/Localizable.xcstrings` içindedir.

| Konu | Anahtarlar | Neye bakılacak |
|---|---|---|
| "Nasıl hesaplanıyor?" ekranı (P071) | `how.*` | "Tahmindir", "sağlık ölçüsü değildir" ifadeleri yeterli mi; yüzdelik/güven iddiaları aşırı kesin mi; makine hareketi ve teknik varsayımı. |
| Sorumluluk reddi (P071) | `how.disclaimer` | Tıbbi tavsiye değildir ve yeni programdan önce sağlık değerlendirmesi uyarısı yerel mevzuata uygun mu. |
| Veri kaynakları ve atıflar (P071) | `how.sources.*`, `how.source.*` | OpenPowerlifting (veri kullanım koşulları ve atıf biçimi), free-exercise-db (Unlicense), react-native-body-highlighter (MIT, lisans metni Hakkında > Lisanslar'da). |
| Haftalık özet bildirimi (P070) | `weekly.notification.*`, `settings.weekly.*` | Bildirim izni metni; bildirimin pazarlama sayılıp sayılmadığı (içerik yalnızca kullanıcının kendi verisi, açma/kapama ayarı Ayarlar'da). |
| Haftalık özet "yeniden başlama" mesajı (P070) | `weekly.restart.*` | Suçlayıcı olmayan, tıbbi/psikolojik iddia içermeyen dil. |
| AI veri paylaşımı onay ekranı (P081) | `coach.consent.*` | App Store 5.1.2(i): hangi veri / kime (DeepSeek) / ne amaçla açık mı; "gönderilmeyenler" listesi doğru mu (ad, e-posta, kimlikler, ham Sağlık verisi); önceden işaretli kutu yok; reddetmek uygulamanın geri kalanını etkilemiyor. Sağlayıcı veya veri kapsamı değişirse `ConsentVersions.aiSharing` ve sunucu `COACH_AI_CONSENT_VERSION` birlikte artar. |
| Koç ayarları (P081) | `settings.coach.*`, `coach.memory.*` | Onayı geri alma ve konuşma/bellek silme metinlerinin "kalıcı silinir" iddiası sunucudaki gerçek davranışla (sert silme) uyumlu mu. |
| Proaktif yorumlar (P083) | `summary.coach.*`, `weekly.card.coach`, `settings.coach.proactive`, `settings.coach.footer` | Cihaz üstü yorum etiketi ("Cihazında yazıldı") doğru mu; yorumların tıbbi/diyet iddiası içermediği (istem `coach-digest-v1`, cihaz üstü filtre) incelendi mi. |
| Paylaşım kartı (P084) | `share.*` | "Tahmini skor" notu kartta okunur mu; vücut ağırlığı varsayılan kapalı mı; kart metinleri skor iddiasını abartmıyor mu; Instagram `source_application` Meta App ID ile değiştirildi mi. |
| Sosyal (P085/P086) | `social.*` | App Store kullanıcı içeriği kuralları: bildir + engelle + engellenenler listesi var; uygunsuz kelime listesi (`social_text_ok` + `SocialTextPolicy`) hukuk/moderasyonca genişletildi mi; "sosyal özelliği kapat" iddiası (profil ve arkadaşlıklar silinir) sunucu davranışıyla uyumlu mu; şikâyetleri kimin, ne sürede inceleyeceği (`reports` tablosu) belirlendi mi. |

## P101 — hukukçu incelemesi gerekli

Taslak belgeler: `docs/VERI-ENVANTERI.md`, `docs/HUKUK-TASLAKLARI.md`, `docs/APP-STORE-GIZLILIK.md`, `web/privacy`, `web/terms`, `web/support`.
**Hepsi taslaktır; yayından önce bir hukukçu bakmalıdır.** Aşağıdaki maddeler tek tek karara bağlanmalı:

| # | Karar / inceleme | Nerede |
|---|---|---|
| 1 | Veri sorumlusunun unvanı/adresi, MERSİS, VERBİS kaydı gerekip gerekmediği, iletişim e-postası | Tüm web sayfaları, HUKUK §6 |
| 2 | Vücut ağırlığı, performans, boy, doğum tarihi, `limitations` **özel nitelikli sağlık verisi** mi; hesap açılışında Supabase işlemesi için **ayrı açık rıza** gerekli mi (gerekirse `onboarding.terms.*` + `consents` türü eklenir) | VERI-ENVANTERI §4, HUKUK §3.4 |
| 3 | **DeepSeek'e yurt dışı aktarım:** KVKK m.9 (açık rıza yeterli mi, taahhütname/standart sözleşme), GDPR aktarım aracı, DeepSeek'in saklama ve model eğitimi koşulları, veri işleme sözleşmesi | `coach.consent.*`, privacy §3/§7 |
| 4 | Supabase bölgesi seçimi (AB önerilir) ve aktarım güvenceleri; TelemetryDeck saklama süresi | privacy §6/§7 |
| 5 | Anonim model katkısı **gerçekten anonim mi** (aralıklar + rastgele anahtar + k=20); anonimse KVKK/GDPR dışında kalır, değilse özel nitelikli veri işlenir | `onboarding.contribution.*`, schema 21 |
| 6 | Saklama süreleri: `reports`, `billing.app_store_events`, yedekler; politika ve silme işlerinin (cron) tanımlanması | VERI-ENVANTERI §5 #6 |
| 7 | Rıza metinleri ekran metinleriyle birebir mi; "önceden işaretli kutu yok"; ayrı rıza gerekir mi (sosyal profil) | HUKUK §2–§3 |
| 8 | Sağlık ve AI sorumluluk reddi; "hiçbir öneri onaysız uygulanmaz" ve "tıbbi/diyet/ilaç tavsiyesi vermez" iddialarının koç güvenlik setiyle uyumu | HUKUK §4, P082/P102 |
| 9 | Kullanım Koşulları: sorumluluk sınırlaması, uygulanacak hukuk/yetkili mahkeme, tüketici cayma hakkı ve abonelik maddeleri (Mesafeli Sözleşmeler / Apple koşulları) | terms |
| 10 | 16 yaş koşulu ve beyana dayalı doğrulamanın yeterliliği; GDPR m.8 / COPPA | HUKUK §5 |
| 11 | App Store gizlilik etiketi: AI sağlayıcıya aktarımın "üçüncü taraf" beyanı, katkı verisinin bağlantısız ayrı beyanı, yaş derecelendirmesi | APP-STORE-GIZLILIK |
| 12 | Kullanıcı içeriği moderasyonu: şikâyet inceleme süresi ve sorumlusu (`reports`), uygunsuz kelime listesi | `social.*` (mevcut satır) |
| 13 | TelemetryDeck SDK gizlilik manifestinin doğrulanması: arşivde *Generate Privacy Report* `[MANUEL]` | VERI-ENVANTERI §6 |
| 14 | Alan adı kesinleşince `LEGAL_PRIVACY_URL`, `LEGAL_TERMS_URL`, `APP_LINK_HOST` ve web sayfalarındaki `[…]` alanları doldurulur `[MANUEL]` | xcconfig, web/ |

## Koç değerlendirme kapısı (P082)

- `supabase/functions/coach-chat/evals/run.ts` her sistem istemi veya sağlayıcı değişikliğinden sonra tam set için koşulur.
- **Güvenlik kategorisinde tek bir başarısızlık yayın engelidir** (kural başarısızlığı ya da yargıç güvenlik puanı < 4). Koşucu bu durumda 1 koduyla çıkar.
- Yayın öncesi son koşunun `results/` dosyası ve özet tablosu depoya konur; ilk gerçek koşu henüz yapılmadı (docs/ILERLEME.md).

## Açık noktalar

- Modelin **yayın tarihi** `manifest.json` içinde yok; "Nasıl hesaplanıyor?" ekranı sürümü, kaynağı (gömülü/indirilen) ve son güncelleme kontrolünü gösterir. Yayın tarihi için `model_versions` tablosuna bir tarih sütunu ve manifeste alan eklenmeli (P063 şeması).
- Bildirim izni şu an yalnızca dinlenme sayacı ilk kullanıldığında ve Ayarlar'da haftalık özet açıldığında istenir.
