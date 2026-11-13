# P055 — Nüfus kalibrasyonu raporu

> Otomatik üretildi: `make calibrate` (`gymml.calibration.run`). Elle düzenlemeyin; metin değişiklikleri `run.py` içindeki şablona yapılır.

## Özet

- **Salon referansı belirsizlik bandı:** tipik kullanıcılarda medyan **±8.3** yüzdelik puan (en kötü ±18.6).
- **Genel nüfus referansı:** medyan ±18.7, en kötü ±26.0 puan — çapası az ve dağınık; salon referansından belirgin şekilde daha belirsiz.
- Dokümandaki ±8–12 tahmini bu ölçümle değiştirildi (`docs/03-ML-MODEL.md` §5.3).
- Yarışmacı referansı: `p053-winner-A` (P057'den itibaren varsayılan P053 kazananı Spline-LMS; `--reference opl` ampirik OPL referansını kullanır). "OPL tümü" senaryosu ampirik tested+untested referansıyla karşılaştırır.
- BMI düzeltmesi: **kapalı** (aşağıda).

## Model

Log-kg ölçeğinde yer-ölçek (§5.1): `m_g = m_c − δ_g`, `s_g = κ_g · s_c`, skor `Φ((ln kg − m_c + δ) / (κ s_c))`. Parametrizasyon:

```
δ_g(cinsiyet, kaldırış, bant) = D_g(cinsiyet) + L(cinsiyet, kaldırış) + A_g(cinsiyet, bant)
κ_g (nüfus başına tek)
```

- `L` bench için 0 ve iki nüfusta ortak (genel nüfusta deadlift çapası yok; kaldırışlar arası fark salon çapalarından öğrenilir).
- `A` referans bantta (20-39) 0. Yaş ofsetleri yaşa göreli çapalardan (Strength Level yaş tabloları, NHANES el kavrama) ve Cooper yaş bantlarından gelir.
- Tahmin parametrelerde doğrusal → ağırlıklı en küçük kareler; ağırlık = reliability / √(kaynağın satır sayısı); nominal çapa hatası σ₀ = 0.05 log. Zayıf önseller: A ~ N(0, 0.5²), κ ~ N(1, 1²), D, L ~ N(0, 2²) — yalnızca çapası olmayan hücreleri tanımlı tutar.
- Yaşa göreli çapa (VA'sı olmayan satır): aynı kaynak/cinsiyet/kaldırış/yüzdeliğin 20-39 satırına log farkı, yarışmacının aynı farkıyla karşılaştırılır. El kavrama gücü için yarışmacı farkı üç kaldırışın ortalamasıdır (varsayım: genel nüfusta kaldırış gücü yaşla el kavrama gücüyle aynı oranda düşer).
- `age_band = all` olan tablolar (Strength Level vücut ağırlığı tabloları) 20-39 kabul edilir.

## Çapa dosyası

`ml/data/anchors.csv`: 98 satır, 7 kaynak. Her satırda URL ve erişim tarihi var; tüm kaynaklar açılıp okundu (2026-11-13).

| Kaynak | Nüfus | Satır | Güven | Ne alındı |
|---|---|---|---|---|
| [StrengthLevel-bench](https://strengthlevel.com/strength-standards/bench-press/kg) | gym | 22 | 2 | VA tablosu (80 kg erkek 5 seviye; 60/100/120 kg medyan; kadın 60 kg 5/50/95, 80 kg medyan) + yaş tablosu medyanları |
| [StrengthLevel-squat](https://strengthlevel.com/strength-standards/squat/kg) | gym | 22 | 2 | aynı desen |
| [StrengthLevel-deadlift](https://strengthlevel.com/strength-standards/deadlift/kg) | gym | 22 | 2 | aynı desen |
| [Cooper(ACE)](https://www.acefitness.org/images/webcontent/assets/certification/ace-answers/forms/pt/38_Bench-Press_Assessment_Protocol.pdf) | general | 12 | 1/2 | 1RM bench / VA oran normları (Cooper Institute, ACE'nin izinli yeniden basımı); VA varsayımı E 85 / K 68 kg |
| [FernandezOrtega2022](https://pmc.ncbi.nlm.nih.gov/articles/PMC9180020/) | general | 6 | 1/2 | kuvvet antrenmanı yapmayan aktif öğrenciler, ort ± SS → log-normal |
| [Stratton2024](https://pmc.ncbi.nlm.nih.gov/articles/PMC11679921/) | gym | 2 | 1 | direnç antrenmanlı yetişkinler (n=12+12), ort → medyan |
| [Perna2016-NHANES-grip](https://pmc.ncbi.nlm.nih.gov/articles/PMC7197498/) | general | 12 | 3 | NHANES 2011-12 el kavrama medyanları, yalnızca yaş şekli |

### Bulunan ve bulunamayan çapa türleri (§5.2)

- **Yayımlanmış salon standartları — bulundu:** Strength Level (seviye = 5/20/50/80/95. yüzdelik). Kendi kullanıcılarının girdiği kaldırışlardan türetilmiş; kullanıcı kitlesi salon nüfusundan güçlü tarafa yanlı olabilir (gönüllü kayıt). Yaş tabloları VA'dan bağımsız tek tablo — yaş eğrisi büyük olasılıkla modelden türetilmiş, ham veri değil.
- **Akademik salon kohortları — kısmen:** yalnızca küçük, giriş eşiğiyle kesilmiş örneklemler bulundu. Stratton 2024 (n=24, bench ≥ 0.85/0.4 × VA) güven 1 ile alındı. Macarilla 2022 (n=17, bench ≥ 1.25 × VA ve squat ≥ 1.5 × VA) salon medyanına yakın bir eşikle kesildiği için **alınmadı**. Büyük, kesilmemiş bir "düzenli salon kullanıcısı" 1RM kohortu bulunamadı.
- **Nüfus normları — kısmen:** Cooper Institute bench/VA normları (ACE'nin izinli yeniden basımı; asıl monografa erişilemedi). Kadın tablosunun sütunları düzensiz (60+ "Superior" > 50-59) → güven 1. Leg press normları alınmadı (çapa hareketi değil). Squat/deadlift için nüfus normu bulunamadı. Genç, antrenmansız aktif yetişkin kohortu (Fernandez Ortega 2022, n=355) genel nüfus çapası olarak alındı; tam (derin) squat güç kaldırma derinliği değildir → squat satırları güven 1.
- **Yaş eğrisi — bulundu:** NHANES 2011-12 el kavrama (Perna 2016). Ham değerler lb, kg'ye çevrildi.
- **Bulunamayan / kullanılmayan:** ikincil derleme siteleri (fitnessnorms vb.) birincil kaynak olmadığı için alınmadı; CDC vücut ölçüleri sayfası erişimi reddetti (Cooper VA varsayımı bu yüzden kaynaksız bir varsayım olarak duyarlılıkta ±10 kg oynatıldı); van den Hoek 2024 yarışmacı nüfusudur — P053 akıl sağlığı testinde kullanılır, kalibrasyon çapası değildir.

## Kestirim sonucu

Ağırlıklı ortalama kare artık: 0.0082 (log², σ₀ birimsiz). Bootstrap: kaynak içinde tabakalı satır yeniden örneklemesi, B = 500.

| Nüfus | Cinsiyet | κ (5–95%) | δ bench 20-39 (5–95%) | δ squat 20-39 | δ deadlift 20-39 |
|---|---|---|---|---|---|
| gym | M | 1.95 (1.73–2.10) | 0.244 (0.194–0.297) | 0.366 | 0.332 |
| gym | F | 1.95 (1.73–2.10) | 0.195 (0.111–0.281) | 0.476 | 0.434 |
| general | M | 1.25 (0.75–1.78) | 0.550 (0.474–0.628) | 0.672 | 0.639 |
| general | F | 1.25 (0.75–1.78) | 0.526 (0.378–0.611) | 0.807 | 0.765 |

δ = 0.25 → salon medyanı yarışmacı medyanının e^−0.25 ≈ %78'i. κ > 1 → salon nüfusu yarışmacılardan daha geniş yayılır (beklenen: yarışmacılar seçilmiş, homojen bir uçtur).

Yaş ofsetleri A (δ'ya eklenir; pozitif = o yaşta yarışmacılara göre daha fazla düşüş):

| Nüfus | Cinsiyet | 40-49 | 50-59 | 60-69 | 70+ |
|---|---|---|---|---|---|
| gym | M | -0.029 | +0.041 | +0.096 | +0.071 |
| gym | F | -0.030 | +0.020 | +0.065 | +0.044 |
| general | M | -0.034 | -0.026 | -0.100 | -0.226 |
| general | F | -0.081 | -0.097 | -0.196 | -0.201 |

Not: salon (Strength Level) yaş tabloları yarışmacılardan daha dik, genel nüfus (el kavrama) daha yatık bir düşüş ima ediyor. Yaşlı yarışmacılar seçilmiş güçlü bir gruptur, bu yüzden genel nüfus için bu yön beklenir; salon yönü Strength Level'ın yaş çarpanlarından gelir ve tek kaynaklıdır.

## Birini dışarıda bırak (kaynak bazında)

Her kaynak çıkarılır, kalanlarla kestirilir, çıkarılan kaynağın mutlak çapalarının yüzdeliği tahmin edilir (hata = tahmin − yayımlanan yüzdelik). Yaşa göreli çapalar için log hatası.

| Çıkarılan kaynak | Satır | Ort. mutlak yüzdelik hatası | log RMSE |
|---|---|---|---|
| Stratton2024 | 2 | 0.8 | 0.009 |
| Perna2016-NHANES-grip | 8 | — (göreli) | 0.143 |
| FernandezOrtega2022 | 6 | 28.9 | 0.283 |
| StrengthLevel-bench | 20 | 8.2 | 0.129 |
| StrengthLevel-deadlift | 20 | 10.9 | 0.145 |
| StrengthLevel-squat | 20 | 22.4 | 0.259 |
| Cooper(ACE) | 12 | 19.8 | 0.243 |

Tüm kaynaklar üzerinden ortalama mutlak yüzdelik hatası: **16.3** puan. Yorum: tek kaynağın taşıdığı parametreler (ör. squat'ın kaldırış farkı yalnızca Strength Level-squat'tan, genel nüfus bench seviyesi Cooper ile Fernandez Ortega arasında) o kaynak çıkınca önsele düşer — büyük hatalar kaynak sayısının azlığını gösterir, bir kaynağın "yanlış" olduğunu değil. Bu yüzden bant LOSO kestirimlerini de kapsar.

## Duyarlılık: tipik kullanıcılar

Senaryolar: temel; her kaynağın çıkarılması (7); eşit ağırlık; yalnız reliability ağırlığı; yarışmacı referansı olarak tüm OPL (tested + untested); Cooper VA varsayımı ±10 kg; bootstrap 5–95%. Bant = bu zarfın yarı genişliği.

| Kullanıcı | Nüfus | Temel skor | Bootstrap 5–95 | En düşük (senaryo) | En yüksek (senaryo) | ± |
|---|---|---|---|---|---|---|
| Erkek 30 y, 80 kg, bench 80 | gym | 25.9 | 21.2–31.1 | 18.4 (−StrengthLevel-bench) | 28.2 (−StrengthLevel-squat) | 6.4 |
| Erkek 30 y, 80 kg, bench 80 | general | 65.5 | 51.6–86.3 | 49.1 (−FernandezOrtega2022) | 87.2 (−Cooper(ACE)) | 19.0 |
| Erkek 30 y, 80 kg, squat 100 | gym | 23.0 | 17.5–28.8 | 20.8 (−FernandezOrtega2022) | 49.8 (−StrengthLevel-squat) | 16.1 |
| Erkek 30 y, 80 kg, squat 100 | general | 60.1 | 37.4–80.7 | 36.8 (−FernandezOrtega2022) | 88.8 (−StrengthLevel-squat) | 26.0 |
| Erkek 30 y, 80 kg, deadlift 140 | gym | 36.3 | 28.6–42.4 | 25.2 (−StrengthLevel-deadlift) | 37.1 (OPL tümü (tested+untested)) | 8.6 |
| Erkek 30 y, 80 kg, deadlift 140 | general | 86.0 | 66.4–99.0 | 66.4 (−FernandezOrtega2022) | 97.9 (−Cooper(ACE)) | 16.3 |
| Erkek 50 y, 90 kg, bench 90 | gym | 48.4 | 42.5–54.1 | 38.3 (−StrengthLevel-bench) | 51.9 (−StrengthLevel-squat) | 7.9 |
| Erkek 50 y, 90 kg, bench 90 | general | 81.2 | 67.1–96.0 | 71.8 (−FernandezOrtega2022) | 92.2 (−Cooper(ACE)) | 14.4 |
| Kadın 30 y, 65 kg, bench 40 | gym | 30.8 | 22.7–38.1 | 24.1 (−StrengthLevel-bench) | 34.1 (−StrengthLevel-squat) | 7.7 |
| Kadın 30 y, 65 kg, bench 40 | general | 65.1 | 44.8–80.5 | 47.6 (−FernandezOrtega2022) | 86.3 (−Cooper(ACE)) | 20.7 |
| Kadın 30 y, 65 kg, squat 70 | gym | 51.7 | 41.4–60.9 | 46.3 (−FernandezOrtega2022) | 78.6 (−StrengthLevel-squat) | 18.6 |
| Kadın 30 y, 65 kg, squat 70 | general | 90.9 | 62.3–99.2 | 66.6 (−FernandezOrtega2022) | 98.5 (−StrengthLevel-squat) | 18.5 |

Karşılaştırma: aynı kullanıcı (Erkek 30 y, 80 kg, bench 80) yarışmacı referansında 0.4. yüzdelikte.

## Boy / BMI düzeltmesi deneyi (§7)

`bw_eff = 25·h² + β·(bw − 25·h²)` (BMI > 25 ise). Çapaların hiçbirinde bireysel boy yok; deney varsayılan boylarla yapıldı. Ölçütler: ağırlıklı RSS ve LOSO ortalama mutlak yüzdelik hatası.

| Varyant | Ağırlıklı RSS | LOSO MAE (puan) |
|---|---|---|
| düzeltme yok | 0.0082 | 16.3 |
| varsayılan boy 177/164, β=0.5 | 0.0100 | 17.4 |
| varsayılan boy 177/164, β=0.25 | 0.0115 | 18.2 |
| FO boyu 170.5/158.2, β=0.5 | 0.0107 | 18.4 |
| FO boyu 170.5/158.2, β=0.25 | 0.0128 | 19.8 |

Vekil kontrol: Strength Level erkek medyan satırlarında yüzdelik hatası VA'ya göre (ağır kullanıcılarda sistematik sapma BMI etkisine işaret ederdi):

| Kaldırış | VA | Hata (puan) |
|---|---|---|
| bench | 60 | -13.3 |
| bench | 80 | -2.0 |
| bench | 100 | +4.9 |
| bench | 120 | +12.0 |
| deadlift | 60 | -11.7 |
| deadlift | 80 | -0.2 |
| deadlift | 100 | +11.2 |
| deadlift | 120 | +22.4 |
| squat | 60 | -5.3 |
| squat | 80 | +3.2 |
| squat | 100 | +11.5 |
| squat | 120 | +18.5 |

**Sonuç: kapalı.** Düzeltme RSS'i ve LOSO hatasını iyileştirmedi, tersine kötüleştirdi. Nedenleri: (1) çapalar bireysel boy taşımıyor (yalnızca varsayılan boy) ve yarışmacı verisinde de boy yok; (2) vekil tablo düzeltmenin varsaydığının tersini gösteriyor — Strength Level'da ağır kullanıcıların medyanı yarışmacı VA eğrisinin öngördüğünden *yüksek* (hata VA ile artıyor); BMI düzeltmesi ağır kullanıcının etkin VA'sını düşürüp bu farkı büyütür. Bu eğim tek kaynaklıdır (Strength Level'ın kendi tablo modeli olabilir). Boy toplanmaya devam eder; v2'de uygulama verisiyle (boy × e1RM) yeniden denenir (`bmi_correction.enabled = false`).

## Sınırlar

- Çapa sayısı az ve kaynaklar heterojen; özellikle genel nüfus ve kadın tarafı zayıf.
- Strength Level kullanıcıları salon nüfusunun güçlü tarafına yanlı olabilir → salon skorları muhtemelen olması gerekenden biraz düşük.
- κ nüfus başına tek değer (cinsiyet/kaldırış başına değil; ayrı kestirimde genel nüfus kadın κ'sı tanımsız kaldı); yaşa ve VA'ya göre ölçek değişimi yalnızca yarışmacı ölçeğinden gelir.
- δ VA'ya bağlı değil (§5.1). Strength Level satırları yarışmacılardan daha dik bir VA eğimi ima ediyor (BMI bölümündeki vekil tablo): 60 kg'da skor fazla, 120 kg'da az tahmin ediliyor olabilir. δ'ya bir log-VA terimi eklemek model biçimini değiştirir → kullanıcı kararına bırakıldı (ILERLEME Ertelenenler).
- Yarışmacı referansı ampirik hücre çeyrekleridir; uç kuyruk şekli log-normal varsayımıyla (z = (ln y − m_c)/s_c) yaklaşıklanır. P053 modeli takılınca yeniden kestirilmelidir.
- Faz 10'da uygulama verisi bu δ/κ'yı önsel olarak kullanıp Bayesçi günceller (§12).
