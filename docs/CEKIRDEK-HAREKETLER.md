# Çekirdek hareketler (P025, oranlar P056)

Güç Skoru'nun ilk sürümde hedeflediği ~150 hareket ve her birinin çapa oranı. Bu liste **onayını bekliyor**:
kalıp/tür/yük kuralı değişiklikleri `tools/catalog/taxonomy_overrides.yaml`, oran/kaynak/güven değişiklikleri
`tools/catalog/ratios.yaml` içine yazılır; ardından `cd tools/catalog && uv run catalog-taxonomy` bu dosyayı ve
`scoring_taxonomy.yaml`'ı yeniden üretir, `uv run catalog-build` kataloğu.

- Çekirdek hareket sayısı: **155** (katalogda toplam 876)
- Çapa oranı olan (skorlanan) çekirdek hareket: **142** — güven A: 4, B: 6, C: 132
- Kuralla atanıp **belirsiz** işaretlenen çekirdek satır: **15** (aşağıda ⚠ ile)
- Tür: `weighted` = ağırlıklı, `bodyweight_loaded` = vücut ağırlığı + ek yük, `reps_only` = yalnızca tekrar
  (`ml/data/rep_norms.csv`), `time` = süre, `none` = skorlanmaz. Çekirdek dışı hareketler skor üretmez.

## Oranlar nasıl okunur

- **ρ (oran):** kullanıcının bu harekette *yazdığı* sayının 1RM'i ≈ ρ × çapa hareketin 1RM'i. Yazılan sayı yük
  kuralına göredir: `el başına` = tek dambıl, `taraf başına` = makinenin bir tarafındaki plakalar (kızak
  eklenmez), `toplam` = bar dahil (Smith makinesinde Smith barı dahil), `vücut ağırlığı + ek yük` = efektif
  yük `bw × vücut ağırlığı + ek yük`.
- **τ:** oranın kişiden kişiye log ölçekte yayılımı. Çapanın kendisi 0.02, A 0.08, B 0.15, C 0.4, makine/kablo 0.5 (satır özel değer verebilir).
  Ölçek: OpenPowerlifting'te log(bench/squat) kişiler arası SS ≈ 0,15.
- **Güven:** A = birden çok uyumlu birincil kaynak, B = tek birincil kaynak ya da A/B kaynakların çarpımı,
  C = uzman tahmini. Makine ve kablo hareketleri en fazla C alır.
- **C sınıfı uç skor veremez:** `s_max = 0.25` iken |z| = 3.0 bile [5, 95] aralığında kalır (test: `tests/test_ratios.py`).
- **Ört. E / Ört. K:** örnek ortalama sporcu için ima edilen 1RM, yazılan birimde (kg). erkek, 80 kg: squat 125, bench 90, deadlift 150; kadın, 62 kg: squat 80, bench 45, deadlift 100. Vücut ağırlığı hareketlerinde ek yük (eksi = yardım gerekir).

## Kalıba göre dağılım

| Kalıp | Adet |
|---|---|
| yatay itiş (`horizontal_push`) | 15 |
| izolasyon-biceps (`isolation_biceps`) | 15 |
| dikey itiş (`vertical_push`) | 15 |
| gövde (`core`) | 14 |
| squat (`squat`) | 14 |
| izolasyon-triceps (`isolation_triceps`) | 12 |
| kalça menteşesi (`hip_hinge`) | 11 |
| yatay çekiş (`horizontal_pull`) | 11 |
| izolasyon-omuz (`isolation_shoulders`) | 9 |
| dikey çekiş (`vertical_pull`) | 9 |
| izolasyon-göğüs (`isolation_chest`) | 7 |
| izolasyon-baldır (`isolation_calves`) | 5 |
| izolasyon-arka bacak (`isolation_hamstrings`) | 4 |
| olimpik kaldırış (`olympic`) | 4 |
| izolasyon-sırt/trapez (`isolation_back`) | 3 |
| izolasyon-önkol (`isolation_forearms`) | 3 |
| izolasyon-kalça yanı/iç (`isolation_hips`) | 2 |
| taşıma (`carry`) | 1 |
| izolasyon-ön bacak (`isolation_quads`) | 1 |

## Çekirdek liste

| # | Ad | Kalıp | Tür | Yük kuralı | Tek taraflı | Çapa | ρ | τ | Güven | bw | Ört. E | Ört. K | Kaynak | Not |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 59 | Farmer's Walk | taşıma | weighted | el başına | hayır | deadlift | 0.4 | 0.4 | C | — | 60 | 40 | expert | Per hand. |
| 1 | Ab Crunch Machine | gövde | weighted | makine/kablo ağırlığı | hayır | deadlift | 0.35 | 0.5 | C | — | 52 | 35 | expert |  |
| 2 | Ab Roller | gövde | reps_only | — | hayır | — | — | — | — | — | — | — | — |  |
| 5 | Barbell Ab Rollout | gövde | reps_only | — | hayır | — | — | — | — | — | — | — | — |  |
| 15 | Barbell Side Bend | gövde | weighted | toplam (bar dahil) | hayır | deadlift | 0.35 | 0.4 | C | — | 52 | 35 | expert |  |
| 26 | Cable Crunch | gövde | weighted | makine/kablo ağırlığı | hayır | deadlift | 0.4 | 0.5 | C | — | 60 | 40 | expert |  |
| 38 | Crunches | gövde | reps_only | — | hayır | — | — | — | — | — | — | — | — |  |
| 60 | Flat Bench Lying Leg Raise | gövde | reps_only | — | hayır | — | — | — | — | — | — | — | — |  |
| 69 | Hanging Leg Raise | gövde | reps_only | — | hayır | — | — | — | — | — | — | — | — | ⚠ ambiguous name pattern: hanging |
| 92 | Oblique Crunches | gövde | reps_only | — | hayır | — | — | — | — | — | — | — | — |  |
| 96 | Pallof Press | gövde | weighted | makine/kablo ağırlığı | hayır | deadlift | 0.15 | 0.5 | C | — | 22 | 15 | expert |  |
| 100 | Plank | gövde | time | — | hayır | — | — | — | — | — | — | — | — |  |
| 109 | Reverse Crunch | gövde | reps_only | — | hayır | — | — | — | — | — | — | — | — |  |
| 115 | Russian Twist | gövde | reps_only | — | hayır | — | — | — | — | — | — | — | — |  |
| 124 | Sit-Up | gövde | reps_only | — | hayır | — | — | — | — | — | — | — | — |  |
| 8 | Barbell Deadlift | kalça menteşesi | weighted | toplam (bar dahil) | hayır | deadlift | 1 | 0.02 | A | — | 150 | 100 | anchor |  |
| 10 | Barbell Hip Thrust | kalça menteşesi | weighted | toplam (bar dahil) | hayır | deadlift | 1 | 0.4 | C | — | 150 | 100 | expert |  |
| 65 | Good Morning | kalça menteşesi | weighted | toplam (bar dahil) | hayır | deadlift | 0.4 | 0.4 | C | — | 60 | 40 | expert |  |
| 71 | Hyperextensions (Back Extensions) | kalça menteşesi | bodyweight_loaded | vücut ağırlığı + ek yük | hayır | deadlift | 0.55 | 0.4 | C | 0.6 | 34 | 18 | deleva1996, expert | bw_fraction = head + trunk + arms (≈ 60%, de Leva); ratio is an expert estimate. |
| 94 | One-Arm Kettlebell Swings | kalça menteşesi | weighted | toplam (bar dahil) | evet | deadlift | 0.17 | 0.4 | C | — | 26 | 17 | expert | Ballistic; loads limited by available bell sizes. |
| 107 | Rack Pulls | kalça menteşesi | weighted | toplam (bar dahil) | hayır | deadlift | 1.15 | 0.4 | C | — | 172 | 115 | expert | Pin at/below knee. |
| 114 | Romanian Deadlift | kalça menteşesi | weighted | toplam (bar dahil) | hayır | deadlift | 0.75 | 0.4 | C | — | 112 | 75 | expert |  |
| 138 | Stiff-Legged Barbell Deadlift | kalça menteşesi | weighted | toplam (bar dahil) | hayır | deadlift | 0.7 | 0.4 | C | — | 105 | 70 | expert |  |
| 139 | Stiff-Legged Dumbbell Deadlift | kalça menteşesi | weighted | el başına | hayır | deadlift | 0.3 | 0.4 | C | — | 45 | 30 | expert | Per hand. |
| 141 | Sumo Deadlift | kalça menteşesi | weighted | toplam (bar dahil) | hayır | deadlift | 1 | 0.1 | B | — | 150 | 100 | opl | OPL mixes sumo and conventional pulls in one deadlift column; stance preference adds spread. |
| 145 | Trap Bar Deadlift | kalça menteşesi | weighted | toplam (bar dahil) | hayır | deadlift | 1.1 | 0.08 | A | — | 165 | 110 | swinton2011, lockie2018 | 1.08 (powerlifters) and 1.15 (trained, high handles); total incl. the bar. |
| 19 | Bent Over Barbell Row | yatay çekiş | weighted | toplam (bar dahil) | hayır | bench | 0.8 | 0.4 | C | — | 72 | 36 | expert |  |
| 21 | Bent Over Two-Dumbbell Row | yatay çekiş | weighted | el başına | hayır | bench | 0.32 | 0.4 | C | — | 29 | 14 | expert | Per hand. |
| 49 | Dumbbell Incline Row | yatay çekiş | weighted | el başına | hayır | bench | 0.33 | 0.4 | C | — | 30 | 15 | expert | Per hand. |
| 76 | Inverted Row | yatay çekiş | bodyweight_loaded | vücut ağırlığı + ek yük | hayır | bench | 0.8 | 0.4 | C | 0.65 | 20 | -4 | suprak2011, expert | ⚠ equipment missing in source bw_fraction by analogy with the push-up (feet on the floor, body straight). |
| 80 | Leverage High Row | yatay çekiş | weighted | makine/kablo ağırlığı | hayır | bench | 0.8 | 0.5 | C | — | 72 | 36 | expert |  |
| 81 | Leverage Iso Row | yatay çekiş | weighted | makine/kablo ağırlığı | hayır | bench | 0.45 | 0.5 | C | — | 40 | 20 | expert |  |
| 86 | Lying T-Bar Row | yatay çekiş | weighted | taraf başına (plaka) | hayır | bench | 0.35 | 0.5 | C | — | 31 | 16 | expert | ⚠ plate-loaded machine assumed (`per_side`); confirm loading convention Per side plates. |
| 93 | One-Arm Dumbbell Row | yatay çekiş | weighted | el başına | evet | bench | 0.4 | 0.4 | C | — | 36 | 18 | expert | Per hand (one dumbbell). |
| 111 | Reverse Grip Bent-Over Rows | yatay çekiş | weighted | toplam (bar dahil) | hayır | bench | 0.78 | 0.4 | C | — | 70 | 35 | expert |  |
| 117 | Seated Cable Rows | yatay çekiş | weighted | makine/kablo ağırlığı | hayır | bench | 0.8 | 0.5 | C | — | 72 | 36 | expert |  |
| 142 | T-Bar Row with Handle | yatay çekiş | weighted | toplam (bar dahil) | hayır | bench | 0.7 | 0.4 | C | — | 63 | 31 | expert | Total incl. the bar. |
| 6 | Barbell Bench Press - Medium Grip | yatay itiş | weighted | toplam (bar dahil) | hayır | bench | 1 | 0.02 | A | — | 90 | 45 | anchor |  |
| 11 | Barbell Incline Bench Press - Medium Grip | yatay itiş | weighted | toplam (bar dahil) | hayır | bench | 0.76 | 0.15 | B | — | 68 | 34 | rodriguezridao2020 | 0.78 at 30°, 0.71 at 45°; gym benches sit between. |
| 24 | Cable Chest Press | yatay itiş | weighted | makine/kablo ağırlığı | hayır | bench | 0.5 | 0.5 | C | — | 45 | 22 | expert |  |
| 34 | Close-Grip Barbell Bench Press | yatay itiş | weighted | toplam (bar dahil) | hayır | bench | 0.92 | 0.15 | B | — | 83 | 41 | larsen2021 | Narrow grip 0.95 of medium in the study; gym close grip is narrower. |
| 39 | Decline Barbell Bench Press | yatay itiş | weighted | toplam (bar dahil) | hayır | bench | 1.03 | 0.4 | C | — | 93 | 46 | expert |  |
| 40 | Decline Dumbbell Bench Press | yatay itiş | weighted | el başına | hayır | bench | 0.43 | 0.4 | C | — | 39 | 19 | expert | Per hand. |
| 46 | Dumbbell Bench Press | yatay itiş | weighted | el başına | hayır | bench | 0.415 | 0.15 | B | — | 37 | 19 | saeterbakken2011 | Pair = 0.83 × barbell, per hand half of that. |
| 75 | Incline Dumbbell Press | yatay itiş | weighted | el başına | hayır | bench | 0.32 | 0.15 | B | — | 29 | 14 | saeterbakken2011, rodriguezridao2020 | Product of the dumbbell (0.415) and incline (0.76) factors. |
| 79 | Leverage Chest Press | yatay itiş | weighted | makine/kablo ağırlığı | hayır | bench | 0.9 | 0.5 | C | — | 81 | 40 | expert |  |
| 87 | Machine Bench Press | yatay itiş | weighted | makine/kablo ağırlığı | hayır | bench | 0.9 | 0.5 | C | — | 81 | 40 | expert |  |
| 105 | Push-Ups With Feet Elevated | yatay itiş | reps_only | — | hayır | — | — | — | B | 0.72 | — | — | ebben2011 | reps_only. |
| 106 | Pushups | yatay itiş | reps_only | — | hayır | — | — | — | A | 0.7 | — | — | suprak2011, ebben2011 | reps_only; 0.64–0.75 of body mass across studies and positions. |
| 125 | Smith Machine Bench Press | yatay itiş | weighted | toplam (bar dahil) | hayır | bench | 0.93 | 0.5 | C | — | 84 | 42 | saeterbakken2011, cotterman2005 | ⚠ ambiguous name pattern: smith; smith machine: bar is counterbalanced, so `total` may overstate the load 0.97 and ≈0.88–0.92 in the two studies; total incl. the Smith bar; capped at C as a machine. |
| 126 | Smith Machine Incline Bench Press | yatay itiş | weighted | toplam (bar dahil) | hayır | bench | 0.72 | 0.5 | C | — | 65 | 32 | cotterman2005, rodriguezridao2020 | ⚠ ambiguous name pattern: smith; smith machine: bar is counterbalanced, so `total` may overstate the load |
| 153 | Wide-Grip Barbell Bench Press | yatay itiş | weighted | toplam (bar dahil) | hayır | bench | 1 | 0.15 | B | — | 90 | 45 | larsen2021 |  |
| 14 | Barbell Shrug | izolasyon-sırt/trapez | weighted | toplam (bar dahil) | hayır | deadlift | 0.85 | 0.4 | C | — | 128 | 85 | expert |  |
| 55 | Dumbbell Shrug | izolasyon-sırt/trapez | weighted | el başına | hayır | deadlift | 0.3 | 0.4 | C | — | 45 | 30 | expert | Per hand. |
| 140 | Straight-Arm Pulldown | izolasyon-sırt/trapez | weighted | makine/kablo ağırlığı | hayır | bench | 0.35 | 0.5 | C | — | 31 | 16 | expert |  |
| 7 | Barbell Curl | izolasyon-biceps | weighted | toplam (bar dahil) | hayır | bench | 0.5 | 0.4 | C | — | 45 | 22 | expert |  |
| 36 | Concentration Curls | izolasyon-biceps | weighted | el başına | evet | bench | 0.2 | 0.4 | C | — | 18 | 9 | expert | Per hand. |
| 37 | Cross Body Hammer Curl | izolasyon-biceps | weighted | el başına | evet | bench | 0.23 | 0.4 | C | — | 21 | 10 | expert | Per hand. |
| 45 | Dumbbell Alternate Bicep Curl | izolasyon-biceps | weighted | el başına | evet | bench | 0.23 | 0.4 | C | — | 21 | 10 | expert | Per hand. |
| 47 | Dumbbell Bicep Curl | izolasyon-biceps | weighted | el başına | hayır | bench | 0.22 | 0.4 | C | — | 20 | 10 | expert | Per hand. |
| 57 | EZ-Bar Curl | izolasyon-biceps | weighted | toplam (bar dahil) | hayır | bench | 0.48 | 0.4 | C | — | 43 | 22 | expert |  |
| 67 | Hammer Curls | izolasyon-biceps | weighted | el başına | hayır | bench | 0.24 | 0.4 | C | — | 22 | 11 | expert | Per hand. |
| 70 | High Cable Curls | izolasyon-biceps | weighted | makine/kablo ağırlığı | hayır | bench | 0.2 | 0.5 | C | — | 18 | 9 | expert |  |
| 73 | Incline Dumbbell Curl | izolasyon-biceps | weighted | el başına | hayır | bench | 0.19 | 0.4 | C | — | 17 | 9 | expert | Per hand. |
| 88 | Machine Bicep Curl | izolasyon-biceps | weighted | makine/kablo ağırlığı | hayır | bench | 0.45 | 0.5 | C | — | 40 | 20 | expert |  |
| 89 | Machine Preacher Curls | izolasyon-biceps | weighted | makine/kablo ağırlığı | hayır | bench | 0.4 | 0.5 | C | — | 36 | 18 | expert |  |
| 102 | Preacher Curl | izolasyon-biceps | weighted | toplam (bar dahil) | hayır | bench | 0.42 | 0.4 | C | — | 38 | 19 | expert |  |
| 108 | Reverse Barbell Curl | izolasyon-biceps | weighted | toplam (bar dahil) | hayır | bench | 0.4 | 0.4 | C | — | 36 | 18 | expert |  |
| 131 | Standing Biceps Cable Curl | izolasyon-biceps | weighted | makine/kablo ağırlığı | hayır | bench | 0.45 | 0.5 | C | — | 40 | 20 | expert |  |
| 155 | Zottman Curl | izolasyon-biceps | weighted | el başına | hayır | bench | 0.18 | 0.4 | C | — | 16 | 8 | expert | Per hand. |
| 31 | Calf Press On The Leg Press Machine | izolasyon-baldır | weighted | taraf başına (plaka) | hayır | squat | 0.7 | 0.5 | C | — | 88 | 56 | expert | ⚠ plate-loaded machine assumed (`per_side`); confirm loading convention Per side plates. |
| 44 | Donkey Calf Raises | izolasyon-baldır | weighted | toplam (bar dahil) | hayır | squat | 0.8 | 0.4 | C | — | 100 | 64 | expert |  |
| 118 | Seated Calf Raise | izolasyon-baldır | weighted | makine/kablo ağırlığı | hayır | squat | 0.55 | 0.5 | C | — | 69 | 44 | expert |  |
| 130 | Standing Barbell Calf Raise | izolasyon-baldır | weighted | toplam (bar dahil) | hayır | squat | 0.8 | 0.4 | C | — | 100 | 64 | expert |  |
| 132 | Standing Calf Raises | izolasyon-baldır | weighted | makine/kablo ağırlığı | hayır | squat | 1 | 0.5 | C | — | 125 | 80 | expert |  |
| 18 | Bent-Arm Dumbbell Pullover | izolasyon-göğüs | weighted | toplam (bar dahil) | hayır | bench | 0.35 | 0.4 | C | — | 31 | 16 | expert | One dumbbell held with both hands → total. |
| 23 | Butterfly | izolasyon-göğüs | weighted | makine/kablo ağırlığı | hayır | bench | 0.7 | 0.5 | C | — | 63 | 31 | expert |  |
| 25 | Cable Crossover | izolasyon-göğüs | weighted | makine/kablo ağırlığı | hayır | bench | 0.25 | 0.5 | C | — | 22 | 11 | expert |  |
| 48 | Dumbbell Flyes | izolasyon-göğüs | weighted | el başına | hayır | bench | 0.22 | 0.4 | C | — | 20 | 10 | expert | Per hand. |
| 72 | Incline Cable Flye | izolasyon-göğüs | weighted | makine/kablo ağırlığı | hayır | bench | 0.22 | 0.5 | C | — | 20 | 10 | expert |  |
| 74 | Incline Dumbbell Flyes | izolasyon-göğüs | weighted | el başına | hayır | bench | 0.2 | 0.4 | C | — | 18 | 9 | expert | Per hand. |
| 83 | Low Cable Crossover | izolasyon-göğüs | weighted | makine/kablo ağırlığı | hayır | bench | 0.22 | 0.5 | C | — | 20 | 10 | expert |  |
| 97 | Palms-Down Wrist Curl Over A Bench | izolasyon-önkol | weighted | toplam (bar dahil) | hayır | bench | 0.25 | 0.4 | C | — | 22 | 11 | expert |  |
| 98 | Palms-Up Barbell Wrist Curl Over A Bench | izolasyon-önkol | weighted | toplam (bar dahil) | hayır | bench | 0.4 | 0.4 | C | — | 36 | 18 | expert |  |
| 119 | Seated Dumbbell Palms-Up Wrist Curl | izolasyon-önkol | weighted | el başına | hayır | bench | 0.18 | 0.4 | C | — | 16 | 8 | expert | Per hand. |
| 63 | Glute Ham Raise | izolasyon-arka bacak | bodyweight_loaded | vücut ağırlığı + ek yük | hayır | squat | 0.6 | 0.5 | C | 0.88 | 5 | -7 | deleva1996, expert | Body above the knees (de Leva); hinge at the knee makes the ratio a rough estimate. |
| 85 | Lying Leg Curls | izolasyon-arka bacak | weighted | makine/kablo ağırlığı | hayır | squat | 0.4 | 0.5 | C | — | 50 | 32 | expert |  |
| 121 | Seated Leg Curl | izolasyon-arka bacak | weighted | makine/kablo ağırlığı | hayır | squat | 0.45 | 0.5 | C | — | 56 | 36 | expert |  |
| 135 | Standing Leg Curl | izolasyon-arka bacak | weighted | makine/kablo ağırlığı | hayır | squat | 0.2 | 0.5 | C | — | 25 | 16 | expert | One leg. |
| 143 | Thigh Abductor | izolasyon-kalça yanı/iç | weighted | makine/kablo ağırlığı | hayır | squat | 0.55 | 0.5 | C | — | 69 | 44 | expert |  |
| 144 | Thigh Adductor | izolasyon-kalça yanı/iç | weighted | makine/kablo ağırlığı | hayır | squat | 0.55 | 0.5 | C | — | 69 | 44 | expert |  |
| 77 | Leg Extensions | izolasyon-ön bacak | weighted | makine/kablo ağırlığı | hayır | squat | 0.6 | 0.5 | C | — | 75 | 48 | expert |  |
| 20 | Bent Over Low-Pulley Side Lateral | izolasyon-omuz | weighted | makine/kablo ağırlığı | hayır | bench | 0.1 | 0.5 | C | — | 9 | 4 | expert |  |
| 28 | Cable Rear Delt Fly | izolasyon-omuz | weighted | makine/kablo ağırlığı | hayır | bench | 0.12 | 0.5 | C | — | 11 | 5 | expert |  |
| 30 | Cable Seated Lateral Raise | izolasyon-omuz | weighted | makine/kablo ağırlığı | hayır | bench | 0.1 | 0.5 | C | — | 9 | 4 | expert |  |
| 58 | Face Pull | izolasyon-omuz | weighted | makine/kablo ağırlığı | hayır | bench | 0.3 | 0.5 | C | — | 27 | 14 | expert |  |
| 62 | Front Two-Dumbbell Raise | izolasyon-omuz | weighted | el başına | hayır | bench | 0.14 | 0.4 | C | — | 13 | 6 | expert | Per hand. |
| 110 | Reverse Flyes | izolasyon-omuz | weighted | el başına | hayır | bench | 0.12 | 0.4 | C | — | 11 | 5 | expert | Per hand. |
| 113 | Reverse Machine Flyes | izolasyon-omuz | weighted | makine/kablo ağırlığı | hayır | bench | 0.45 | 0.5 | C | — | 40 | 20 | expert |  |
| 122 | Seated Side Lateral Raise | izolasyon-omuz | weighted | el başına | hayır | bench | 0.13 | 0.4 | C | — | 12 | 6 | expert | Per hand. |
| 123 | Side Lateral Raise | izolasyon-omuz | weighted | el başına | hayır | bench | 0.14 | 0.4 | C | — | 13 | 6 | expert | Per hand. |
| 27 | Cable One Arm Tricep Extension | izolasyon-triceps | weighted | makine/kablo ağırlığı | evet | bench | 0.18 | 0.5 | C | — | 16 | 8 | expert |  |
| 29 | Cable Rope Overhead Triceps Extension | izolasyon-triceps | weighted | makine/kablo ağırlığı | hayır | bench | 0.42 | 0.5 | C | — | 38 | 19 | expert |  |
| 52 | Dumbbell One-Arm Triceps Extension | izolasyon-triceps | weighted | el başına | evet | bench | 0.12 | 0.4 | C | — | 11 | 5 | expert | Per hand. |
| 84 | Lying Dumbbell Tricep Extension | izolasyon-triceps | weighted | el başına | hayır | bench | 0.15 | 0.4 | C | — | 14 | 7 | expert | Per hand. |
| 91 | Machine Triceps Extension | izolasyon-triceps | weighted | makine/kablo ağırlığı | hayır | bench | 0.5 | 0.5 | C | — | 45 | 22 | expert |  |
| 112 | Reverse Grip Triceps Pushdown | izolasyon-triceps | weighted | makine/kablo ağırlığı | hayır | bench | 0.38 | 0.5 | C | — | 34 | 17 | expert |  |
| 134 | Standing Dumbbell Triceps Extension | izolasyon-triceps | weighted | toplam (bar dahil) | hayır | bench | 0.3 | 0.4 | C | — | 27 | 14 | expert | One dumbbell held with both hands → total. |
| 137 | Standing Overhead Barbell Triceps Extension | izolasyon-triceps | weighted | toplam (bar dahil) | hayır | bench | 0.4 | 0.4 | C | — | 36 | 18 | expert |  |
| 146 | Tricep Dumbbell Kickback | izolasyon-triceps | weighted | el başına | evet | bench | 0.1 | 0.4 | C | — | 9 | 4 | expert | Per hand. |
| 147 | Triceps Pushdown | izolasyon-triceps | weighted | makine/kablo ağırlığı | hayır | bench | 0.5 | 0.5 | C | — | 45 | 22 | expert |  |
| 148 | Triceps Pushdown - Rope Attachment | izolasyon-triceps | weighted | makine/kablo ağırlığı | hayır | bench | 0.42 | 0.5 | C | — | 38 | 19 | expert |  |
| 149 | Triceps Pushdown - V-Bar Attachment | izolasyon-triceps | weighted | makine/kablo ağırlığı | hayır | bench | 0.52 | 0.5 | C | — | 47 | 23 | expert |  |
| 33 | Clean and Jerk | olimpik kaldırış | weighted | toplam (bar dahil) | hayır | squat | 0.65 | 0.4 | C | — | 81 | 52 | expert |  |
| 68 | Hang Clean | olimpik kaldırış | weighted | toplam (bar dahil) | hayır | squat | 0.58 | 0.4 | C | — | 72 | 46 | expert |  |
| 101 | Power Clean | olimpik kaldırış | weighted | toplam (bar dahil) | hayır | squat | 0.6 | 0.4 | C | — | 75 | 48 | expert |  |
| 128 | Snatch | olimpik kaldırış | weighted | toplam (bar dahil) | hayır | squat | 0.5 | 0.4 | C | — | 62 | 40 | expert |  |
| 9 | Barbell Full Squat | squat | weighted | toplam (bar dahil) | hayır | squat | 1 | 0.02 | A | — | 125 | 80 | anchor |  |
| 12 | Barbell Lunge | squat | weighted | toplam (bar dahil) | evet | squat | 0.55 | 0.4 | C | — | 69 | 44 | expert |  |
| 16 | Barbell Step Ups | squat | weighted | toplam (bar dahil) | evet | squat | 0.45 | 0.4 | C | — | 56 | 36 | expert | ⚠ ambiguous name pattern: step_up |
| 17 | Barbell Walking Lunge | squat | weighted | toplam (bar dahil) | evet | squat | 0.5 | 0.4 | C | — | 62 | 40 | expert |  |
| 22 | Bodyweight Squat | squat | reps_only | — | hayır | — | — | — | B | 0.88 | — | — | deleva1996 | ⚠ bodyweight exercise outside the push-up/sit-up families treated as reps_only reps_only; body minus both shanks and feet (1 − 2·(4.33+1.37)%). |
| 50 | Dumbbell Lunges | squat | weighted | el başına | evet | squat | 0.27 | 0.4 | C | — | 34 | 22 | expert | Per hand. |
| 53 | Dumbbell Rear Lunge | squat | weighted | el başına | evet | squat | 0.27 | 0.4 | C | — | 34 | 22 | expert | Per hand. |
| 56 | Dumbbell Squat | squat | weighted | el başına | hayır | squat | 0.3 | 0.4 | C | — | 38 | 24 | expert | Per hand; grip-limited. |
| 61 | Front Barbell Squat | squat | weighted | toplam (bar dahil) | hayır | squat | 0.82 | 0.4 | C | — | 102 | 66 | expert | Coaching rule of thumb 80–90% of back squat; no primary 1RM comparison found. |
| 64 | Goblet Squat | squat | weighted | toplam (bar dahil) | hayır | squat | 0.28 | 0.4 | C | — | 35 | 22 | expert | Limited by holding one implement. |
| 66 | Hack Squat | squat | weighted | taraf başına (plaka) | hayır | squat | 0.45 | 0.5 | C | — | 56 | 36 | expert | ⚠ plate-loaded machine assumed (`per_side`); confirm loading convention Per side plates; carriage not added. |
| 78 | Leg Press | squat | weighted | taraf başına (plaka) | hayır | squat | 0.85 | 0.5 | C | — | 106 | 68 | expert | ⚠ plate-loaded machine assumed (`per_side`); confirm loading convention Per side plates; sled weight and angle vary by machine. |
| 127 | Smith Machine Squat | squat | weighted | toplam (bar dahil) | hayır | squat | 1 | 0.5 | C | — | 125 | 80 | cotterman2005 | ⚠ ambiguous name pattern: smith; smith machine: bar is counterbalanced, so `total` may overstate the load Total incl. the Smith bar (7–25 kg depending on machine); capped at C as a machine. |
| 129 | Split Squat with Dumbbells | squat | weighted | el başına | evet | squat | 0.3 | 0.4 | C | — | 38 | 24 | expert | Per hand. |
| 4 | Band Assisted Pull-Up | dikey çekiş | bodyweight_loaded | vücut ağırlığı + ek yük | hayır | bench | 1.15 | 0.5 | C | 0.7 | 47 | 8 | expert | Band assistance is not logged; assumes a typical 30% assist. |
| 32 | Chin-Up | dikey çekiş | bodyweight_loaded | vücut ağırlığı + ek yük | hayır | bench | 1.2 | 0.4 | C | 1 | 28 | -8 | expert |  |
| 35 | Close-Grip Front Lat Pulldown | dikey çekiş | weighted | makine/kablo ağırlığı | hayır | bench | 0.75 | 0.5 | C | — | 68 | 34 | expert |  |
| 95 | One Arm Lat Pulldown | dikey çekiş | weighted | makine/kablo ağırlığı | evet | bench | 0.4 | 0.5 | C | — | 36 | 18 | expert |  |
| 103 | Pullups | dikey çekiş | bodyweight_loaded | vücut ağırlığı + ek yük | hayır | bench | 1.15 | 0.4 | C | 1 | 23 | -10 | expert | Whole body hangs from the bar; ratio expert. |
| 150 | Underhand Cable Pulldowns | dikey çekiş | weighted | makine/kablo ağırlığı | hayır | bench | 0.78 | 0.5 | C | — | 70 | 35 | expert |  |
| 151 | Upright Barbell Row | dikey çekiş | weighted | toplam (bar dahil) | hayır | bench | 0.45 | 0.4 | C | — | 40 | 20 | expert | ⚠ ambiguous name pattern: upright_row |
| 152 | V-Bar Pulldown | dikey çekiş | weighted | makine/kablo ağırlığı | hayır | bench | 0.78 | 0.5 | C | — | 70 | 35 | expert |  |
| 154 | Wide-Grip Lat Pulldown | dikey çekiş | weighted | makine/kablo ağırlığı | hayır | bench | 0.75 | 0.5 | C | — | 68 | 34 | expert |  |
| 3 | Arnold Dumbbell Press | dikey itiş | weighted | el başına | hayır | bench | 0.29 | 0.4 | C | — | 26 | 13 | expert | Per hand. |
| 13 | Barbell Shoulder Press | dikey itiş | weighted | toplam (bar dahil) | hayır | bench | 0.66 | 0.4 | C | — | 59 | 30 | expert | Seated. |
| 41 | Dip Machine | dikey itiş | weighted | makine/kablo ağırlığı | hayır | bench | 1 | 0.5 | C | — | 90 | 45 | expert |  |
| 42 | Dips - Chest Version | dikey itiş | bodyweight_loaded | vücut ağırlığı + ek yük | hayır | bench | 1.3 | 0.4 | C | 0.95 | 41 | -0 | deleva1996, expert | ⚠ Dips load chest and triceps together; filed under vertical push (hands travel past the torso). Confirm. bw_fraction = body minus hands and forearms (de Leva); ratio expert. |
| 43 | Dips - Triceps Version | dikey itiş | bodyweight_loaded | vücut ağırlığı + ek yük | hayır | bench | 1.25 | 0.4 | C | 0.95 | 36 | -3 | deleva1996, expert | ⚠ Same movement as the chest version with a more upright torso; filed under vertical push. Confirm. |
| 51 | Dumbbell One-Arm Shoulder Press | dikey itiş | weighted | el başına | evet | bench | 0.32 | 0.4 | C | — | 29 | 14 | expert |  |
| 54 | Dumbbell Shoulder Press | dikey itiş | weighted | el başına | hayır | bench | 0.33 | 0.4 | C | — | 30 | 15 | saeterbakken2013, expert | Seated pair ≈ 1.03 × standing barbell (Saeterbakken 2013) × press/bench 0.65 (expert), per hand. |
| 82 | Leverage Shoulder Press | dikey itiş | weighted | makine/kablo ağırlığı | hayır | bench | 0.65 | 0.5 | C | — | 58 | 29 | expert |  |
| 90 | Machine Shoulder (Military) Press | dikey itiş | weighted | makine/kablo ağırlığı | hayır | bench | 0.6 | 0.5 | C | — | 54 | 27 | expert |  |
| 99 | Parallel Bar Dip | dikey itiş | bodyweight_loaded | vücut ağırlığı + ek yük | hayır | bench | 1.3 | 0.4 | C | 0.95 | 41 | -0 | deleva1996, expert | ⚠ Same dip family as above. Confirm. |
| 104 | Push Press | dikey itiş | weighted | toplam (bar dahil) | hayır | bench | 0.85 | 0.4 | C | — | 76 | 38 | expert |  |
| 116 | Seated Barbell Military Press | dikey itiş | weighted | toplam (bar dahil) | hayır | bench | 0.66 | 0.4 | C | — | 59 | 30 | expert |  |
| 120 | Seated Dumbbell Press | dikey itiş | weighted | el başına | hayır | bench | 0.33 | 0.4 | C | — | 30 | 15 | saeterbakken2013, expert |  |
| 133 | Standing Dumbbell Press | dikey itiş | weighted | el başına | hayır | bench | 0.3 | 0.4 | C | — | 27 | 14 | saeterbakken2013, expert | Pair ≈ 0.93 × standing barbell, per hand. |
| 136 | Standing Military Press | dikey itiş | weighted | toplam (bar dahil) | hayır | bench | 0.65 | 0.4 | C | — | 58 | 29 | expert | Widely quoted 60–67% of bench; no same-subject primary study found. |

## Kaynaklar

- `anchor` — Definition — the anchor lift itself (docs/03-ML-MODEL.md §4).
- `opl` — OpenPowerlifting snapshot 2026-11-07 (ml/data/SOURCES.md), computed in P056: first raw SBD meet per athlete, 286,293 men / 133,646 women. Median bench/squat 0.667 M, 0.556 F; deadlift/squat 1.178 M, 1.227 F; robust SD of log ratios 0.12–0.17. Residual SD of log 1RM given sex, body weight and age 0.19–0.26. <https://openpowerlifting.gitlab.io/opl-csv/> (erişim 2026-11-13)
- `saeterbakken2011` — Saeterbakken AH, van den Tillaar R, Fimland MS. A comparison of muscle activity and 1-RM strength of three chest-press exercises with different stability requirements. J Sports Sci 2011;29(5):533-8. Dumbbell 1RM (sum of both) 17% below barbell; Smith machine 3% below barbell (12 trained men). <https://doi.org/10.1080/02640414.2010.543916> (erişim 2026-11-13)
- `saeterbakken2013` — Saeterbakken AH, Fimland MS. Effects of body position and loading modality on muscle activity and strength in shoulder presses. J Strength Cond Res 2013;27(7):1824-31. Standing dumbbell 1RM ~7% below standing barbell and ~10% below seated dumbbell (15 men). <https://doi.org/10.1519/JSC.0b013e318276b873> (erişim 2026-11-13)
- `cotterman2005` — Cotterman ML, Darby LA, Skelly WA. Comparison of muscle force production using the Smith machine and free weights for bench press and squat exercises. J Strength Cond Res 2005;19(1):169-76. Smith bench 1RM = −6.76 + 0.95 × free bench 1RM; Smith squat 1RM ≥ free squat (16 men, 16 women). <https://doi.org/10.1519/14433.1> (erişim 2026-11-13)
- `swinton2011` — Swinton PA et al. A biomechanical analysis of straight and hexagonal barbell deadlifts using submaximal loads. J Strength Cond Res 2011;25(7):2000-9. Hexagonal bar 1RM 265 ± 41 kg vs straight bar 245 ± 39 kg (19 men). <https://doi.org/10.1519/JSC.0b013e3181e73f87> (erişim 2026-11-13)
- `lockie2018` — Lockie RG et al. The 1 repetition maximum mechanics of a high-handle hexagonal bar deadlift compared with a conventional deadlift as measured by a linear position transducer. J Strength Cond Res 2018;32(1):150-161. High-handle hex bar 154.5 ± 45.3 kg vs conventional 134.7 ± 40.6 kg (21 men, 10 women). <https://doi.org/10.1519/JSC.0000000000001781> (erişim 2026-11-13)
- `rodriguezridao2020` — Rodríguez-Ridao D et al. Effect of five bench inclinations on the electromyographic activity of the pectoralis major, anterior deltoid, and triceps brachii during the bench press exercise. Int J Environ Res Public Health 2020;17(19):7339, Table 1. 1RM 81.4 kg at 0°, 63.3 kg at 30°, 57.9 kg at 45° (30 trained adults). <https://doi.org/10.3390/ijerph17197339> (erişim 2026-11-13)
- `larsen2021` — Larsen S, Gomo O, van den Tillaar R. A biomechanical analysis of wide, medium, and narrow grip width effects on ... 1-RM bench pressing. Front Sports Act Living 2021;2:637066. 1RM wide 109.8, medium 108.9, narrow 103.7 kg. <https://doi.org/10.3389/fspor.2020.637066> (erişim 2026-11-13)
- `suprak2011` — Suprak DN, Dawes J, Stephenson MD. The effect of position on the percentage of body mass supported during traditional and modified push-up variants. J Strength Cond Res 2011;25(2):497-503. Traditional push-up 69.16% (up) / 75.04% (down) of body mass — values as reported by the Cooper Institute summary. <https://doi.org/10.1519/JSC.0b013e3181bde2cf> (erişim 2026-11-13)
- `ebben2011` — Ebben WP et al. Kinetic analysis of several variations of push-ups. J Strength Cond Res 2011;25(10):2891-4. Peak GRF as share of body mass: regular ≈ 0.64–0.66, feet on 30.5 cm box ≈ 0.70, on 61 cm box ≈ 0.74 (values from secondary summaries; the abstract states the ordering only). <https://doi.org/10.1519/JSC.0b013e31820c8587> (erişim 2026-11-13)
- `deleva1996` — de Leva P. Adjustments to Zatsiorsky-Seluyanov's segment inertia parameters. J Biomech 1996;29(9):1223-30. Segment mass shares (male/female %): head 6.94/6.68, trunk 43.46/42.57, upper arm 2.71/2.55, forearm 1.62/1.38, hand 0.61/0.56, thigh 14.16/14.78, shank 4.33/4.81, foot 1.37/1.29. <https://doi.org/10.1016/0021-9290(95)00178-6> (erişim 2026-11-13)
- `expert` — Expert estimate (ATROX P056): typical gym loads for a lifter whose anchor lift is known, cross-checked with the implied-load table in docs/CEKIRDEK-HAREKETLER.md. To be replaced by app data (docs/03-ML-MODEL.md §12).

## Çekirdek dışı

Çekirdek dışı 191 hareket kural tabanlı atandı ve `scoring_taxonomy.yaml` içinde `needs_review: true` ile işaretli; bunlar kaydedilir ama ilk sürümde yüzdelik skor üretmez.
