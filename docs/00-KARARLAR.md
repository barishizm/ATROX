# 00 — Kararlar ve Araştırma Bulguları

Son güncelleme: 2026-11-11. Bu dosya projenin "anayasası"dır; buradaki bir kararı değiştirmek tüm prompt listesini etkiler.

## 1. Ürün tanımı

**Tek cümle:** Antrenmanını kaydet, her hareketteki gücünün kendi kategorindeki insanlara göre 100 üzerinden kaç olduğunu
öğren, verini bilen bir yapay zekâ koçla geliş.

**Farklılaştırıcılar**

1. **Güç Skoru:** Kendi eğittiğimiz, cinsiyet/yaş/vücut ağırlığına koşullu, kalibre edilmiş yüzdelik modeli. Skorun
   yanında her zaman *kime göre* ve *ne kadar emin olduğumuz* gösterilir.
2. **Kas grubu ısı haritası ve dengesizlik analizi:** "Çekiş gücün itişine göre geride" gibi somut içgörüler.
3. **Ajan koç:** Sohbet etmekle kalmaz; geçmişi sorgular, program önerir, kullanıcı onayıyla uygulamaya yazar.
4. **Hızlı set girişi:** Salonda tek elle, üç dokunuşta set kaydı; dinlenme sayacı kilit ekranında.

## 2. Kullanıcıyla kesinleştirilen kararlar

| # | Konu | Karar |
|---|---|---|
| 1 | Geliştirme ortamı | Mac'te yerel Claude Code; derleme/simülatör/test döngüsü yerelde |
| 2 | Teknoloji | Native SwiftUI (Swift 6, SwiftData) |
| 3 | Backend | Supabase |
| 4 | Minimum iOS | iOS 26+ |
| 5 | Kapsam | Tam antrenman takipçisi + analiz |
| 6 | Skor referansı | Varsayılan: düzenli salon kullanıcıları. Seçilebilir: genel nüfus, yarışmacı sporcular |
| 7 | Skor seviyeleri | Hareket + kas grubu + genel skor + gelişim hızı + dengesizlik |
| 8 | Çıkarım | Cihaz üstünde; model paketi buluttan güncellenir |
| 9 | LLM | DeepSeek V4.1 Flash; birincil OpenRouter (ucuz sağlayıcı), yedek resmi DeepSeek API |
| 10 | Koç yetkisi | Ajan: veriyi okur, değişiklik **önerir**, kullanıcı onayıyla uygulanır |
| 11 | Görseller | free-exercise-db fotoğrafları + kendi kas haritamız |
| 12 | Diller | Türkçe + İngilizce |
| 13 | Gelir | Freemium abonelik (StoreKit 2) |
| 14 | Giriş | Apple + Google + e-posta |
| 15 | Health/Watch | HealthKit + Live Activity v1.0'da; Watch uygulaması v1.x |
| 16 | Tasarım | Koyu, atletik, veri odaklı |
| 17 | Skorlanan türler | Ağırlıklı + vücut ağırlığı hareketleri; kardiyo yalnızca kaydedilir |
| 18 | Veri katkısı | İsteğe bağlı, anonim, güven veren dille (uygulama biçimi için §4'e bak) |
| 19 | Sosyal | Paylaşılabilir skor kartı + arkadaş sıralaması |
| 20 | Ad | Ad `ATROX`; görünen ad tek yerden değişir |

## 3. Benim verdiğim mühendislik kararları (gerekçeli)

| Konu | Karar | Gerekçe |
|---|---|---|
| Proje üretimi | XcodeGen | `.xcodeproj` birleştirme çakışması olmaz; Claude YAML düzenleyerek hedef ekleyebilir |
| Modülerlik | 4 yerel Swift paketi | Skor motoru UI'dan bağımsız test edilir; derleme süreleri kısalır |
| Yerel veri | SwiftData, çevrimdışı öncelikli | Salonda bağlantı zayıftır; kayıt asla ağa bağlı olmamalı |
| Senkronizasyon | Kendi "outbox" motorumuz | CloudKit yerine Supabase seçildi; kayıt bazında son-yazan-kazanır yeterli |
| Model çalışma zamanı | Core ML (`.mlpackage`) + saf Swift | Core AI iOS 27 ister; tabular modeller için Core ML geçerli yol. Hedefimiz iOS 26 |
| Model güncelleme | İmzalı model paketi (Ed25519) | İndirilen model dosyası kurcalanamaz; App Store güncellemesi gerekmez |
| Abonelik | Doğrudan StoreKit 2 + App Store Server Notifications V2 | Üçüncü taraf bağımlılığı yok; koç kotası sunucuda yetki bilmek zorunda |
| Analitik | TelemetryDeck + MetricKit | Kimlik toplamayan analitik; gizlilik etiketleri sade kalır |
| Yaş sınırı | 16+ | Sağlık benzeri veri + AI sohbeti; KVKK/GDPR rıza yaşı karmaşasından kaçınmak |
| Soyad | İsteğe bağlı | Veri minimizasyonu; analizde hiçbir işlevi yok |
| Push bildirimi | v1.0'da yalnızca yerel bildirim | APNs sunucu altyapısı v1.x'e ertelendi |

## 4. Düzeltilmesi gereken bir istek: "otomatik tikli" rıza kutusu

Veri katkısı için kutunun **işaretli gelmesini** istedin. Bunu aynen uygulamamayı öneriyorum, çünkü:

- GDPR'da önceden işaretlenmiş kutu geçerli rıza sayılmıyor (ABAD *Planet49* kararı); KVKK'da açık rıza da
  kullanıcının aktif bir eylemini gerektiriyor.
- App Store incelemesinde önceden işaretli rıza kutuları yanıltıcı kabul edilip ret sebebi olabiliyor.

**Aynı hedefe (yüksek katılım + güven) ulaşan tasarım:** Onboarding'de tek amaçlı bir ekran.
Başlık: "Modeli birlikte geliştirelim". Üç kısa güvence satırı (isim/e-posta gitmez · yalnızca yaş aralığı, kilo,
cinsiyet ve en iyi setler · istediğin an kapatırsın). Büyük birincil düğme **"Anonim olarak katkı sağla"**, altında
sade ikincil bağlantı "Şimdi değil". Kutu yok, dolayısıyla "ön işaret" sorunu da yok; birincil düğme varsayılan
yol olduğu için katılım oranı yüksek kalır. Hukuki metinler yayın öncesinde bir hukukçuya gösterilmelidir (P101).

## 5. Araştırma bulguları

### 5.1 LLM

- `deepseek-v4-flash` adı emekli; güncel model **DeepSeek-V4.1-Flash-1017**, resmi API adı `deepseek-flash`.
  1M bağlam, araç çağırma, JSON çıktısı, görsel girdi; düşünme modu varsayılan açık.
- Resmi fiyat (1M token): girdi $0.30 (yoğun) / $0.15 (sakin), önbellek isabeti $0.006 / $0.003, çıktı $1.20 / $0.60.
  Yoğun saat: hafta içi 01:00–04:00 ve 06:00–10:00 UTC.
- OpenRouter kimliği `deepseek/deepseek-v4.1-flash`. Sağlayıcı fiyatları çok değişken (ör. DeepInfra $0.112 / $0.336).
  AB bölge içi yönlendirme şu an yok. Ucuz sağlayıcılarda nicemleme ve araç çağırma kalitesi farklı olabilir →
  **sağlayıcı izin listesi** kullanılacak ve koç değerlendirme seti (P082) ile doğrulanacak.
- Uzun ve sabit sistem istemi kullandığımız için resmi API'nin önbellek indirimi toplam maliyette OpenRouter'daki
  ucuz sağlayıcıyı geçebilir. Proxy her isteğin maliyetini kaydeder; karar veriyle verilir (P073).

### 5.2 ML verisi

- **OpenPowerlifting:** ~3M+ yarışma kaydı; cinsiyet, yaş, vücut ağırlığı, ekipman, squat/bench/deadlift, "Tested"
  bayrağı. Proje verisini kamu malı olarak yayımlıyor (indirirken LICENSE dosyası teyit edilecek — P047).
  **Boy bilgisi yok.** Yarışmacıları temsil eder; salon ortalaması değildir.
- **van den Hoek ve ark. 2024** (809.986 kayıt): doğrulama için bağımsız referans. 18–35 yaş 90. yüzdelik:
  squat 2.83×/2.26× VA, bench 1.95×/1.35×, deadlift 3.25×/2.66× (erkek/kadın).
- **Çok kullanıcılı gerçek salon logu açık veri olarak yok.** Kaggle'daki setler tek kullanıcılı veya sentetik.
  Sonuç: salon kullanıcısı dağılımı ilk sürümde kalibrasyonla türetilir, sonra uygulamanın kendi verisiyle öğrenilir.
- **Strength Level** seviye tanımları (5/20/50/80/95. yüzdelik) ve yayımlanmış tablolar kalibrasyon çapası olarak
  kullanılabilir; tablolar toplu kopyalanmaz, az sayıda çapa noktası kaynak gösterilerek elle derlenir.
- **Referans eğrisi yöntemi:** GAMLSS/LMS büyüme eğrilerinin ve el kavrama gücü normlarının standart yöntemi
  (Nevill, Tomkinson ve ark.). Bizim model yarışmasında (P050–P053) temel aday.
- **1RM tahmini:** Formüller 2–10 tekrarda güvenilir, 10+ tekrarda bozulur ve harekete göre değişir. İkincil
  kaynaklardaki hata yüzdeleri doğrulanmadı; P054'te birincil makalelerden teyit edilecek.

### 5.3 Platform

- iOS 27 ile **Core AI** geldi (PyTorch → `.aimodel`, iOS 27 şart). Core ML kaldırılmadı; ağaç ve tabular modeller
  için hâlâ önerilen yol. iOS 26 hedeflediğimiz için Core ML kullanıyoruz; Core AI'a geçiş v2 konusu.
- **Foundation Models** (Apple'ın cihaz üstü LLM'i) iOS 26'da mevcut; çevrimdışı kısa özetler için yedek (P083).
- **App Store 5.1.2(i):** Kişisel veri üçüncü taraf AI'a gönderilmeden **önce** kime ne gittiğini söyleyen açık
  onay ekranı zorunlu. İstek onaydan önce atılırsa ret sebebi.
- **XcodeBuildMCP** Claude Code'a derleme/simülatör/test araçları verir (P001'de kurulur).

### 5.4 İçerik

- **free-exercise-db:** 800+ hareket, Unlicense (kamu malı). Alanlar: `force`, `level`, `mechanic`, `equipment`,
  `primaryMuscles`, `secondaryMuscles`, `instructions`, `category`, `images` (hareket başına genelde 2 JPG).
  17 kas: abdominals, abductors, adductors, biceps, calves, chest, forearms, glutes, hamstrings, lats, lower back,
  middle back, neck, quadriceps, shoulders, traps, triceps.
- **Kas haritası:** `react-native-body-highlighter` (MIT) SVG yolları SwiftUI `Shape`'e çevrilebilir; LICENSE dosyası
  P029'da teyit edilecek ve atıf eklenecek.

## 6. Bilinçli olarak v1.0 dışında bırakılanlar

Apple Watch uygulaması · kardiyo skoru · kamera ile form analizi · beslenme/kalori takibi · APNs push ·
herkese açık küresel sıralama · Android · Core AI'a geçiş · antrenör–öğrenci paneli.

## 7. Açık riskler

| Risk | Etki | Önlem |
|---|---|---|
| Salon kullanıcısı kalibrasyonu ilk sürümde yaklaşık | Skor ±10 yüzdelik puan sapabilir | Güven aralığı göster; uygulama verisiyle yeniden kalibre et (P094) |
| Makine/kablo hareketlerinde yük markaya göre değişir | Skor yanıltıcı olabilir | "Düşük güven" etiketi; genel skorda düşük ağırlık |
| Kullanıcı yanlış veri girer (yazım hatası, yarım tekrar) | Skor şişer | Aykırı değer onayı; sağlam (robust) güç tahmini |
| Ucuz LLM sağlayıcısında araç çağırma hataları | Koç yanlış işlem önerir | Sağlayıcı izin listesi + değerlendirme seti + kullanıcı onayı |
| Sağlık benzeri verinin yurt dışına aktarımı | KVKK/GDPR yükümlülüğü | Modele yalnızca anonim özet; açık onay; hukukçu incelemesi |
| App Store incelemesi (AI + abonelik + sağlık) | Yayın gecikmesi | P101–P103 kontrol listesi; inceleme notları ve demo hesabı |

## 8. Kaynaklar

- DeepSeek fiyat/model sayfası: https://api-docs.deepseek.com/quick_start/pricing
- OpenRouter model sayfası: https://openrouter.ai/deepseek/deepseek-v4.1-flash
- OpenPowerlifting CSV belgeleri: https://openpowerlifting.gitlab.io/opl-csv/bulk-csv-docs.html
- van den Hoek ve ark. 2024: https://pubmed.ncbi.nlm.nih.gov/39060209/
- El kavrama gücü ve allometri (Nevill, Tomkinson): https://acsm.org/handgrip-strength-normalized-body-size/
- free-exercise-db: https://github.com/yuhonas/free-exercise-db
- Apple 5.1.2(i) haberi: https://techcrunch.com/2025/11/13/apples-new-app-review-guidelines-clamp-down-on-apps-sharing-personal-data-with-third-party-ai
- Core AI / Core ML durumu (ikincil kaynak): https://ecorpit.com/core-ai-framework-ios-27-replaces-core-ml/
- XcodeBuildMCP rehberi: https://mcp.directory/blog/xcodebuildmcp-complete-guide-2026
- Strength Level hakkında: https://strengthlevel.pt/sobre
