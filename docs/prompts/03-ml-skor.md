# Faz 5–6 · ML Modeli, Skor ve Analiz Arayüzü (P046–P071)

Faz 5'in tamamı için zorunlu okuma: `docs/03-ML-MODEL.md`. P046–P059 `[PARALEL]` yürütülebilir (uygulamaya dokunmaz).

---

## Faz 5 — ML: veri ve model

### P046 · ML çalışma alanı `[PARALEL]`

```text
ml/ altında eğitim projesini kur (docs/03-ML-MODEL.md §14):
- uv ile Python 3.12 projesi; bağımlılıklar: polars, duckdb, pyarrow, numpy, scipy, torch, lightgbm, optuna,
  coremltools, matplotlib, pytest, ruff. Sürümleri kilitle.
- Yapı: src/gymml/{data,features,models,eval,export,utils}, tests/, configs/, reports/, golden/,
  data/{raw,interim,processed} (raw ve interim gitignore'da), runs/ (gitignore).
- Yapılandırma: YAML + tipli dataclass'lar. Her çalıştırma runs/<zaman>-<ad>/ altına yapılandırmanın kopyasını,
  git commit özetini, metrikleri (JSON) ve grafikleri yazar.
- Tekrarlanabilirlik: tek seed_everything yardımcı fonksiyonu; deterministik bayraklar.
- Makefile hedefleri: data, eda, train-a, train-b, train-c, tune, bakeoff, export, test.
- ml/MODEL_CARD.md iskeleti (veri kaynakları, amaç, sınırlar, sürüm tablosu).
Duman testi: make test geçmeli.
```

Kabul: `make test` yeşil; örnek bir çalıştırma `runs/` altında iz bırakıyor.

### P047 · OpenPowerlifting içe aktarma `[PARALEL]`

```text
OpenPowerlifting toplu CSV'sini içe aktaran hattı yaz (gymml/data/opl.py, make data):
- Resmi toplu indirme bağlantısını projenin kendi veri sayfasından bul; indirilen arşivin içindeki LICENSE/README
  metnini oku ve lisans durumunu ml/data/SOURCES.md'ye birebir alıntıyla, indirme tarihi ve dosya SHA-256'sı ile yaz.
  Lisans kamu malı değilse veya belirsizse DUR ve bana bildir.
- CSV'yi akış halinde oku, şemayı açıkça tanımla (sütun belgeleri: openpowerlifting.gitlab.io/opl-csv/bulk-csv-docs.html),
  Parquet'e yaz (data/interim/opl.parquet).
- Ad sütununu sporcu kimliğine (kararlı özet) çevir ve adı AT; ileriki hiçbir dosyada kişi adı bulunmasın.
- Veri sözleşmesi testleri: beklenen sütunlar, tipler, değer aralıkları, satır sayısı alt sınırı.
- ml/reports/data_dictionary.md: kullandığımız her sütunun anlamı.
```

Kabul: Parquet üretildi; lisans alıntısı belgelendi; sözleşme testleri geçiyor.

### P048 · Temizleme, kohort tanımı ve keşif analizi `[PARALEL]`

```text
docs/03-ML-MODEL.md §4.1'i uygula (gymml/data/cohort.py):
- Süzgeçler: Equipment = Raw (squat için Wraps ayrı bayrak), Sex ∈ {M,F}, yaş 14–85, geçerli vücut ağırlığı,
  başarılı kaldırış > 0, diskalifiye/misafir/no-show hariç. Yaşı eksik kayıtlar için AgeClass orta noktasını
  kullanmanın etkisini ölç; kararı raporla.
- Uzun biçime çevir: (sporcu, yıl, cinsiyet, yaş, kilo, kaldırış türü, değer, tested, federasyon).
- Sporcu × yıl × kaldırış başına en iyi kayıt; sporcu başına ters-frekans ağırlığı.
- Aykırı değerler: fiziksel olarak imkânsız oranları (ör. vücut ağırlığının 6 katı bench) ve veri giriş hatalarını ele.
- SBD üçlüsü tam olan kayıtlar için ayrı "ortak" tablo (korelasyon için).
- Her süzgeçten sonra kalan satır sayısını gösteren akış tablosu.
Keşif raporu (ml/reports/eda.md + grafikler): kaldırış dağılımları, kilo ve yaşa göre medyan eğrileri, tested vs
tümü farkı, cinsiyet/yaş/kilo hücrelerinde örneklem büyüklüğü ısı haritası, seyrek bölgeler.
```

Kabul: Kohort tabloları üretildi; EDA raporu seyrek bölgeleri ve süzgeç etkilerini gösteriyor.

### P049 · Değerlendirme koşumu ve temel çizgiler `[PARALEL]`

```text
Tüm adayların kullanacağı ortak değerlendirme altyapısını yaz (gymml/eval):
- Bölme: sporcu kimliğine göre gruplu %70/15/15; sabit tohum; bölme dosyaları diske yazılır ve tüm modeller aynısını kullanır.
- Ortak arabirim: DistributionModel.fit(df), .quantile(x, q), .cdf(x, y), .params(x).
- Metrikler: 19 çeyrek üzerinden ortalama pinball kaybı; CRPS yaklaşımı; PIT histogramı ve tekdüzelik istatistiği;
  katman bazında (cinsiyet × yaş bandı × kilo bandı, n ≥ 500) kapsama hatası tablosu.
- Akıl sağlığı testleri (docs/03-ML-MODEL.md §4.3 madde 3): ağırlıkta monotonluk, kiloda artmama, yaş eğrisinin
  biçimi, pürüzsüzlük (ikinci fark sınırı), eğitim aralığı dışında makul davranış.
- Dış doğrulama: van den Hoek 2024 makalesindeki yüzdelik değerlerini birincil kaynaktan oku, ml/data/external/
  altına kaynağıyla yaz, model çıktısıyla karşılaştıran test ekle.
- Temel çizgiler: (1) hücre bazlı ampirik yüzdelikler, (2) DOTS puanının ampirik dağılımı.
Temel çizgilerin metriklerini ml/reports/baselines.md'ye yaz; adaylar bunları geçmek zorunda.
```

Kabul: İki temel çizgi koşumdan geçiyor; rapor ve dış doğrulama testi hazır.

### P050 · Aday A — Spline-LMS `[PARALEL]`

```text
Aday A'yı uygula (docs/03-ML-MODEL.md §4.2): GAMLSS tarzı referans eğrisi modeli, PyTorch ile.
- Dağılım: Box-Cox Cole-Green (BCCG) ve Box-Cox Power Exponential (BCPE); log-olabilirlik, CDF ve ters CDF'i
  kendin yaz, scipy ile sayısal olarak doğrula (birim testi).
- μ, σ, ν (ve BCPE için τ): cinsiyet başına, yaş ve log-kilo üzerinde tensör çarpımı B-spline tabanı;
  ikinci fark (P-spline) cezası. σ > 0 ve μ > 0 için uygun bağlantı fonksiyonları.
- Üç kaldırış için ayrı modeller. Örnek ağırlıkları P048'den.
- Eniyileme: Adam ile ısınma, sonra L-BFGS; erken durdurma doğrulama olabilirliğine göre.
- Ceza katsayıları ve düğüm sayıları yapılandırmadan; makul varsayılanlarla bir temel eğitim yap.
P049 koşumuyla değerlendir; yüzdelik eğrilerini (5/25/50/75/95) kilo ve yaşa karşı çiz; BCCG vs BCPE farkını raporla.
```

Kabul: Model temel çizgileri geçiyor; akıl sağlığı testlerinin sonucu raporda.

### P051 · Aday B — LightGBM çeyreklik `[PARALEL]`

```text
Aday B'yi uygula: gradyan artırmalı çeyreklik regresyon.
- 19 çeyrek (0.05…0.95) için pinball kayıplı LightGBM; girdiler: cinsiyet, yaş, kilo (ve türetilmiş log-kilo).
- Kiloda monotonluk kısıtı dene (beklenen kaldırış kiloyla azalmamalı); kısıtlı ve kısıtsız sürümleri karşılaştır.
- Çeyrek kesişmesini düzelt (izotonik yeniden sıralama); kesişme oranını raporla.
- 5–95 dışındaki kuyruklar için uç değer ekstrapolasyonu stratejisi (ör. log ölçekte doğrusal kuyruk); bunun
  zayıflığını açıkça belgeleyerek uygula.
- Çeyreklerden sürekli CDF'e enterpolasyon; ortak arabirime uyum.
- Model boyutunu ve tek çıkarım süresini ölç.
P049 koşumuyla değerlendir; A ile yan yana yüzdelik eğrisi grafikleri üret (basamaklılık görünür olsun).
```

Kabul: Aday B koşumdan geçiyor; kesişme oranı ve boyut ölçülmüş.

### P052 · Aday C — Sinirsel dağılımsal regresyon `[PARALEL]`

```text
Aday C'yi uygula: küçük bir MLP'nin dağılım parametrelerini tahmin ettiği model.
- Girdiler: cinsiyet (gömme veya one-hot), standartlaştırılmış yaş, log-kilo. Gövde: 2–3 gizli katman, pürüzsüz
  aktivasyon (ör. SiLU/tanh). Çıkış başlıkları: üç kaldırış için ayrı (μ, σ, ν, τ), P050'deki BCPE olabilirliğiyle;
  alternatif olarak sinh-arcsinh başlığını da dene.
- Ortak başlık: SBD üçlüsü tam kayıtlarda z-skorlarının koşullu korelasyon matrisi (Cholesky parametreli,
  Gauss kopula olabilirliği). docs/03-ML-MODEL.md §4.4.
- Düzenlileştirme: ağırlık azaltma, erken durdurma; pürüzsüzlük için girdi gradyanı cezası dene.
- Eğitim aralığının dışında (çok hafif/ağır, çok genç/yaşlı) çıktıların patlamadığını test et; girdileri eğitim
  aralığına kırpma kuralını tanımla (bu kural Swift tarafında da aynen uygulanacak).
- Parametre sayısı < 50 bin hedefi.
P049 koşumuyla değerlendir; A ve B ile aynı grafik seti.
```

Kabul: Aday C koşumdan geçiyor; korelasyon matrisi makul (pozitif, 0.4–0.9 aralığında beklenir) ve raporlanmış.

### P053 · Hiperparametre araması ve model yarışması `[ARAŞTIRMA]` `[PARALEL]`

```text
Model yarışmasını yürüt (docs/03-ML-MODEL.md §4.3 kriterleri DEĞİŞTİRİLEMEZ; önce onları reports/bakeoff.md'nin
başına kopyala, sonra deneylere başla):
- Optuna ile her aday için arama (A: düğüm sayıları, cezalar, dağılım ailesi; B: ağaç sayısı/derinlik/öğrenme oranı/
  yaprak; C: genişlik/derinlik/aktivasyon/ağırlık azaltma/öğrenme oranı/başlık türü). Amaç: doğrulama pinball kaybı;
  kalibrasyon kapısını ihlal eden denemeler budanır. Aday başına aynı deneme bütçesi.
- En iyi yapılandırmaları 3 farklı tohumla yeniden eğit; ortalama ± standart sapma raporla.
- Test kümesine yalnızca EN SONDA, her adayın tek bir nihai yapılandırmasıyla bak.
- Duyarlılık analizleri: Tested=Yes vs tümü; squat'ta wraps dahil/hariç; ağırlıklandırma açık/kapalı.
- reports/bakeoff.md: metrik tablosu, katman bazlı kalibrasyon ısı haritaları, akıl sağlığı testi sonuçları,
  boyut/hız, kazanan ve gerekçe, bilinen zayıflıklar.
Kazananı seçtikten sonra bana raporu özetle; ben onaylamadan P060'a geçilmez. MODEL_CARD.md'yi güncelle.
```

Kabul: Rapor önceden yazılmış kriterlere göre bir kazanan ilan ediyor; test kümesi yalnızca bir kez kullanılmış.

### P054 · 1RM modülü `[ARAŞTIRMA]` `[PARALEL]`

```text
docs/03-ML-MODEL.md §2'yi uygula (gymml/models/e1rm.py).
- Önce literatür: Epley, Brzycki, Lombardi, Mayhew, Wathan formüllerinin birincil kaynaklarını ve bunları
  karşılaştıran çalışmaları (ör. LeSuer 1997, Reynolds 2006 ve daha yeni doğrulama çalışmaları) bul; hareket ve
  tekrar aralığına göre bildirilen hataları reports/e1rm_literature.md'ye KAYNAĞIYLA yaz. Birincil kaynağını
  okuyamadığın hiçbir sayıyı rapora koyma.
- Aday eğri ailelerini tek arabirimde uygula; hepsinde f(1) = 1 koşulunu sağla (standart Epley bunu sağlamaz; düzelt).
- Literatürdeki tekrar–%1RM tablolarına hareket kategorisi bazında uydur; kategori parametrelerini params taslağına yaz.
- Güven ağırlığı c(r_eff) fonksiyonu ve RIR işleme (§2).
- Kendi kendini denetleyen kayıp (pencere içi log e1RM varyansı) için eğitim fonksiyonunu ŞİMDİ yaz ama yalnızca
  sentetik veriyle test et; gerçek veriyle P094'te çalışacak.
- Özellik testleri: e1RM ağırlıkta ve tekrarda artan; 1 tekrar → ağırlığın kendisi; 30+ tekrar → güven 0.
```

Kabul: Kategori parametreleri kaynaklı; özellik testleri geçiyor; sentetik veriyle kendi kendini denetleyen kayıp doğru parametreyi buluyor.

### P055 · Nüfus kalibrasyonu `[ARAŞTIRMA]` `[PARALEL]`

```text
docs/03-ML-MODEL.md §5 ve §7'yi uygula. Bu, modelin en kritik ve en belirsiz katmanı; titiz ol.
1. Çapa dosyası ml/data/anchors.csv: sütunlar population (gym|general), sex, lift, age_band, bodyweight_kg,
   percentile, value_kg, source_url, accessed, reliability (1–3), note.
   Kaynak türleri §5.2 tablosunda. Kurallar: kaynak başına az sayıda nokta al (tabloları toplu kopyalama);
   birincil kaynağını açıp okuyamadığın çapa dosyaya GİRMEZ; her satırda URL ve erişim tarihi zorunlu.
   Bulabildiğin ve bulamadığın çapa türlerini bana raporla.
2. Yer-ölçek modelini (δ, κ) ağırlıklı en küçük karelerle kestir; bootstrap ile parametre belirsizliği.
3. Birini dışarıda bırak doğrulaması: her kaynağı sırayla çıkar, kalanlarla kestir, çıkarılanı tahmin et.
4. Duyarlılık raporu: tipik bir kullanıcı için (ör. 80 kg erkek, 30 yaş, bench 80 kg) skorun kaynak seçimine göre
   ne kadar oynadığı → gerçek belirsizlik bandı (dokümandaki ±8–12 tahminini bu rakamla değiştir).
5. Boy/BMI düzeltmesi deneyi (§7): iyileşme göstermezse kapalı bırak ve nedenini yaz.
Çıktı: params taslağına calibration bölümü + reports/calibration.md. Sonucu onayıma sun.
```

Kabul: Her çapa kaynaklı; belirsizlik bandı ölçülmüş ve `03-ML-MODEL.md` güncellenmiş.

### P056 · Hareket oranları ve yük kuralları `[ARAŞTIRMA]` `[PARALEL]`

```text
tools/catalog/scoring_taxonomy.yaml içindeki çekirdek ~150 hareket için anchor, ratio (ρ), tau, ratio_confidence
ve bw_fraction alanlarını doldur (docs/03-ML-MODEL.md §6).
- Oran kaynakları: OpenPowerlifting'ten doğrudan hesaplanabilenler (squat:bench:deadlift), yayımlanmış standart
  tablolarından türetilenler, biyomekanik çalışmalar (ör. şınavda taşınan vücut ağırlığı oranı — birincil kaynağı
  bul), ve son çare olarak uzman tahmini. Her satıra kaynak ve güven derecesi (A/B/C) yaz.
- Yük kuralı tuzakları: dumbbell tek el ağırlığı; plaka yüklü makinede taraf başına; Smith makinesinde bar
  ağırlığı; kablo/makine → en fazla düşük güven.
- tau: A sınıfı için küçük, C sınıfı için büyük; C sınıfı hareketlerin uç skor verememesini bir testle doğrula.
- reps_only hareketler için yaş/cinsiyet tekrar normu tabloları (kaynaklı) → ml/data/rep_norms.csv.
- Tutarlılık denetimi: "ortalama" bir sporcu profili için tüm hareketlerin ima ettiği yükleri listele; bariz
  saçmalıkları (ör. biceps curl > bench) yakalayan test.
docs/CEKIRDEK-HAREKETLER.md'yi oranlarla güncelle ve incelememe sun. Kataloğu yeniden üret (P028 betiği).
```

Kabul: Çekirdek hareketlerin tümünde kaynaklı oran var; tutarlılık testi geçiyor.

### P057 · Uçtan uca referans uygulama ve birleştirme `[PARALEL]`

```text
Python'da tam skor hattının referans uygulamasını yaz (gymml/scoring.py); Swift tarafı bunun birebir kopyası olacak:
- score_set → e1RM + güven (P054).
- current_strength: docs/03-ML-MODEL.md §3 (42 gün penceresi, aykırı değer işareti, bayatlama, güven düzeyi).
- exercise_score: oran dönüşümü (§6) → çapa z-skoru (P053 kazananı) → kalibrasyon (P055) → yüzdelik; referans
  grubu parametresi; belirsizlik bandı; cinsiyet belirtilmemişse karışım (§4.5).
- aggregate: kas grubu ve genel skor, z uzayında korelasyon düzeltmeli (§8); kapsama kuralları ve "geçici skor"
  bayrağı; makine hareketlerinin düşük ağırlığı; seviye adları.
- Tüm sabitler params.json'dan okunur; kodda sihirli sayı yok.
Özellik testleri: tek hareketli grubun skoru o hareketin skoruna eşit; eşit iki skorun birleşimi aynı skor;
daha fazla ağırlık hiçbir skoru düşürmez; girdilerin sırası sonucu değiştirmez.
Örnek kullanıcı profilleriyle (yeni başlayan, orta, ileri; erkek/kadın) çıktı tablosu üret ve gözle doğrula.
```

Kabul: Özellik testleri geçiyor; örnek profillerin skorları sezgiyle uyumlu ve raporlanmış.

### P058 · Gelişim analitiği `[PARALEL]`

```text
docs/03-ML-MODEL.md §9'u Python referansı olarak uygula (gymml/progress.py):
- Eğilim: oturum e1RM serisinde Theil–Sen eğimi (8–12 hafta), aylık yüzde değişim ve güven aralığı; en az veri
  koşulu (ör. ≥ 4 oturum, ≥ 3 hafta).
- Beklenen gelişim eğrisi: seviyeye (yüzdelik) ve deneyime göre azalan-getiri eğrisi. Literatürden kaynaklı bir
  başlangıç eğrisi öner; kaynak bulamazsan bunu açıkça "varsayım" olarak etiketle ve params.json'da ayarlanabilir tut.
- Gelişim Skoru: gözlenen / beklenen oranının 0–100'e sınırlı, yorumlanabilir eşlemesi.
- Plato tespiti: CUSUM veya eşdeğeri; yeterli sıklık koşuluyla; yanlış alarmı sınırlayan eşikler.
- Tahmin: 4/8/12 hafta; belirsizlik bandı zamanla genişler; gerçekçi olmayan uzatmaları sınırla.
Sentetik serilerle test: bilinen eğim geri bulunur; gürültülü düz seri plato verir; tek aykırı değer eğilimi bozmaz.
```

Kabul: Sentetik testler geçiyor; varsayımlar açıkça etiketlenmiş.

### P059 · Dengesizlik analizi `[PARALEL]`

```text
docs/03-ML-MODEL.md §10'u Python referansı olarak uygula (gymml/imbalance.py):
- Koşullu beklenti: korelasyon matrisinden E[z_i | diğer z'ler] ve artığın standart sapması; |artık| > eşik ise
  bulgu üret (hangi kaldırış, ne yönde, ne kadar).
- Kural tabanlı oranlar: itiş/çekiş, üst/alt vücut, squat/deadlift, tek taraflı hareketlerde sol/sağ. Eşikleri
  params.json'da tut; her kuralın kaynağını veya "uzman varsayımı" olduğunu belgeye yaz.
- Güven: yalnızca orta/yüksek güvenli skorlardan bulgu üret; makine hareketlerinden üretme.
- Çıktı biçimi: makine tarafından okunur bulgu nesneleri (tür, şiddet, ilgili hareketler/kaslar, öneri anahtarı).
  Metin üretme; metinler uygulamada yerelleştirilmiş şablonlardan gelecek (P069).
Testler: dengeli profilde bulgu yok; kasıtlı zayıflatılmış bench bulgu üretir; düşük güvenli veride sessiz kalır.
```

Kabul: Testler geçiyor; bulgu nesnesi şeması belgelenmiş.

### P060 · Dışa aktarım: model paketi ve altın vektörler

```text
Model paketini üret (docs/03-ML-MODEL.md §11) — make export:
- Kazanan C ise coremltools ile anchor.mlpackage (ML Program, iOS 26 hedefi, float32; giriş/çıkış adları ve
  birimleri manifestte). Kazanan A ise anchor_tables.json (spline tabanı + katsayılar). Her iki durumda da
  PyTorch ↔ dışa aktarılan model farkını 2.000 rastgele girdide ölç (hedef < 1e-4).
- params.json (şema sürümlü): e1RM, kalibrasyon + belirsizlik, korelasyonlar, birleştirme, gelişim, dengesizlik,
  seviye eşikleri, girdi kırpma aralıkları. JSON Schema ile doğrula.
- taxonomy.json: katalogdan skorla ilgili alanlar.
- manifest.json: semver, şema sürümü, dosya SHA-256'ları, min uygulama sürümü, eğitim verisi özeti, metrik özeti.
- İmzalama: Ed25519. Anahtar üretme betiği; özel anahtar depoya GİRMEZ (nerede saklanacağını KURULUM.md'ye yaz),
  açık anahtar ios/ tarafına sabit olarak eklenir. manifest.sig üret ve doğrulama betiği yaz.
- Altın vektörler: ml/golden/ altında katman bazında (e1rm, anchor, calibration, exercise_score, aggregate,
  progress, imbalance) girdi→çıktı JSON'ları + sınır durumları.
```

Kabul: İmzalı paket üretildi ve doğrulanıyor; altın vektörler yazıldı; dönüşüm hatası hedefin altında.

### P061 · StrengthKit 1 — sayısal çekirdek

```text
StrengthKit'te skor matematiğinin Swift uygulamasını yaz (Linux'ta da derlenir, CoreML'siz):
- ModelParams: params.json ve taxonomy.json için Codable tipler; şema sürümü denetimi.
- E1RM: eğri ailesi, kategori parametreleri, RIR, güven ağırlığı. P040'taki geçici Epley'i bununla değiştir.
- Distributions: BCCG/BCPE (veya kazanan başlığın) CDF/ters CDF'i, normal CDF/ters CDF (yüksek doğruluklu yaklaşım).
- Calibration: yer-ölçek dönüşümü, referans grubu, belirsizlik bandı, cinsiyet karışımı.
- ExerciseScoring: yük kuralları (toplam, tek el, taraf başına, vücut ağırlığı + ek yük), oran dönüşümü, tau büzülmesi.
- CurrentStrength: 42 gün penceresi, aykırı değer işareti, bayatlama, güven düzeyi.
- Tüm tipler Sendable; girdiler doğrulanır, geçersiz girdi tipli hata döndürür (çökme yok).
ml/golden altın vektörlerini okuyan parametrik testler: 1e-4 tolerans. Çapa dağılımı bu adımda protokol
(AnchorDistribution) + altın vektörlerden beslenen test sahtesiyle temsil edilir.
```

Kabul: Altın vektör testleri macOS ve Linux'ta geçiyor.

### P062 · StrengthKit 2 — model çalıştırıcı, birleştirme, analitik

```text
StrengthKit'i tamamla:
- AnchorDistribution uygulamaları: CoreMLAnchorDistribution (#if canImport(CoreML); toplu tahmin; model bir kez
  yüklenir) ve TableAnchorDistribution (spline tabloları, saf Swift). Hangisinin kullanılacağını manifest belirler.
- ModelBundle: paketi diskten yükler; manifest imzasını (CryptoKit Curve25519) ve dosya özetlerini doğrular;
  şema/min sürüm uyumunu denetler; .mlpackage'ı gerekiyorsa cihazda derler ve derlenmiş hali önbelleğe alır.
- Aggregation: kas grubu ve genel skor, kapsama kuralları, seviye adları.
- Progress ve Imbalance: P058–P059'un Swift karşılıkları.
- ScoreEngine: P021'deki protokolün gerçek uygulaması; yer tutucu motoru sil.
- Uygulama paketine temel model paketini göm; ilk açılışta çevrimdışı çalışır.
Altın vektör testleri (aggregate, progress, imbalance, uçtan uca). Performans testi: 150 hareketli bir kullanıcının
tüm skorları < 50 ms. Kurcalanmış paketin reddedildiğini ve gömülü pakete düşüldüğünü test et.
```

Kabul: Uçtan uca altın vektörler geçiyor; kurcalanmış paket reddediliyor; performans hedefi tutuyor.

### P063 · Model güncelleme altyapısı

```text
Model paketinin buluttan güncellenmesini kur (docs/03-ML-MODEL.md §11 "Güncelleme"):
- Göç: model_versions (version, schema_version, min_app_version, storage_path, manifest_sha256, metrics jsonb,
  is_active, rollout_percent, released_at). Herkese açık okuma; yalnızca servis rolü yazar. "model-bundles" kovası.
- ml/ tarafında yayınlama betiği: paketi zip'le, yükle, satır ekle (varsayılan is_active=false).
- Uygulamada ModelUpdater: açılışta ve günde bir kontrol; uyumlu ve daha yeni etkin sürümü indir → imza/özet
  doğrula → altın vektör alt kümesiyle duman testi → atomik olarak etkinleştir. Başarısızlıkta mevcut paket korunur.
- rollout_percent: cihaza özgü kararlı özetle kademeli dağıtım. is_active=false olursa bir önceki sürüme dön.
- Model sürümü değişince skorlar yeniden hesaplanır (P064) ve fark kullanıcıya bir kez açıklanır.
Sahte depoyla testler: bozuk indirme, imza hatası, uyumsuz şema, geri alma.
```

Kabul: Yeni paket yayınlanınca uygulama güncelliyor; geri alma ve hata senaryoları testli.

---

## Faz 6 — Skor ve analiz arayüzü

### P064 · Skor orkestrasyonu

```text
Skorların ne zaman hesaplanıp nasıl saklanacağını kur (uygulama katmanı + DataKit):
- ScoreService: antrenman bitince, geçmiş düzenlenince, kilo/profil değişince, model sürümü değişince ilgili
  skorları yeniden hesaplar. Hesap arka plan aktöründe; arayüz @Observable durumdan beslenir.
- Artımlı hesap: yalnızca etkilenen hareketler ve onlara bağlı gruplar.
- ScoreSnapshot (SwiftData + score_snapshots göçü ve RLS + senkron): haftalık ve her anlamlı değişimde anlık görüntü;
  scope, key, reference_group, score, z, confidence, model_version. Zaman içi skor grafikleri buradan beslenir.
- Vücut ağırlığı kaynağı: en güncel ölçüm; 60 günden eskiyse "kilonu güncelle" nazik hatırlatması.
- Referans grubu tercihi (salon varsayılan) user_settings'te.
- Geçmişe dönük doldurma: ilk kurulumda mevcut geçmiş için haftalık anlık görüntüler üret.
Testler: düzenleme sonrası tutarlılık, artımlı = tam yeniden hesap eşitliği, model sürümü değişimi.
```

Kabul: Antrenman bitince skorlar güncelleniyor; artımlı ve tam hesap aynı sonucu veriyor.

### P065 · Hareket skoru ekranı

```text
Hareket detayındaki "Senin verin" bölümünü ve tam ekran skor görünümünü yaz:
- ScoreRing + seviye adı + tek cümle: "Senin yaşında ve kilondaki salon kullanıcılarının %73'ünden güçlüsün."
- "Dağılımda buradasın" grafiği (Swift Charts): referans nüfusun yoğunluk eğrisi, kullanıcının konumu, medyan
  ve seviye eşikleri işaretli; eksen kullanıcının biriminde.
- Referans grubu değiştirici: Salon kullanıcıları / Genel nüfus / Yarışmacı sporcular (anında yeniden hesap).
- Güven rozeti (yüksek/orta/düşük) ve dokununca neden: veri azlığı, yüksek tekrar, makine hareketi, bayat veri.
  Belirsizlik bandı grafikte gölge olarak.
- "Bir sonraki seviyeye": kaç kg/tekrar gerektiği (ters hesap).
- Dayanak: skoru belirleyen set, e1RM, tarih.
- Skorlanamayan hareketlerde açıklayıcı boş durum.
Ters hesabın doğruluğunu test et (hedef yükle skor gerçekten eşiği geçiyor).
```

Kabul: Ekran üç referans grubunda tutarlı; ters hesap testi geçiyor.

### P066 · Kas ısı haritası ve kas grubu skorları

```text
Analiz sekmesinde kas grubu görünümünü yaz:
- MuscleMapView ile ön/arka ısı haritası: renk = kas grubu skoru (seviye ölçeği); skoru olmayan kas nötr.
- Kasa dokununca detay sayfası: skor, katkı yapan hareketler (ağırlıklarıyla), son 4 haftadaki haftalık set sayısı,
  eğilim.
- Liste görünümü: kas grupları skora göre sıralı, en zayıf üç vurgulu.
- İkinci harita modu: "son 7 günde çalışma yükü" (set sayısına göre yoğunluk) — hangi kası ihmal ettiğini gösterir.
- Haftalık hacim hesabı: birincil kas 1 set, ikincil kas 0.5 set (kuralı docs/ANTRENMAN-MANTIGI.md'ye yaz).
- Erişilebilirlik: haritanın metin karşılığı (liste) VoiceOver'da varsayılan.
Hacim ve katkı hesaplarını test et.
```

Kabul: Isı haritası skorlarla renkleniyor; kas detayı doğru hareketleri listeliyor.

### P067 · Genel Güç Skoru panosu (Bugün sekmesi)

```text
Bugün sekmesini yaz — uygulamanın ana ekranı:
- Üstte büyük Genel Güç Skoru halkası, seviye adı, son 30 gün değişimi; "geçici skor" ise eksik hareket kalıpları
  ve "tamamlamak için şunu kaydet" yönlendirmesi.
- Hareket kalıbı çubukları (7 kalıp) mini skorlarla.
- "Bugünün antrenmanı" kartı: aktif programdaki sıradaki gün + başlat; program yoksa şablon önerisi.
- Öne çıkanlar: son rekor, en çok gelişen hareket, en önemli içgörü (P069).
- Haftalık hedef halkası (planlanan/yapılan antrenman) ve seri (streak).
- Yeni kullanıcı için boş durumlar: ilk antrenmanı kaydetmeye yönlendiren tek net eylem.
Tasarım: veri yoğun ama sakin; tek vurgu rengi; kartlar DesignSystem bileşenlerinden.
Durum eşlemesini (veri yok / geçici / tam) test et; TR/EN ve büyük yazı tipinde görsel kontrol.
```

Kabul: Üç durum da doğru; pano örnek veriyle anlamlı ve akıcı.

### P068 · Gelişim grafikleri

```text
Analiz sekmesinde gelişim görünümlerini yaz (Swift Charts):
- Hareket bazında e1RM zaman serisi: oturum noktaları, eğilim çizgisi, 4/8/12 hafta tahmin bandı (StrengthKit
  Progress), rekor işaretleri, plato bölgeleri gölgeli.
- Skor zaman serisi (ScoreSnapshot'tan): hareket, kas grubu veya genel.
- Hacim: haftalık toplam ve kas grubu bazında yığılmış sütun.
- Sıklık: takvim ısı haritası (son 6 ay).
- Vücut ağırlığı eğilimi ile göreli güç (e1RM / vücut ağırlığı) birlikte.
- Zaman aralığı seçici (1A/3A/6A/1Y/Tümü), grafikte parmakla değer okuma, birim farkındalığı.
- Gelişim Skoru kartı: "Seviyene göre beklenenden hızlı/yavaş gelişiyorsun" + açıklama.
Büyük veriyle performans: 2 yıllık örnek geçmişte akıcı kaydırma. Seri hazırlama fonksiyonlarını test et.
```

Kabul: Grafikler örnek veriyle doğru; tahmin bandı ve plato bölgeleri görünüyor.

### P069 · İçgörü motoru ve kartları

```text
İçgörü sistemini yaz:
- InsightEngine (uygulama katmanı): StrengthKit bulgularını (dengesizlik, plato, gelişim) ve basit kuralları
  (ihmal edilen kas grubu, itiş/çekiş hacim dengesizliği, uzun aradan sonra dönüş, kilo güncellenmemiş, tek tekrar
  aralığına sıkışma) toplar; öncelik puanı verir; aynı içgörüyü 14 gün tekrar göstermez; kapatılanı hatırlar.
- Her içgörü: tür, şiddet, ilgili varlıklar, yerelleştirilmiş başlık/gövde şablonu (parametreli), önerilen eylem
  (ör. "Programına bir çekiş hareketi ekle" → hareket önerileri; "Koça sor" → hazır mesajla koç sekmesi).
- Metinler String Catalog'da TR/EN; ton: yargılamayan, somut, tek eylemli.
- Arayüz: Bugün'de en önemli tek kart; Analiz'de tam liste ve geçmiş.
- İçgörüler koçun get_insights aracının da kaynağı olacak; bu yüzden sunucuyla eşitlenen sade bir tablo/alan tasarla.
Testler: önceliklendirme, tekrar bastırma, eşiklerin altında sessizlik.
```

Kabul: Kasıtlı dengesiz örnek veride doğru içgörü çıkıyor; tekrar bastırma çalışıyor.

### P070 · Haftalık özet

```text
Haftalık özet özelliği:
- Hafta bitiminde (kullanıcının yerel pazar akşamı; ayarlanabilir) üretilen özet: antrenman sayısı/hedef, toplam
  hacim ve değişim, kırılan rekorlar, skor değişimleri, en çok çalışılan/ihmal edilen kas, haftanın içgörüsü.
- Özet ekranı: kaydırmalı kısa "hikâye" kartları + sade liste görünümü. Geçmiş haftalara erişim.
- Yerel bildirim ile haber ver (izin varsa); bildirime dokununca özet açılır. BGAppRefreshTask ile hazırlama,
  olmazsa uygulama açılışında tembel üretim.
- Hiç antrenman yoksa suçlayıcı olmayan, kısa bir "yeniden başlama" mesajı.
- Koç yorumu için yer tutucu (P083'te dolacak).
Özet hesaplarını saf fonksiyon olarak yaz ve hafta sınırı/saat dilimi kenar durumlarını test et.
```

Kabul: Örnek veriyle özet doğru; saat dilimi testleri geçiyor.

### P071 · "Nasıl hesaplanıyor?" ekranı

```text
Şeffaflık ekranını yaz (Profil > Hakkında ve her skor ekranından erişilir):
- Sade dille 5 adım: setinden 1RM tahmini → güncel güç → benzer kişilerle karşılaştırma → nüfus ayarı → birleştirme.
  docs/03-ML-MODEL.md'nin kullanıcı dostu özeti; formül yok, küçük görsellerle.
- Referans grupları ne demek; hangisi en güvenilir ve neden.
- Güven düzeyleri ve skoru neyin belirsizleştirdiği.
- Sınırlar: tahmindir; sağlık ölçüsü değildir; makine hareketleri; teknik ve tam hareket açıklığı varsayımı.
- Veri kaynakları ve atıflar (OpenPowerlifting'e teşekkür, free-exercise-db, kas haritası kaynağı).
- Yüklü model sürümü, yayın tarihi, son güncelleme kontrolü.
- Sorumluluk reddi: tıbbi tavsiye değildir; yeni programa başlamadan önce sağlık durumunu değerlendir.
Metinler TR/EN. Metni yayın öncesi hukuk incelemesi listesine ekle (docs/YAYIN-KONTROL.md oluştur).
```

Kabul: Ekran iki dilde eksiksiz; model sürümü gerçek paketten okunuyor.
