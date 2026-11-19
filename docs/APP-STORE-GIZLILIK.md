# ATROX — App Store gizlilik etiketleri ve yaş derecelendirmesi (P101)

> **TASLAK — hukuki tavsiye değildir.** App Store Connect formu zaman zaman değişir; **doldururken güncel formu Apple'ın
> sitesinden oku** ve bu tabloyu ona göre düzelt. Kaynak: `docs/VERI-ENVANTERI.md`; manifest karşılığı `ios/App/Resources/PrivacyInfo.xcprivacy`.

## 1. Uygulama Gizliliği ("App Privacy") yanıtları

**İzleme (tracking):** Hayır. Veriler reklam/izleme için kullanılmıyor, veri komisyoncusuyla paylaşılmıyor. ATT istemi yok.
**Gizlilik politikası URL'si:** `LEGAL_PRIVACY_URL` (alan adı kesinleşince). **Hesap silme:** uygulama içinde var (Ayarlar → Hesabımı sil).

| App Store veri türü | Topluyor muyuz | Kullanıcıya bağlı | İzleme | Amaç | Kaynak (envanter) |
|---|---|---|---|---|---|
| İletişim → E-posta adresi | Evet | Evet | Hayır | Uygulama işlevselliği | Hesap |
| İletişim → Ad | Evet (isteğe bağlı ad/soyad) | Evet | Hayır | Uygulama işlevselliği | Profil |
| Sağlık ve Fitness → Sağlık | Evet (vücut ağırlığı, boy, doğum tarihi, cinsiyet, kısıt etiketleri) | Evet | Hayır | Uygulama işlevselliği | Profil/ölçüm; koç onayıyla AI sağlayıcıya |
| Sağlık ve Fitness → Fitness | Evet (antrenmanlar, setler, rekorlar, skorlar) | Evet | Hayır | Uygulama işlevselliği | Antrenman |
| Fotoğraf veya Videolar → Fotoğraflar veya Videolar | Evet (yalnızca kullanıcının analiz etmeyi seçtiği yemek fotoğrafı; sunucuda saklanmaz, analiz sağlayıcısına iletilir) | Evet | Hayır | Uygulama işlevselliği | Yemek analizi |
| Sağlık ve Fitness → Fitness (yemek günlüğü, kalori/makro hedefi) | Evet | Evet | Hayır | Uygulama işlevselliği | Beslenme |
| Kullanıcı İçeriği → Diğer kullanıcı içeriği | Evet (notlar, koç mesajları, kullanıcı/görünen ad) | Evet | Hayır | Uygulama işlevselliği | Koç, sosyal |
| Tanımlayıcılar → Kullanıcı kimliği | Evet (hesap UUID'si) | Evet | Hayır | Uygulama işlevselliği | Hesap |
| Tanımlayıcılar → Cihaz kimliği | Evet (TelemetryDeck'in hash'li tanıtıcısı) | **Hayır** | Hayır | Analitik | Analitik |
| Satın Alımlar → Satın alma geçmişi | Evet (abonelik durumu) | Evet | Hayır | Uygulama işlevselliği | Satın alma |
| Kullanım Verisi → Ürün etkileşimi | Evet (anonim olaylar) | **Hayır** | Hayır | Analitik | Analitik |
| Tanılama → Çökme verisi | **Hayır** (yalnızca cihazda `OSLog`; Apple'ın kendi çökme raporları geliştirici verisi sayılmaz) | — | — | — | MetricKit |

Notlar:
- **Anonim model katkısı** (vücut ağırlığı/kaldırışlar, hesapla eşlenmeyen anahtar) sağlık/fitness verisidir ama bağlantısızdır;
  manifestte bu türler zaten **bağlı** olarak bildirildiği için ayrıca satır eklenmedi (tür başına tek giriş). Hukukçu "bağlantısız ayrı beyan"
  isterse etiket değişir `[HUKUKÇU]`.
- **AI sağlayıcıya aktarım** (DeepSeek) App Store etiketinde "üçüncü taraf ortakla paylaşım" olarak değerlendirilmeli; Apple
  tanımına göre hizmet sağlayıcı sayılıp sayılmadığı `[HUKUKÇU]`. 5.1.2(i): kişisel veriyi üçüncü taraf AI ile paylaşmadan önce
  açık izin gerekir — uygulama bunu `coach.consent.*` (koç) ve `food.consent.*` (yemek fotoğrafı/açıklaması) ile yapıyor.
- Manifest ↔ etiket tutarlılığı: etiket tablosundaki "Evet" satırları `PrivacyInfo.xcprivacy`'deki `NSPrivacyCollectedDataTypes` ile aynı olmalı
  (CI betiği yalnızca manifestin geçerliliğini denetler; **etiketle eşleşmeyi insan denetler** `[MANUEL]`).
- Sign in with Apple "gizli e-posta" kullanılırsa e-posta bir aktarma adresidir; yine e-posta toplanıyor sayılır.
- HealthKit: veri reklam/komisyonculuk için kullanılmıyor (5.1.3); iCloud'a HealthKit verisi yazılmıyor.

## 2. Yaş derecelendirme anketi (taslak yanıtlar)

| Soru grubu | Yanıt | Gerekçe |
|---|---|---|
| Şiddet, korku, cinsel içerik, küfür, uyuşturucu/alkol/tütün göndermesi, kumar, yarışma amaçlı kumar | Yok | Uygulama içeriği bunları içermez |
| **Tıbbi/tedavi bilgisi** | Yok | Tıbbi tavsiye/teşhis verilmiyor; sağlık uyarısı mevcut (koç güvenlik seti P082) |
| **Kullanıcı tarafından oluşturulan içerik / sosyal etkileşim** | Var — kullanıcı adı, görünen ad, avatar, arkadaşlık istekleri; serbest metin mesajlaşma **yok** | Bildir + engelle + engellenenler listesi mevcut (1.2) |
| Sınırsız web erişimi | Hayır | |
| **Yapay zekâ / sohbet botu** | Var — AI Koç; üretken yanıtlar | Güncel formda bu soru varsa "Evet"; güvenlik kuralları ve onaysız uygulama yok |
| Uygulama içi satın alma/abonelik | Evet | Pro aboneliği |
| Sağlık/Fitness verisi | Evet (HealthKit) | |
| Yaş kısıtı | **16+** (kendi koşulumuz; Apple derecelendirmesinden bağımsız) | `onboarding.terms.age` |

Beklenen sonuç: düşük (4+/9+/12+ aralığı; güncel formda 13+/16+/18+ kademeleri de varsa AI sohbet ve sosyal yanıtlarına göre 13+ veya 16+ çıkabilir, formu doldururken kontrol et; sosyal + AI ile 12+ olası). **Çıkan derecelendirme uygulamanın kendi 16+ koşuluyla
çelişmez** (derecelendirme yalnızca mağaza içeriği içindir); gerekirse "Yaş aralığı" için App Store'un özel yaş kısıtı seçeneği
değerlendirilir `[MANUEL]`. Nihai değer anket doldurulunca belli olur.

## 3. İnceleme notlarına girecekler (P103'e devir)

Demo hesabı ve koç onayı akışı, HealthKit kullanımı, hesap silme yeri, engelle/bildir yeri, "tıbbi iddia yok" — P103'te
`YAYIN-KONTROL.md` ile birlikte yazılır.
