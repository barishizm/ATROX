# ATROX — Hukuki metin taslakları (P101)

> **TASLAK — hukuki tavsiye değildir.** Hazırlayan bir hukukçu değil. Yayımlanmadan önce Türkiye (KVKK) ve hedef
> pazarlar (GDPR/AB, ABD eyalet yasaları, App Store gereklilikleri) açısından bir hukukçu tarafından incelenmeli.
> Köşeli parantezli `[…]` alanlar doldurulmalıdır. Metinler `docs/VERI-ENVANTERI.md` ile birebir tutarlıdır.

Bu belge: (1) belge haritası, (2) uygulama içi onay metinleri ile birebir eşleşme tablosu, (3) KVKK açık rıza metinleri,
(4) sağlık ve AI sorumluluk reddi, (5) 16+ koşulu. Gizlilik Politikası, Kullanım Koşulları, KVKK Aydınlatma Metni ve Destek
sayfası statik sitede yayımlanır: `web/privacy`, `web/terms`, `web/support` (TR + EN, aynı sayfada iki bölüm).

## 1. Belge haritası

| Belge | Nerede | Dil |
|---|---|---|
| Gizlilik Politikası + **KVKK Aydınlatma Metni** (TR bölümünde m.10) | `web/privacy/index.html` | TR/EN |
| Kullanım Koşulları (abonelik, sağlık/AI sorumluluk reddi, 16+, kullanıcı içeriği) | `web/terms/index.html` | TR/EN |
| Destek / başvuru kanalı (KVKK m.11 hakları, hesap silme, bildirme) | `web/support/index.html` | TR/EN |
| Veri envanteri | `docs/VERI-ENVANTERI.md` | TR |
| Uygulama içi onay ekranları | `Localizable.xcstrings` (`coach.consent.*`, `onboarding.contribution.*`, `onboarding.terms.*`) | TR/EN |

Uygulamadaki bağlantılar `LEGAL_TERMS_URL` / `LEGAL_PRIVACY_URL` (`ios/Config/*.xcconfig`) ile gelir; alan adı kesinleşince değiştirilir.

## 2. Uygulama ekranı ↔ metin eşleşmesi

Kural: **uygulamadaki onay ekranı neyi söylüyorsa politika da onu söyler; politika daha fazlasını kapsayabilir ama
ekrandakiyle çelişemez.** Bir ekran metni değişirse ilgili sürüm numarası artar (`ConsentVersions.aiSharing`, sunucu
`COACH_AI_CONSENT_VERSION`) ve bu tablo güncellenir.

| Ekran / anahtar | Söylediği | Politikadaki karşılığı |
|---|---|---|
| `coach.consent.sent.*` | Profil özeti, skorlar, antrenman geçmişi, koça yazılan mesajlar ve koç notları gönderilir | Privacy §"AI Koç" — aynı liste |
| `coach.consent.recipient.body` | ATROX sunucusu → DeepSeek; DeepSeek kendi politikasına göre işler | Privacy §"Alıcılar" + yurt dışı aktarım |
| `coach.consent.purpose.body` | Yalnızca yanıt/program önerisi; reklam yok | Privacy §"Amaçlar" |
| `coach.consent.notsent.body` | Ad, e-posta, hesap kimlikleri, ham Apple Sağlık verisi gönderilmez | Privacy §"AI Koç" |
| `coach.consent.withdraw` | Ayarlar > AI Koç'tan geri alınır; uygulamanın geri kalanı çalışır | Privacy §"Haklarınız" |
| `onboarding.contribution.*` | Aylık özet; yaş/boy aralığı, tam kg, cinsiyet, deneyim/sıklık aralığı, en iyi setler; rastgele anahtar; kapatınca silinir | Privacy §"Anonim model katkısı" |
| `settings.analytics.footer` | Sayım/eylem; ağırlık/skor/mesaj yok; seninle ilişkilendirilmez; çökme raporları anonim | Privacy §"Analitik" (cihaz özeti dahil) |
| `onboarding.terms.age` / `profile.edit.ageError` | 16 yaş ve üzeri | Terms §"Yaş" |
| `how.disclaimer` | Tıbbi tavsiye değil | Terms §"Sağlık uyarısı" |
| `paywall.terms.*` | Otomatik yenileme, Apple Hesabından tahsilat, 24 saat öncesi iptal | Terms §"Abonelik" |
| `social.form.footer`, `social.turnoff.body` | Kilo/kaldırış görünmez; kapatınca profil ve arkadaşlıklar silinir | Privacy §"Sosyal" |

## 3. KVKK açık rıza metinleri (taslak)

KVKK'da açık rıza: belirli bir konuya ilişkin, bilgilendirmeye dayalı ve özgür iradeyle açıklanan rıza; **önceden işaretli
kutu yok, hizmet rızaya şart koşulmaz** (koç ve katkı isteğe bağlı; uygulama onsuz çalışır). Rıza kaydı: `consents` tablosu
(tür, sürüm, verildi/geri alındı, zaman).

### 3.1 AI veri paylaşımı (`ai_sharing`) — sağlık verisi ve yurt dışı aktarım

> **TR.** Yapay zekâ koçunu kullanabilmem için, [VERİ SORUMLUSU] tarafından işlenen profil özetimin (yaş, cinsiyet, vücut
> ağırlığı, hedef, deneyim, haftalık sıklık, ekipman), Güç Skorlarımın, antrenman geçmişimin ve koça yazdığım
> mesajların ile koçun tuttuğu notların; yanıt üretmek ve program önermek amacıyla, ATROX sunucusu aracılığıyla yapay
> zekâ model sağlayıcısı **DeepSeek**'e **yurt dışına aktarılmasına** ve orada işlenmesine açık rızam vardır. Bu veriler
> sağlık verisi niteliği taşıyabilir. Adım, e-postam, hesap kimliklerim ve ham Apple Sağlık verilerim gönderilmez. Rızamı
> istediğim zaman Ayarlar > AI Koç'tan geri alabilirim; bu, uygulamanın geri kalanını etkilemez. Geri alma, geçmiş
> işlemlerin hukuka uygunluğunu etkilemez.
>
> **EN.** To use the AI coach, I give my explicit consent to [CONTROLLER] sending my profile summary (age, sex, body weight,
> goal, experience, weekly frequency, equipment), Strength Scores, workout history, the messages I write to the coach and
> the coach's notes about me — through ATROX's server to the AI model provider **DeepSeek**, which may be located outside my
> country — to be processed to answer me and suggest programs. This data may include health-related data. My name, email,
> account identifiers and raw Apple Health data are not sent. I can withdraw consent at any time in Settings > AI Coach;
> this does not affect the rest of the app or past processing.

Not: uygulamadaki ekran bu metnin **kısa, ekran boyutuna uygun** halidir (§2). Hukukçu onaylarsa uzun hali ekranda
"Ayrıntılar" bağlantısı olarak da gösterilebilir `[HUKUKÇU]`.

### 3.2 Anonim model katkısı (`ml_contribution`)

> **TR.** Güç modelinin geliştirilmesi için, ayda bir, yalnızca cihazımda üretilen rastgele bir anahtarla (hesabımla
> eşlenmeyen) gönderilen anonim özetin — cinsiyet, 5 yıllık yaş aralığı, tam kg'a yuvarlanmış vücut ağırlığı, 5 cm'lik boy
> aralığı, deneyim ve haftalık sıklık aralığı, ay ve hareket başına en iyi tahmini 1TM, en iyi set tekrarı ve antrenman
> sayısı — işlenmesine açık rızam vardır. Ad, e-posta veya kullanıcı kimliğim gönderilmez. Rızamı kapattığımda anahtarımla
> paylaşılan her şey silinir.
>
> **EN.** To improve the strength model, I give my explicit consent to a monthly anonymous summary being sent under a random
> key generated on my device (not linked to my account): sex, 5-year age range, body weight rounded to a whole kg, 5 cm
> height range, experience and weekly-frequency ranges, the month, and per exercise the best estimated 1RM, best-set reps and
> session count. My name, email and user ID are never sent. When I turn it off, everything shared under my key is deleted.

### 3.3 Sosyal özellikler

Kullanıcı profil oluşturup "bulunabilir" ve "skoru paylaş" anahtarlarını **kendisi açar** (varsayılan kapalı); bu eylem rıza
anlamına gelir. Kapatınca profil ve arkadaşlıklar silinir. Ayrı kutu gerekip gerekmediği `[HUKUKÇU]`.

### 3.4 Hesap açılışında sağlık verisi

Profil (doğum tarihi, cinsiyet, boy), ölçümler ve antrenmanlar hesapla birlikte Supabase'e senkronize olur. Bu veri sağlık
verisi sayılırsa açık rıza gerekir. Önerilen yaklaşım: Kullanım Koşulları/Gizlilik onay ekranına, **ayrı ve işaretlenmemiş**
bir onay satırı eklemek veya aydınlatma + sözleşme dayanağını yeterli bulmak. **Karar hukukçunun** `[HUKUKÇU]`; bu karara
göre `onboarding.terms.*` ekranı ve `consents` türleri güncellenir (ayrı ürün onayı gerekir, bu adımda değiştirilmedi).

## 4. Sağlık ve AI sorumluluk reddi (taslak)

Uygulamada: `how.disclaimer` ("ATROX tıbbi tavsiye değildir…"), "Nasıl hesaplanıyor?" ekranı, koç yanıtlarında güvenlik kuralları
(`coach-chat/prompts`). Politika/Koşullar için:

> **TR — Sağlık uyarısı.** ATROX bir tıbbi cihaz değildir ve tıbbi tavsiye, teşhis veya tedavi sunmaz. Güç Skoru, benzer
> kullanıcılara göre **tahmini** bir karşılaştırmadır; sağlık ölçüsü değildir. Yeni bir antrenman programına başlamadan
> önce, özellikle sakatlığın veya sağlık sorunun varsa, bir doktora veya sağlık uzmanına danış. Ağrı, baş dönmesi veya
> olağan dışı bir belirti hissedersen antrenmanı bırak. Antrenmanı kendi sorumluluğunda yaparsın.
>
> **TR — AI Koç.** AI Koç yapay zekâ kullanır; hatalı, eksik veya uygunsuz yanıt verebilir. Önerileri uygulamadan önce kendi
> durumuna uygunluğunu sen değerlendirirsin. Koç; doktor, diyetisyen veya fizyoterapist yerine geçmez; tıbbi, diyet veya ilaç
> konularında tavsiye vermez. Hiçbir öneri sen onaylamadan programına uygulanmaz.
>
> **EN — Health notice.** ATROX is not a medical device and does not provide medical advice, diagnosis or treatment. The
> Strength Score is an **estimated** comparison with similar users, not a measure of health. Check with a doctor or other
> health professional before starting a new training program, especially with an injury or health condition. Stop if you
> feel pain, dizziness or anything unusual. You train at your own risk.
>
> **EN — AI Coach.** The AI Coach uses artificial intelligence and can be wrong, incomplete or unsuitable. You decide whether
> a suggestion fits you before acting on it. It does not replace a doctor, dietitian or physiotherapist and does not give
> medical, diet or medication advice. No suggestion is applied to your program without your approval.

"Hiçbir öneri onaysız uygulanmaz" ve "tıbbi/diyet/ilaç tavsiyesi vermez" iddiaları koç güvenlik setiyle (P082) ve
öneri onay akışıyla (P080) doğrulanmalı `[HUKUKÇU + P102]`.

## 5. Yaş koşulu (16+)

- Uygulama: kayıt sırasında doğum tarihi sorulur; 16'dan küçükse **hiçbir şey kaydedilmez** (`onboarding.blocked.message`),
  Profil düzenlemede de aynı kural (`profile.edit.ageError`); veritabanı kısıtı `profiles_min_age_check`.
- KVKK'da çocuk için genel bir yaş sınırı yok; GDPR m.8 üye devletlere göre 13–16 aralığındadır; 16 üst sınır olduğu için
  AB'de ebeveyn rızası gerektirmez. ABD'de 13 yaş altı COPPA kapsamıdır (hedeflenmiyor).
- App Store yaş derecelendirmesi `docs/APP-STORE-GIZLILIK.md` §2.
- Yaş doğrulaması **beyan esaslıdır**; bunun yeterliliği `[HUKUKÇU]`.

## 6. Doldurulacak alanlar

| Alan | Nerede |
|---|---|
| Veri sorumlusu unvanı, adres, MERSİS/VERBİS (gerekiyorsa), iletişim e-postası | Privacy, Terms, Support, §3 metinleri |
| Alan adı | `LEGAL_*_URL`, `APP_LINK_HOST`, web sayfaları |
| Supabase bölgesi, TelemetryDeck saklama süresi, DeepSeek saklama/eğitim politikası bağlantısı | Privacy |
| Uygulanacak hukuk ve yetkili mahkeme | Terms |
| Yürürlük tarihi | Privacy, Terms |
