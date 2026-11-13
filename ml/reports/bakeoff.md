# Model yarışması (P053)

Bu dosyanın ilk iki bölümü **deneylere başlamadan önce** yazıldı ve commit edildi (ön kayıt). Sonuçlar §3'ten
itibaren `make tune` / `make bakeoff` çıktısıyla eklenir.

## 1. Seçim kriterleri (docs/03-ML-MODEL.md §4.3, birebir kopya)

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

## 2. Deney protokolü (ön kayıt)

- **Veri:** P048 kohortu, referans `tested = true`, `wraps = false`, ters-frekans ağırlıklar; P049 bölmesi
  (sporcu bazlı %70/15/15, tohum 20260101). Arama ve tohum tekrarları yalnızca **doğrulama** kümesinde.
- **Arama:** Optuna TPE (örnekleyici tohumu 20260101), aday başına **aynı bütçe: 10 deneme**, her deneme üç
  kaldırışı eğitir. Amaç: üç kaldırışın doğrulama pinball ortalaması (kg). Kalibrasyon kapısını (§1 madde 2)
  herhangi bir kaldırışta ihlal eden deneme budanır; B için 1 MB'ı aşan deneme de budanır (madde 4). Bir adayın
  bütün denemeleri budanırsa en düşük pinball'lu denemesi "kapıyı geçemedi" notuyla raporlanır.
- **Arama uzayları:**
  - A (Spline-LMS): aile {BCCG, BCPE}, yaş düğüm aralığı 6–16, kilo düğüm aralığı 5–12, μ cezası 1e-4–1e-1,
    σ cezası 1e-3–1, ν ve τ cezası 1e-2–10 (log ölçek; yaş ve kilo yönünde aynı katsayı).
  - B (LightGBM): ağaç sayısı 50–400, yaprak 4–31, öğrenme oranı 0.03–0.3, yaprakta en az örnek 100–2000,
    monotonluk kısıtı {açık, kapalı}.
  - C (sinirsel): genişlik {32, 48, 64, 96}, derinlik {2, 3}, aktivasyon {silu, tanh}, ağırlık azaltma
    1e-6–1e-2, öğrenme oranı 1e-3–1e-2, başlık {bcpe, shash}.
- **Tohum tekrarı:** her adayın en iyi yapılandırması 3 tohumla (1, 2, 3) yeniden eğitilir; doğrulama
  metrikleri ortalama ± standart sapma.
- **Test kümesi:** her aday için tek nihai yapılandırma, 3 tohum modeli test kümesinde **bir kez** ölçülür
  (kod bir kilit dosyasıyla ikinci bakışı reddeder). Seçim §1'e göre test sonuçlarıyla yapılır.
- **Duyarlılık (doğrulama, tohum 1):** Tested=Yes yerine tüm veri; squat'ta wraps dahil; ağırlıklandırma kapalı.
  vdH ±%3 ölçütü kullanıcı onayı gereği ağırlıklandırması kapalı sürümle karşılaştırılır.
- **Ön kayıt değişikliği (2026-11-13):** ilk arama koşumu A ve C'nin bütün denemelerini 10 kg'lık bantlarda
  budadı; kök neden kilo sınıfı dişiydi. Kullanıcı onayıyla katmanlar kilo sınıflarına çevrildi ve arama
  **sıfırdan** yeniden başlatıldı; ilk koşumun sonuçları seçimde kullanılmadı ve test kümesine bakılmadı.
- **Akıl sağlığı testleri** (`gymml.eval.sanity`) nihai modellerde; yaş sıçrama sınırı 20+ yaş (onay
  2026-11-13, deneylerden önce).
