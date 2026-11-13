# Tekrar normları (`rep_norms.csv`, P056)

`reps_only` çekirdek hareketlerin yüzdeliği yayımlanmış yaş/cinsiyet tekrar normlarından enterpolasyonla bulunur
(docs/03-ML-MODEL.md §6). Skor her zaman "düşük güven" etiketlidir. Tablolar toplu kopyalanmadı: kaynak başına yaş
bandı × cinsiyet başına 4–5 nokta alındı.

| Sütun | Anlam |
|---|---|
| `test` | Norm testinin adı |
| `exercise_ids` | Normun uygulandığı katalog kimlikleri (`;` ile ayrılır) |
| `sex` | `M` / `F` |
| `age_min`, `age_max` | Yaş bandı (dahil; `99` = üst sınır yok) |
| `percentile` | Yüzdelik (0–100) |
| `reps` | O yüzdeliğe karşılık gelen tekrar sayısı |
| `protocol` | Testin yapılış biçimi (aşağıda) |
| `source` | Aşağıdaki kaynak anahtarı |

## Kaynaklar

### `csep_path_2019` — şınav

Canadian Society for Exercise Physiology (2019). *CSEP Physical Activity Training for Health (CSEP-PATH) Resource
Manual* (2nd ed.). Ottawa: CSEP. Tablonun izinli yeniden basımından okundu: American Council on Exercise, "Push-up
Assessment Protocol" (2020), <https://contentcdn.eacefitness.com/assets/certification/ace-answers/forms/pt/36_Push-up_Assessment_Protocol.pdf>,
erişim 2026-11-13. Normların dayandığı veri: Payne N, Gledhill N, Katzmarzyk PT, Jamnik V, Keir PJ. Canadian
musculoskeletal fitness norms. *Can J Appl Physiol* 2000;25(6):430-42.

- Protokol: tükenene kadar, ara vermeden; erkekler standart şınav (`standard`), **kadınlar dizler yerde**
  (`modified_knee`). Kadın kullanıcının standart şınavı bu normla doğrudan karşılaştırılamaz: P057 bu satırları
  kadınların standart şınavı için yalnızca üst sınır (iyimser) olarak kullanmalı ya da skoru göstermemelidir.
- CSEP beş kategori verir (Geliştirilmeli / Orta / İyi / Çok iyi / Mükemmel); yüzdelik vermez. Kategori alt
  sınırları beşte birlik dilimler varsayılarak 20/40/60/80. yüzdeliğe yazıldı (Payne vd. 2000 kategorileri yaş ve
  cinsiyet içi yüzdeliklerden kurar). Bu bir varsayımdır.

### `ymca_2000` — mekik (curl-up)

YMCA of the USA (2000). *YMCA Fitness Testing and Assessment Manual* (4th ed.). Champaign, IL: Human Kinetics.
Tablonun izinli yeniden basımından okundu: American Council on Exercise, "ACE Group Fitness Instructor Fitness
Assessment Protocols", Tablo 4–5, <https://www.acefitness.org/groupfitnessresources/pdfs/GFI_Assessments.pdf>, erişim
2026-11-13. Yüzdelikler kaynakta doğrudan verilir; 10/25/50/75/90. yüzdelikler alındı.

- Protokol (`curl_up_to_fatigue`): sırtüstü, dizler 90°, kollar göğüste çapraz; kürek kemikleri yerden kalkacak
  kadar (~30°) gövde bükülür, tükenene kadar. Katalogdaki `crunches` ile eşleştirildi.

## Normu olmayan çekirdek `reps_only` hareketler

`ab-roller`, `barbell-ab-rollout`, `bodyweight-squat`, `flat-bench-lying-leg-raise`, `hanging-leg-raise`,
`oblique-crunches`, `push-ups-with-feet-elevated`, `reverse-crunch`, `russian-twist`, `sit-up`: güvenilir ve
erişilebilir bir yaş/cinsiyet normu bulunamadı. Bu hareketler kaydedilir ve gelişim grafiği gösterir, yüzdelik skor
üretmez (docs/ILERLEME.md "Ertelenenler").
