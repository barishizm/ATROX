# 1RM tahmini — literatür ve kategori eğrileri (P054)

Kod: `gymml/models/e1rm.py` · Veri: `data/e1rm_rep_tables.csv` · Parametre taslağı: `params_draft/e1rm.json`
(`uv run python -m gymml.models.e1rm` yeniden üretir; `tests/test_e1rm.py` taslağın güncel olduğunu denetler).
Erişim tarihi (tüm kaynaklar): 2026-11-13.

**Kural:** Bu raporda yalnızca birincil kaynağı (tam metin ya da en azından yazarların kendi özeti) açılıp
okunan sayılar var. Okunamayan kaynaklar adıyla anılır, sayısı verilmez. "Özet" = yalnızca PubMed özeti okundu.

## 1. Formüllerin birincil kaynakları — erişilemedi

Epley (1985), Brzycki (1993, *JOPERD*), Lombardi (1989, kitap), Mayhew vd. (1992, *J Appl Sport Sci Res*) ve
Wathan (1994, NSCA kitabı) birincil kaynaklarının hiçbirine çevrim içi erişilemedi (PubMed'de dizinli değiller).
Bu yüzden formüllerin yaygın sabitleri bu raporda **bulgu olarak verilmez**. Kodda yalnızca aile biçimini ve
optimizasyonun başlangıç noktasını tanımlarlar (`FAMILIES[...].defaults`); skorlamada kullanılan bütün sayılar
§3'te literatür tablolarına **bizim uydurduğumuz** değerlerdir.

`f(1) = 1` koşulu: Brzycki (`(a + 1 − r)/a`) ve Lombardi (`r^−b`) bunu zaten sağlar. Standart Epley
(`w·(1 + r/k)`) 1 tekrarda `w·(1 + 1/k)` verir; `r − 1` ile düzeltildi ve böylece genel biçimin `p = 1` hali oldu.
Mayhew ve Wathan (`%1RM = A + B·e^(−c·r)`) 1 tekrarda %100 vermez; `f(r) = g(r)/g(1)` ile normalleştirildi.

## 2. Karşılaştırma ve doğrulama çalışmaları

Kod ve veri dosyasındaki kaynak anahtarları: `nuzzo2024`, `ferrari2017`, `hatfield2006`.

| Kaynak | Okunan | Hareket / örneklem | Bildirilen (birebir sayılar) |
|---|---|---|---|
| Nuzzo, Pinto, Nosaka, Steele 2024, *Sports Med* 54:303–321, [PMC10933212](https://pmc.ncbi.nlm.nih.gov/articles/PMC10933212) | Tam metin + Şekil 2–4 tabloları | 269 çalışma, 7289 kişi, 952 tükenişe-tekrar testi | Cinsiyet, yaş, antrenman durumu ilişkiyi az etkiliyor; hareket etkiliyor: leg press'te bench'ten daha çok tekrar. Bench %80/%70: 8.8 [GA 7.7–10.1] / 14.1 [12.4–16.1] tekrar; leg press %80/%70: 13.1 [9.8–17.5] / 19.0 [14.2–25.5]. Tablo değerleri `data/e1rm_rep_tables.csv`'de. |
| Ferrari, Kothe, Bottaro, Cadore, Kruel 2017, *Open Sports Sci J* 10:81, [tam metin](https://opensportssciencesjournal.com/VOLUME/10/PAGE/81/FULLTEXT/) | Tam metin + Tablo 2 | Bench, dumbbell row, triceps ext., elbow flexion; antrenmanlı/antrenmansız; %60/75/90; tempo 2 s/2 s metronom | Antrenman durumu fark yaratmadı; row %60 ve %75'te diğerlerinden anlamlı az tekrar (antrenmanlı: 13.8 ve 9.25 vs bench 15.5 ve 10.44). |
| Hatfield vd. 2006, *JSCR* 20(4):760–6, PMID 17194227 | Özet | Squat ve shoulder press, 9 antrenmanlı erkek, istemli hız | %60: squat 24 ± 2, SP 14 ± 2 tekrar; %80: squat 12 ± 1, SP 6 ± 1. |
| Shimano vd. 2006, *JSCR* 20(4):819–23, PMID 17194239 | Özet (sayı yok) | Squat, bench, arm curl; 8+8 erkek; %60/80/90 | %60'ta squat'ta bench ve curl'den daha çok tekrar; %80–90'da fark daha az belirgin; antrenman durumu etkisi minimal. |
| Reynolds, Gordon, Robergs 2006, *JSCR* 20(3):584–92, PMID 16937972 | Özet | Bench (CP) ve leg press (LP), 70 kişi, 1/5/10/20RM | Yük–tekrar ilişkisi doğrusal değil (CP doğrusal S(y.x) 2.6 kg, doğrusal olmayan 0.2 kg; LP 11.0 vs 2.6 kg). En iyi tahmin 5RM'den: R² LP 0.974/0.933/0.915, CP 0.993/0.976/0.955 (5/10/20RM). "Doğrusal denklemlerde 10'dan fazla tekrar kullanılmamalı." |
| Mayhew vd. 1995, *J Sports Med Phys Fitness* 35(2):108–13, PMID 7500624 | Özet | Bench, 220 erkek (7 grup) | Altı denklemin geçerlik katsayısı r = 0.82–0.98; ≤10 tekrarda üç denklem fazla, iki denklem eksik tahmin etti, Brzycki en doğru; >10 tekrarda üçü fazla, üçü eksik tahmin etti. |
| McNair, Colvin, Reid 2011, *Arthritis Care Res* 63(2):216–22, PMID 20890972 | Özet | Diz OA'lı 18 kişi; ~10 tekrar | Knee extension: Brown, Brzycki, Epley, Lander, Mayhew, Poliquin, Wathen en doğru; tipik hata %3–4. Leg press: Adams, Berger, Kemmler, O'Conner en doğru; tipik hata %5.9–6.3. |
| García-Ramos vd. 2019, *J Sports Sci* 37(19):2205–12, PMID 31164044 | Özet | Prone bench pull, 26 erkek | Lombardi ve O'Connor denklemleri 1RM'i %3.43–4.08 fazla tahmin etti; Lombardi CV %3.44. |
| Ribeiro Neto vd. 2017, *Spinal Cord* 55(10):950–6, PMID 28485383 | Özet | Bench, omurilik yaralanmalı 45 erkek, 4–12RM | Tüm denklemler 1RM testinden anlamlı farklı değil; Lombardi en iyi Bland–Altman (ortalama fark 0.5 kg, aralık 12.8 kg). |
| Nickerson vd. 2020, *JSCR* 34(9):2427–33, PMID 32740290 | Özet | Bench, 20 antrenmanlı kişi, %70'te tükenişe | Epley, Wathen ve Mayhew'dan daha küçük ortalama fark ve en düşük SEE verdi (sayı özette yok). |
| Marzagao 2026, arXiv [2603.17495](https://arxiv.org/abs/2603.17495) (hakemsiz ön baskı) | Özet | Uygulama verisi: 303,494 tükenişe yakın set, 14,966 kullanıcı, 388 hareket | Ölçülmüş 1RM yok; iç tutarlılık (aynı kişi farklı tekrar → aynı e1RM) ölçütüyle ağırlığa bağlı bir dönüşüm dört klasik denkleme göre tutarsızlığı %17–22 azalttı. Bizim §2 öz-denetimli kaybımızla aynı fikir; ağırlık bağımlılığı Faz 10'da değerlendirilebilir. |

**Erişilemeyen:** LeSuer vd. 1997 (*JSCR* 11(4):211–213; bench/squat/deadlift'te yedi denklem) ve Hoeger vd.
1987/1990 (*J Appl Sport Sci Res*; yedi hareket, %40/60/80) tam metinleri/özetleri açılamadı. İkincil kaynaklar
LeSuer'in deadlift 1RM'inin tüm denklemlerce eksik tahmin edildiğini aktarıyor; birincil kaynak okunmadığı için
sayısı buraya alınmadı ve deadlift için ayrı düzeltme yapılmadı (Ertelenenler).

**Literatürden çıkan özet:** (1) Hareket (özellikle alt/üst vücut, kas kütlesi) tekrar–%1RM ilişkisini değiştirir;
cinsiyet, yaş ve antrenman durumu zayıf düzenleyicilerdir (Nuzzo 2024, Shimano 2006, Ferrari 2017). (2) Hata
tekrar arttıkça büyür; ~10 tekrar üstünde denklemler sistematik sapar (Reynolds 2006, Mayhew 1995). (3) Tek bir
"en iyi" klasik denklem yok; kazanan hareket ve örnekleme göre değişiyor (McNair 2011, Ribeiro Neto 2017,
Nickerson 2020). Bu, kategori bazlı uydurulmuş eğri ve tekrar arttıkça düşen güven ağırlığı seçimini destekliyor.

## 3. Kategori eğrileri

**Veri kuralı.** Nuzzo 2024 meta-regresyonu, içerdiği hareketin kategorisinde tek referanstır (bench →
`upper_push`, leg press → `lower_compound`, tüm hareketler → `general`). Tek çalışmalar farklı tempo/protokol
kullanır: Ferrari 2017'nin metronomlu bench'i aynı %1RM'de Nuzzo bench'ten belirgin az tekrar verir
(%60: 15.5–16.07 vs 19.34). Bu yüzden Ferrari yalnızca **çalışma içi karşıtlık** olarak girer:
`tekrar_hareket × (Nuzzo bench / Ferrari bench)` aynı yük ve grupta. Varsayım: tempo etkisi hareketler arasında
oransaldır. Hatfield 2006 satırları uydurmaya girmez, çapraz denetimdir. Kapsam: ortalama tekrar ≤ 30.

**Ağırlık.** Kaynak içinde ters varyans (log tekrarın SE'si; %95 GA'dan ya da SD/√n'den, Hatfield'deki ± SD
kabul edildi). Kategori içinde her kaynağın toplam ağırlığı eşittir. Kayıp: `log f(r_gözlenen) − log %1RM`
(≈ göreli e1RM hatası).

**Aile karşılaştırması** (ağırlıklı log-RMSE ≈ göreli e1RM hatası; uydurulmuş parametreyle. Parantez içi:
yaygın sabitlerle — bu sabitlerin birincil kaynağı okunmadı, yalnızca kıyas için):

| Aile | lower_compound | upper_push | upper_pull | isolation | general |
|---|---|---|---|---|---|
| **genel (k, p)** | **0.007** (—) | **0.011** | **0.011** | **0.018** | **0.010** |
| Epley (düzeltilmiş) | 0.026 (0.113) | 0.021 (0.025) | 0.023 (0.051) | 0.021 (0.021) | 0.038 (0.039) |
| Brzycki | 0.014 (0.371) | 0.043 (0.195) | 0.017 (0.053) | 0.030 (0.156) | 0.022 (0.206) |
| Lombardi | 0.077 (0.088) | 0.094 (0.152) | 0.079 (0.144) | 0.077 (0.134) | 0.104 (0.169) |
| Mayhew (normalleştirilmiş) | 0.044 (0.053) | 0.068 (0.139) | 0.054 (0.149) | 0.049 (0.124) | 0.084 (0.149) |
| Wathan (normalleştirilmiş) | 0.034 (0.117) | 0.043 (0.043) | 0.036 (0.045) | 0.032 (0.033) | 0.060 (0.060) |

İki parametreli genel biçim her kategoride en iyi; params taslağına o yazıldı.

**Seçilen parametreler** `f(r) = 1 / (1 + ((r − 1)/k)^p)`:

| Kategori | k | p | RMSE | en büyük |hata| | nokta | kaynak | %90 / %80 / %70 / %60'ta tekrar |
|---|---|---|---|---|---|---|---|
| lower_compound | 34.47 | 1.323 | 0.007 | 0.044 | 8 | Nuzzo (leg press) | 7.5 / 13.1 / 19.2 / 26.4 |
| upper_push | 26.46 | 1.148 | 0.011 | 0.023 | 10 | Nuzzo (bench) | 4.9 / 8.9 / 13.6 / 19.6 |
| upper_pull | 22.66 | 1.220 | 0.011 | 0.027 | 6 | Ferrari karşıtlığı (row) | 4.7 / 8.3 / 12.3 / 17.3 |
| isolation | 27.72 | 1.115 | 0.018 | 0.031 | 12 | Ferrari karşıtlığı (triceps ext., elbow flexion) | 4.9 / 9.0 / 14.0 / 20.3 |
| general | 25.17 | 1.352 | 0.010 | 0.027 | 10 | Nuzzo (tüm hareketler) | 6.0 / 10.0 / 14.5 / 19.7 |

**Çapraz denetim (Hatfield 2006, uydurmaya girmedi):** back squat `lower_compound` eğrisine göre %60'ta +0.050,
%80'de +0.024 log fark → squat e1RM'i ~%2–5 düşük tahmin edilir (leg press makinede daha çok tekrar). Shoulder
press `upper_push` eğrisine göre %60'ta +0.145, %80'de +0.085 → OHP e1RM'i ~%8–14 düşük tahmin edilir; dikey
itiş için ayrı kategori gerekebilir (tek çalışma, n = 9; Ertelenenler).

## 4. Güven ağırlığı ve RIR (§2, değişmedi)

`r_eff = tekrar + RIR`. RIR girilmemişse 0 varsayılmaz: değer `r_eff = tekrar` ile hesaplanır (alt sınır), güven
×0.85. `c(r_eff)`: 1–5 → 1.0; 12'de 0.6; 20'de 0.25; 30 ve üstü → 0 (aralar doğrusal; 20–30 arası doğrusal
inişi biz seçtik — doküman yalnızca "30 üstü 0" diyor). Isınma setleri güven 0. Eğri değeri 30 tekrarda kırpılır.
Bu eşikler literatürden değil `03-ML-MODEL.md`'den gelir; §2 bulguları (>10 tekrarda büyüyen hata) yönünü destekler.

## 5. Kendi kendini denetleyen kayıp

`within_window_loss`: kullanıcı-hareket-pencere grubu içinde güven ağırlıklı `log e1RM` varyansı; tek setli gruplar
atlanır. `fit_self_supervised` sentetik veride (400 grup, %1 log gürültü) gerçek `(k, p)`'yi %10, Epley `k`'yi %5
içinde buluyor (testler). Gerçek veriyle P094'te çalışacak.

## 6. Sınırlar

- `upper_pull` tek çalışmanın tek hareketine (dumbbell row) dayanıyor; lat pulldown/barbell row verisi bulunamadı.
- `isolation` yalnızca üst vücut tek eklem (triceps, elbow flexion); knee extension/leg curl verisi okunamadı.
- Deadlift (`hip_hinge`) leg press eğrisini kullanıyor; doğrudan veri yok.
- Nuzzo leg press tablosunun yüksek yük uçları çok belirsiz (%95: GA 1.67–29.75); ters varyans ağırlığı bunları
  bastırıyor ama `lower_compound` eğrisinin 1–5 tekrar bölgesi en zayıf kısmı.
