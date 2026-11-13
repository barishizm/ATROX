# 03 — Güç Skoru Modeli

Bu doküman modelin *ne* hesapladığını, *neden* bu şekilde tasarlandığını ve *nasıl* eğitilip cihaza taşındığını tanımlar.
Uygulamadaki tüm skor kodu bu dokümanın uygulamasıdır.

## 1. Problem tanımı

**Soru:** "Bu kullanıcı bu harekette, kendisine benzeyen insanlara göre ne kadar güçlü?"

**Çıktı:** `Skor ∈ [1, 99]` = kullanıcının referans nüfustaki yüzdelik dilimi. 50 = ortalama (medyan).
"Skorun 73" demek "aynı cinsiyet, yaş ve kilodaki salon kullanıcılarının %73'ünden güçlüsün" demektir.

Bu bir **regresyon değil, koşullu dağılım tahmini** problemidir. Tek bir sayı ("senin kilonda ortalama bench 80 kg")
yetmez; dağılımın tamamını bilmemiz gerekir ki kullanıcının o dağılımdaki yerini söyleyebilelim.

### Neden doğrudan "ağırlığa bakıp skor veren" tek bir model değil?

Böyle bir uçtan uca modeli eğitecek etiketli veri (hareket, ağırlık, tekrar → gerçek yüzdelik) hiçbir yerde yok.
Elimizdeki tek büyük ve temiz veri yarışma kayıtları. Bu yüzden problemi **her biri ayrı doğrulanabilen beş
katmana** bölüyoruz. Her katmanın hatası ölçülebilir ve uygulama verisi biriktikçe tek tek iyileştirilebilir.

```
set (ağırlık, tekrar, RIR)
   │  Katman 1: tekrar → 1RM eğrisi
   ▼
e1RM  ──►  Katman 2: sağlam "güncel güç" tahmini (hareket başına)
   │
   │  Katman 4: hareket → çapa oranı (ρ)          Katman 3: çapa dağılım modeli
   ▼                                              (squat/bench/deadlift | cinsiyet, yaş, kilo)
çapa-eşdeğeri güç ─────────────────────────────►  yarışmacı z-skoru
                                                       │  Katman 5: nüfus kalibrasyonu
                                                       ▼
                                          salon / genel nüfus z-skoru ──► yüzdelik = Skor
                                                       │
                                     Birleştirme: kas grubu, genel skor, dengesizlik, gelişim
```

## 2. Katman 1 — Tekrardan 1RM'e

Bir setin gösterdiği maksimum gücü tahmin ederiz: `e1RM = w / f(r_eff)`.

- `r_eff = tekrar + RIR` (RIR girilmişse; girilmemişse RIR = 0 varsayılmaz, bkz. güven ağırlığı).
- `f(1) = 1` olmak zorunda (1 tekrar yapılan ağırlık 1RM'in kendisidir).
- Aday eğri aileleri (P054'te karşılaştırılır): Epley, Brzycki, Lombardi, Mayhew, Wathan ve iki parametreli
  genel biçim `f(r) = 1 / (1 + ((r − 1)/k)^p)`.
- Parametreler **hareket kategorisine göre** ayrıdır (alt vücut bileşik, üst vücut itiş, üst vücut çekiş, izolasyon).
  Alt vücut hareketlerinde aynı %1RM ile daha çok tekrar yapılabildiği bilinir; tek eğri hepsine uymaz.

**Güven ağırlığı** `c(r_eff)`: 1–5 tekrar → 1.0; 12 tekrarda 0.6'ya, 20 tekrarda 0.25'e doğrusal iner; 30 üstü → 0
(skora girmez). RIR girilmemiş setler 0.85 ile çarpılır. Isınma setleri hiç kullanılmaz.

**Kendi kendini denetleyen iyileştirme (uygulama verisiyle):** Gerçek 1RM testi verisine ihtiyaç duymadan eğriyi
öğrenebiliriz. Aynı kullanıcı aynı harekette 14 gün içinde farklı tekrar sayılarında set yaptıysa, doğru eğri bu
setlerin hepsinden *aynı* e1RM'i üretmelidir. Kayıp fonksiyonu: kullanıcı-hareket-pencere içi `log e1RM` varyansı.
Bu, Faz 10'da kategori parametrelerini ve kullanıcıya özel `k` değerini (hiyerarşik büzülme ile) günceller.

## 3. Katman 2 — Güncel güç tahmini

Tek bir setin e1RM'i gürültülüdür (yazım hatası, yarım tekrar, iyi/kötü gün). Hareket başına güncel güç:

1. Her antrenman için güven ağırlıklı en iyi e1RM alınır.
2. Son 42 gündeki oturum değerlerinin en yükseği, **aykırı değer kontrolünden** geçerek güncel güç olur:
   bir değer önceki sağlam tahminin %12 üzerindeyse kullanıcıdan onay istenir ("Bu seti doğru mu girdin?").
3. 42 günden eski veri haftada %0.5 "form kaybı" indirimiyle kullanılır ve `bayat` olarak işaretlenir.
4. Güven: oturum sayısı, güncellik ve tekrar aralığına göre `düşük / orta / yüksek`.

## 4. Katman 3 — Çapa dağılım modeli

**Çapa hareketler:** squat, bench press, deadlift. Tek büyük veri kaynağımız (OpenPowerlifting) bunları içerir.

**Hedef:** `Y | x ~ D(θ(x))`, `x = (cinsiyet, yaş, vücut ağırlığı)`, `Y` = en iyi başarılı kaldırış (kg).

### 4.1 Veri hazırlığı (P047–P048)

- Yalnızca `Equipment = Raw` (squat için dizlik sargısı ayrı bayrak), `Sex ∈ {M, F}`, yaş 14–85, geçerli vücut ağırlığı.
- Diskalifiye, misafir ve eksik kayıtlar çıkarılır.
- **Tekrarlı ölçüm:** Aynı sporcunun onlarca kaydı vardır. Sporcu × takvim yılı başına en iyi kayıt alınır ve
  sporcular ters-frekansla ağırlıklandırılır.
- **Doping bayrağı:** Varsayılan referans `Tested = Yes` (doğal sporcuya en yakın temsil). Tüm veriyle eğitilen
  sürüm duyarlılık analizi olarak raporlanır.
- **Bölme:** Eğitim/doğrulama/test **sporcu bazında** gruplanır (aynı sporcu iki tarafta olamaz).

### 4.2 Aday modeller (P050–P052)

| Aday | Tanım | Artı | Eksi |
|---|---|---|---|
| **A — Spline-LMS** | Box-Cox Cole-Green / BCPE dağılımı; μ, σ, ν(, τ) yaş ve log-kilo üzerinde tensör çarpımı P-spline; PyTorch ile olabilirlik en çoklaması | Referans eğrilerinin standart yöntemi; çeyrekler kesişemez; yorumlanabilir; birkaç yüz parametre | Etkileşimleri elle tanımlamak gerekir |
| **B — LightGBM çeyreklik** | 19 çeyrek için pinball kaybı; kiloda monotonluk kısıtı; çeyrek kesişmesine karşı yeniden sıralama | Esnek, güçlü temel çizgi | Basamaklı çıktı, kesişme riski, büyük model, uç kuyruklar zayıf |
| **C — Sinirsel dağılımsal regresyon** | Küçük MLP (2–3 gizli katman) → BCPE veya sinh-arcsinh parametreleri; üç kaldırış için ortak gövde, ayrı başlıklar; ek olarak kaldırışlar arası korelasyon başlığı | Pürüzsüz, yeni girdilere (boy, deneyim) kolay genişler, Core ML'e doğrudan çevrilir | Düzenlileştirme ister; veri sınırlarının dışında davranışı denetlenmeli |

Üçü de aynı veri, aynı bölme ve aynı değerlendirme koşumuyla eğitilir. Hiperparametreler Optuna ile aranır (P053).

### 4.3 Önceden belirlenmiş seçim kriterleri

Kazanan, sonuçlar görülmeden önce yazılmış şu kurallarla seçilir:

1. **Birincil metrik:** Test kümesinde ortalama pinball kaybı (CRPS yaklaşımı), 19 çeyrek üzerinden.
2. **Kalibrasyon kapısı:** Her katmanda (cinsiyet × yaş bandı × kilo bandı, n ≥ 500) PIT histogramı tekdüze olmalı;
   10–90 arası çeyreklerde gözlenen-beklenen kapsama farkı ≤ `max(2 yüzdelik puan, katman gürültü bandı)`.
   Gürültü bandı = 2.77 · √(0.25 / n_etkin) · 100 (9 çeyrekte Bonferroni ile katman başına %95; n_etkin Kish etkin
   örneklemi). Kusursuz bir model de katmanların ~%5'inde bandı rastlantıyla aşacağından kapı, bandı aşan katman
   oranı ≤ %10 ise geçilmiş sayılır. *(2026-11-13 kullanıcı onayı: n≈500 ağırlıklı katmanlarda yalnız örnekleme
   gürültüsü 5–8 puan olduğundan düz 2 puan sınırı karşılanamıyordu; bkz. `ml/reports/baselines.md`.)*
   Kilo bantları yarışma kilo sınıflarıdır (erkek ≤59/66/74/83/93/105/120/>120, kadın ≤47/52/57/63/69/76/84/>84 kg).
   *(2026-11-13 kullanıcı onayı: yarışma verisinde güç sınıf sınırının hemen altında tepe yapıp hemen üstünde ~%7
   düşüyor; 10 kg'lık ondalık bantlar bu dişleri böldüğünden pürüzsüz modelleri haksız yere eliyordu.)*
3. **Akıl sağlığı testleri (hepsi geçmeli):**
   - Skor, kaldırılan ağırlıkta kesin artan.
   - Aynı kaldırış için skor, vücut ağırlığı arttıkça **artmamalı** (daha ağır kişi için aynı yük daha az etkileyicidir).
   - Beklenen medyan yaşla tek tepeli olmalı, tepe 20–40 yaş arasında; ani sıçrama olmamalı. *(2026-11-13 kullanıcı
     onayı: OPL ham verisinde tepe 27–34, bench'te 32–41 yaş; "20'lerin ortası" ifadesi bu aralıkla değiştirildi.)*
     "Ani sıçrama" sınırı (ardışık yaşlar arasında medyanda ≤ %4 değişim) yalnızca 20 yaş ve üstüne uygulanır;
     gençlerde yıllık artış verinin kendisinde %4–10 olduğundan oradaki kırılmaları pürüzsüzlük (ikinci fark)
     testi denetler. *(2026-11-13 kullanıcı onayı, P053 deneylerinden önce.)*
   - van den Hoek 2024 tablolarındaki 90. yüzdelik değerlerine ±%3 içinde uyum. vdH her yarışma kaydını ayrı sayar,
     modeller sporcu başına eşit ağırlıkla eğitilir; bu yüzden P053 bu ölçütü ağırlıklandırma açık ve kapalı iki
     sürümle raporlar ve karşılaştırmayı ağırlıksız sürüm üzerinden yapar. *(2026-11-13 kullanıcı onayı.)*
4. **Dağıtım kısıtı:** Model < 1 MB, tek çıkarım < 1 ms.
5. **Eşitlik durumunda** (birincil metrik farkı < %1) daha basit model kazanır (A > C > B).

Hangi adayın kazanacağını bugünden bilmiyoruz. Üç girdili bu problemde A'nın C'ye çok yakın çıkması muhtemeldir;
C'nin asıl avantajı v2'de girdi sayısı artınca ortaya çıkar. Rapor (`ml/reports/bakeoff.md`) sonucu belgeleyecek.

### 4.4 Ortak dağılım

Tam güç (SBD) yarışmalarında üç kaldırış da aynı sporcudan gelir. Bu, koşullu **korelasyon matrisini** öğrenmemizi
sağlar: `Corr(z_S, z_B, z_D | x)`. Kullanım alanları: genel skoru doğru ölçeklemek (§8) ve dengesizlik tespiti (§10).

### 4.5 Cinsiyet belirtmeyen kullanıcılar

Skor, erkek ve kadın dağılımlarının eşit ağırlıklı karışımına göre hesaplanır ve ekranda açıkça belirtilir.

## 5. Katman 5 — Nüfus kalibrasyonu (en kritik mühendislik problemi)

Yarışmacılar salon nüfusunun güçlü ucudur. Salonda ortalama biri yarışmacı dağılımında 10. yüzdeliğin altında
çıkar; bu skoru göstermek hem yanlış hem moral bozucudur.

### 5.1 Model

Log ölçekte yer-ölçek dönüşümü:

```
z_g = ( z_c · s_c(x) + m_c(x) − m_g(x) ) / s_g(x)
m_g(x) = m_c(x) − δ_g(cinsiyet, kaldırış, yaş bandı)       // medyan kayması
s_g(x) = κ_g(cinsiyet, kaldırış) · s_c(x)                   // yayılım oranı
g ∈ { yarışmacı, salon, genel }
```

**v1 kestirimi (P055):** çapa sayısı az olduğu için `δ_g = D_g(cinsiyet) + L(cinsiyet, kaldırış) + A_g(cinsiyet, yaş bandı)`
(kaldırış farkı `L` iki nüfusta ortak) ve `κ` nüfus başına tek değer (cinsiyet/kaldırış ayrımı yok) olarak kestirilir.
Ayrıntı ve gerekçe: `ml/reports/calibration.md`.

**Gerekçe:** Yarışmaya katılma olasılığı güçle üstel artıyorsa (lojistik seçilim), log-normal bir taban dağılımın
seçilmiş alt kümesi yine yaklaşık log-normaldir ve ortalaması kaymıştır. Yani yer-ölçek dönüşümü keyfi bir düzeltme
değil, seçilim yanlılığının birinci dereceden modelidir.

### 5.2 Parametrelerin kestirimi (P055)

`δ` ve `κ`, elle derlenmiş ve her satırı kaynak gösterilen bir **çapa dosyasından** (`ml/data/anchors.csv`) kestirilir:

| Çapa türü | Örnek | Hangi nüfus |
|---|---|---|
| Yayımlanmış salon standartları | Seviye = yüzdelik eşlemesi (5/20/50/80/95) olan tablolardan seçilmiş noktalar | salon |
| Akademik kohortlar | "Rekreasyonel antrenmanlı" erkek/kadın gruplarının ortalama ± SS 1RM değerleri | salon |
| Nüfus normları | Yaş ve cinsiyete göre 1RM bench/leg press oran yüzdelikleri (ACSM/Cooper türü tablolar) | genel |
| Yaş eğrisi | El kavrama gücü normlarından yaşa bağlı düşüş hızı (NHANES tabanlı çalışmalar) | genel |

Kestirim: çapalardaki (yüzdelik, değer) çiftlerine ağırlıklı en küçük kareler; çapalar kaynak güvenilirliğine göre
ağırlıklanır. Çapalar arası tutarsızlık **belirsizlik bandı** olarak saklanır ve arayüzde gösterilir.

Çapa dosyası derlenirken tablolar toplu kopyalanmaz; kaynak başına az sayıda nokta alınır, her birinin URL'si ve
erişim tarihi yazılır, birincil kaynak okunamayan çapa dosyaya girmez.

### 5.3 Dürüstlük notu

P055 duyarlılık analizi (kaynak çıkarma, ağırlıklandırma, yarışmacı referansı, varsayım değişiklikleri ve bootstrap
zarfının yarı genişliği; tipik kullanıcılar) ölçülen belirsizlik bandı:

- **Salon referansı:** medyan **±8 yüzdelik puan**, en kötü ±19 (squat: kaldırış farkı tek kaynağa dayanıyor).
  Örnek: 80 kg, 30 yaş erkek, bench 80 kg → salon skoru ≈ 26 (bant 21–31).
- **Genel nüfus referansı:** medyan **±19 puan**, en kötü ±26 — çapası az; v1'de "çok tahmini" olarak gösterilmeli.
- Yarışmacı referansı doğrudan veriye dayanır; bu bant ona uygulanmaz.

Ayrıntı: `ml/reports/calibration.md`; değerler `ml/params_draft/calibration.json` → `uncertainty_band_pct_points`.
Rakamlar P057'de P053 kazananı (Spline-LMS) yarışmacı referansı olarak takılarak yeniden üretildi
(önceki ampirik OPL referansına göre skorlar ≤ 2,5 puan oynadı). Bu yüzden:

- Skorun yanında güven göstergesi ve "tahmini" etiketi bulunur.
- Yarışmacı referansı her zaman seçilebilir; o referans doğrudan veriye dayanır ve en güvenilir olandır.
- Faz 10'da uygulamanın kendi kullanıcı verisi kalibrasyonu günceller (§12).

## 6. Katman 4 — Çapa olmayan hareketler

800+ hareketin yalnızca üçü için dağılım verimiz var. Diğerleri bir çapaya **oran** ile bağlanır:

```
log e1RM_e = log ρ_e + log e1RM_çapa(e) + ε_e ,   ε_e ~ N(0, τ_e²)
z_e = z_çapa( e1RM_e / ρ_e ) · s / sqrt(s² + τ_e²)
```

`τ_e` oranın kişiden kişiye ne kadar değiştiğini temsil eder; payda büyüdükçe skor ortaya doğru çekilir (emin
olmadığımız harekette uç skor vermeyiz).

`tools/catalog/scoring_taxonomy.yaml` her skorlanabilir hareket için şunları tutar (P025, P056):

| Alan | Açıklama |
|---|---|
| `anchor` | `squat` / `bench` / `deadlift` |
| `ratio` (ρ) | Çapaya göre tipik güç oranı (ör. overhead press ≈ 0.60–0.67 × bench); kullanıcının yazdığı birimde (yük kuralına göre), değerler ve kaynaklar `tools/catalog/ratios.yaml` (P056) |
| `tau` | Oran belirsizliği |
| `ratio_confidence` | `A` (literatür/çoklu kaynak), `B` (tek kaynak), `C` (uzman tahmini) |
| `load_convention` | `total` (bar dahil), `per_hand` (dumbbell), `per_side` (plaka yüklü), `machine_stack`, `bodyweight_plus` |
| `bw_fraction` | Vücut ağırlığı hareketlerinde taşınan vücut ağırlığı oranı (barfiks 1.0, dips ≈ 0.95 — segment kütleleri, de Leva 1996; şınav ≈ 0.70 — Suprak 2011, Ebben 2011) |
| `scoring_type` | `weighted`, `bodyweight_loaded`, `reps_only`, `time`, `none` |

**Skorlama türleri**

- `weighted`: yukarıdaki formül.
- `bodyweight_loaded` (barfiks, dips, chin-up): efektif yük = `bw_fraction × vücut ağırlığı + ek yük`, sonra aynı formül.
- `reps_only` (şınav, mekik): yayımlanmış yaş/cinsiyet tekrar normlarından enterpolasyon; her zaman "düşük güven".
- `time` (plank) ve `none` (esneme, kardiyo): skorlanmaz, yalnızca kaydedilir.

**Makine ve kablo hareketleri:** Makara oranı ve marka farkı yüzünden yük karşılaştırılamaz. Bu hareketler en fazla
"düşük güven" alır, genel skora 0.3 ağırlıkla girer ve esas olarak **kişinin kendi gelişimi** üzerinden değerlendirilir.

İlk sürümde hedef: ~150 skorlanabilir çekirdek hareket (salon kullanımının büyük çoğunluğu). Kalanı kaydedilir,
gelişim grafiği gösterir ama yüzdelik skor üretmez.

## 7. Boy bilgisinin kullanımı

Yarışma verisinde boy yok; bu yüzden v1'de boy çapa dağılım modelinin girdisi **olamaz**. Dürüst kullanım planı:

- **v1:** Boy toplanır; BMI üzerinden bir **vücut kompozisyonu düzeltmesi deneyi** yapılır (P055): yüksek BMI'li
  salon/genel nüfus kullanıcısında kilonun tamamı yağsız kütle sayılmamalıdır. Düzeltme değerlendirmede iyileşme
  göstermezse kapalı kalır (özellik bayrağı). Boy ayrıca koçun bağlamına ve anonim katkıya girer.
  **P055 sonucu: kapalı.** Çapalarda bireysel boy yok; varsayılan boylarla yapılan deneyde düzeltme hatayı artırdı
  (salon çapaları ağır kullanıcıları yarışmacı VA eğrisinin öngördüğünden *güçlü* gösteriyor, düzeltmenin tersi
  yönde). Ayrıntı `ml/reports/calibration.md`.
- **v2:** Uygulama verisi biriktiğinde boy tam kovaryat olur (literatür, kuvvetin boy² ile ölçeklendiğini gösteriyor).

## 8. Birleştirme: kas grubu ve genel skor

Yüzdelikler doğrudan ortalanmaz (ortalamanın yüzdeliği, yüzdeliklerin ortalaması değildir). Birleştirme z uzayında:

```
z_grup = Σ w_i z_i / sqrt( Σ w_i² + 2 Σ_{i<j} w_i w_j r_ij )
```

Payda, ortalamanın varyansını 1'e geri ölçekler. `r_ij` §4.4'teki korelasyonlardan gelir (bilinmeyen çiftler için 0.6).
Sonuç: korelasyon 1'den küçükken eşit iki skorun birleşimi aynı yönde **daha uçtur** (ör. r = 0.6 iken iki 60 → ≈ 61; 50 her
zaman 50) — bütün hareketlerde 60. yüzdelikte olmak, tek harekette olmaktan daha nadirdir. P057 referansı bunu
uygular; kullanıcıya gösterim kararı açık (`docs/ILERLEME.md` Ertelenenler).

- **Kas grubu skoru:** `w_i` = kas katılımı (birincil 1.0, ikincil 0.4) × hareket güveni × güncellik.
- **Genel Güç Skoru:** 7 hareket kalıbı üzerinden (yatay itiş, dikey itiş, yatay çekiş, dikey çekiş, squat, kalça
  menteşesi, gövde). Tam skor için en az 3 kalıp ve hem alt hem üst vücut gerekir; aksi halde "geçici skor" etiketi.
- **Seviye adları:** 0–20 Başlangıç · 20–40 Gelişen · 40–60 Orta · 60–80 İleri · 80–95 Uzman · 95+ Elit.

Skor [1, 99] aralığına kırpılır; "100" ve "0" gösterilmez.

## 9. Gelişim analitiği

- **Eğilim:** Son 8–12 haftadaki oturum e1RM'leri üzerinde Theil–Sen eğimi → aylık yüzde değişim.
- **Gelişim Skoru:** Eğimin, kullanıcının seviyesindeki *beklenen* gelişim hızına oranı. Yeni başlayanlar hızlı,
  ileri seviye yavaş gelişir; aynı aylık %1 artış ikisi için farklı anlam taşır. Beklenti eğrisi ilk sürümde
  literatürden gelen bir azalan-getiri eğrisidir, Faz 10'da uygulama verisiyle öğrenilir.
- **Plato tespiti:** Yeterli antrenman sıklığına rağmen 4+ hafta anlamlı artış yoksa (CUSUM) içgörü üretilir.
- **Tahmin:** 4/8/12 hafta sonrası e1RM, belirsizlik bandıyla.

## 10. Dengesizlik analizi

Ortak dağılım sayesinde "diğer kaldırışlarına bakılırsa bench'in ne olmalıydı?" sorusunu sorabiliriz:
`E[z_B | z_S, z_D, x]`. Gözlenen ile beklenen arasındaki fark 1 standart sapmayı aşarsa içgörü kartı çıkar.
Ek olarak kural tabanlı oranlar: itiş/çekiş, üst/alt vücut, squat/deadlift, sol/sağ (tek taraflı hareketlerde).

## 11. Dışa aktarım ve cihazda çalışma

**Model paketi** (`model-bundle-vX.Y.Z/`):

| Dosya | İçerik |
|---|---|
| `anchor.mlpackage` | Çapa dağılım ağı (C kazanırsa) — veya `anchor_tables.json` (A kazanırsa spline katsayıları) |
| `params.json` | 1RM eğri parametreleri, kalibrasyon (δ, κ, belirsizlik), korelasyonlar, seviye eşikleri, birleştirme ağırlıkları |
| `taxonomy.json` | Hareket oranları ve yük kuralları |
| `manifest.json` | Sürüm, şema sürümü, dosya SHA-256'ları, en düşük uygulama sürümü, eğitim verisi özeti |
| `manifest.sig` | Ed25519 imzası |

`StrengthKit` bir `AnchorDistribution` protokolü tanımlar; Core ML ve tablo tabanlı iki uygulaması vardır, böylece
yarışmayı hangi aday kazanırsa kazansın uygulama kodu değişmez.

**Eşlik testi:** Python hattı ~2.000 rastgele girdi için uçtan uca beklenen çıktıları `ml/golden/*.json` olarak
üretir; Swift testleri aynı girdilerle 1e-4 toleransla aynı sonucu doğrular.

**Güncelleme:** Uygulama içinde gömülü bir temel paket bulunur (ilk açılışta çevrimdışı çalışır). Açılışta
`model_versions` tablosu kontrol edilir; daha yeni ve uyumlu paket varsa indirilir, imza ve özetler doğrulanır,
altın vektörlerin küçük bir alt kümesiyle duman testi yapılır, sonra etkinleştirilir. Sunucudaki `is_active` bayrağı
ile geri alma mümkündür. Skor anlık görüntüleri model sürümünü saklar; sürüm değişince skor farkı kullanıcıya açıklanır.

## 12. Kendini iyileştiren döngü (Faz 10)

1. Anonim katkılar (`ml_contributions`) k-anonimlik süzgecinden geçerek dışa aktarılır.
2. **Kalibrasyon güncellemesi:** Uygulama kullanıcıları doğrudan "salon kullanıcısı" örneğidir. `δ` ve `κ` için
   mevcut değerler önsel, uygulama verisi olabilirlik olur (Bayesçi güncelleme). Uygulama kullanıcıları da yanlı bir
   örnektir (takip uygulaması kullananlar daha ciddidir); bu yüzden önsel tamamen atılmaz.
3. **Oran güncellemesi:** Aynı kullanıcının birden çok hareketi olduğu için `ρ_e` ve `τ_e` doğrudan kestirilebilir.
4. **1RM eğrisi güncellemesi:** §2'deki kendi kendini denetleyen kayıp.
5. **Kalite kapıları:** Yeni paket altın vektör regresyonunu, kalibrasyon kapısını ve "skor kayması" sınırını
   (medyan mutlak değişim ≤ 5 puan) geçmeden yayınlanmaz.

### v2 araştırma izi: gizil faktör modeli (P095)

```
log e1RM_{u,e} = b_e + λ_e · θ_u + ε
```

Her kullanıcının düşük boyutlu bir güç vektörü (`θ_u`: itiş, çekiş, alt vücut…), her hareketin bir zorluk sabiti
ve yükleme vektörü vardır. Bu tek model şunları birlikte verir: her hareket için skor, **hiç yapılmamış hareket
için başlangıç ağırlığı tahmini**, dengesizlik ve genel güç. Etkinleştirme koşulu: en az ~5.000 katkıcı ve hareket
başına ≥ 300 gözlem. O zamana kadar oran tablosu kullanılır.

## 13. Sınırlar ve etik

- Skor bir **sağlık ölçüsü değildir**; uygulama bunu açıkça söyler.
- Skor ego kaldırışını teşvik etmemelidir: aykırı değer onayı, koçun teknik vurgusu, gelişim skorunun öne çıkarılması.
- 16 yaş altı kullanıcı kabul edilmez; 16–18 yaş için koç ek temkinli davranır.
- Model kartı (`ml/MODEL_CARD.md`) veri kaynaklarını, bilinen yanlılıkları ve her sürümün metriklerini belgeler.

## 14. Eğitim ortamı

Python 3.12 · `uv` · polars + duckdb (veri) · PyTorch (A ve C) · LightGBM (B) · Optuna · coremltools · pytest.
Tüm rastgelelik tohumlanır; her deney `ml/runs/<zaman>-<ad>/` altına yapılandırma, metrik ve grafiklerle yazılır.
