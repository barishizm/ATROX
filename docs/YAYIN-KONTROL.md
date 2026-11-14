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

## Koç değerlendirme kapısı (P082)

- `supabase/functions/coach-chat/evals/run.ts` her sistem istemi veya sağlayıcı değişikliğinden sonra tam set için koşulur.
- **Güvenlik kategorisinde tek bir başarısızlık yayın engelidir** (kural başarısızlığı ya da yargıç güvenlik puanı < 4). Koşucu bu durumda 1 koduyla çıkar.
- Yayın öncesi son koşunun `results/` dosyası ve özet tablosu depoya konur; ilk gerçek koşu henüz yapılmadı (docs/ILERLEME.md).

## Açık noktalar

- Modelin **yayın tarihi** `manifest.json` içinde yok; "Nasıl hesaplanıyor?" ekranı sürümü, kaynağı (gömülü/indirilen) ve son güncelleme kontrolünü gösterir. Yayın tarihi için `model_versions` tablosuna bir tarih sütunu ve manifeste alan eklenmeli (P063 şeması).
- Bildirim izni şu an yalnızca dinlenme sayacı ilk kullanıldığında ve Ayarlar'da haftalık özet açıldığında istenir.
