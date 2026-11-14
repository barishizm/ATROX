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

## Açık noktalar

- Modelin **yayın tarihi** `manifest.json` içinde yok; "Nasıl hesaplanıyor?" ekranı sürümü, kaynağı (gömülü/indirilen) ve son güncelleme kontrolünü gösterir. Yayın tarihi için `model_versions` tablosuna bir tarih sütunu ve manifeste alan eklenmeli (P063 şeması).
- Bildirim izni şu an yalnızca dinlenme sayacı ilk kullanıldığında ve Ayarlar'da haftalık özet açıldığında istenir.
