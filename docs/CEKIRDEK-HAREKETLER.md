# Çekirdek hareketler (P025)

Güç Skoru'nun ilk sürümde hedeflediği ~150 hareket. Bu liste **onayını bekliyor**: satırları gözden geçir,
değişiklikleri `tools/catalog/taxonomy_overrides.yaml` içine yaz (`core` listesi ve `overrides`), ardından
`cd tools/catalog && uv run catalog-taxonomy` ile bu dosyayı ve `scoring_taxonomy.yaml`'ı yeniden üret.

- Çekirdek hareket sayısı: **155** (katalogda toplam 876)
- Kuralla atanıp **belirsiz** işaretlenen çekirdek satır: **16** (aşağıda ⚠ ile)
- `anchor`, `ratio`, `tau`, `bw_fraction` bilerek boş; P056'da doldurulacak.
- Tür: `weighted` = ağırlıklı, `bodyweight_loaded` = vücut ağırlığı + ek yük, `reps_only` = yalnızca tekrar,
  `time` = süre, `none` = skorlanmaz.

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

| # | Ad | Kalıp | Tür | Yük kuralı | Tek taraflı | Not |
|---|---|---|---|---|---|---|
| 59 | Farmer's Walk | taşıma | weighted | el başına | hayır |  |
| 1 | Ab Crunch Machine | gövde | weighted | makine/kablo ağırlığı | hayır |  |
| 2 | Ab Roller | gövde | reps_only | — | hayır |  |
| 5 | Barbell Ab Rollout | gövde | reps_only | — | hayır |  |
| 15 | Barbell Side Bend | gövde | weighted | toplam (bar dahil) | hayır |  |
| 26 | Cable Crunch | gövde | weighted | makine/kablo ağırlığı | hayır |  |
| 38 | Crunches | gövde | reps_only | — | hayır |  |
| 60 | Flat Bench Lying Leg Raise | gövde | reps_only | — | hayır |  |
| 69 | Hanging Leg Raise | gövde | reps_only | — | hayır | ⚠ ambiguous name pattern: hanging |
| 92 | Oblique Crunches | gövde | reps_only | — | hayır |  |
| 96 | Pallof Press | gövde | weighted | makine/kablo ağırlığı | hayır |  |
| 100 | Plank | gövde | time | — | hayır |  |
| 109 | Reverse Crunch | gövde | reps_only | — | hayır |  |
| 115 | Russian Twist | gövde | reps_only | — | hayır |  |
| 124 | Sit-Up | gövde | reps_only | — | hayır |  |
| 8 | Barbell Deadlift | kalça menteşesi | weighted | toplam (bar dahil) | hayır |  |
| 10 | Barbell Hip Thrust | kalça menteşesi | weighted | toplam (bar dahil) | hayır |  |
| 65 | Good Morning | kalça menteşesi | weighted | toplam (bar dahil) | hayır |  |
| 71 | Hyperextensions (Back Extensions) | kalça menteşesi | bodyweight_loaded | vücut ağırlığı + ek yük | hayır |  |
| 94 | One-Arm Kettlebell Swings | kalça menteşesi | weighted | toplam (bar dahil) | evet |  |
| 107 | Rack Pulls | kalça menteşesi | weighted | toplam (bar dahil) | hayır |  |
| 114 | Romanian Deadlift | kalça menteşesi | weighted | toplam (bar dahil) | hayır |  |
| 138 | Stiff-Legged Barbell Deadlift | kalça menteşesi | weighted | toplam (bar dahil) | hayır |  |
| 139 | Stiff-Legged Dumbbell Deadlift | kalça menteşesi | weighted | el başına | hayır |  |
| 141 | Sumo Deadlift | kalça menteşesi | weighted | toplam (bar dahil) | hayır |  |
| 145 | Trap Bar Deadlift | kalça menteşesi | weighted | toplam (bar dahil) | hayır |  |
| 19 | Bent Over Barbell Row | yatay çekiş | weighted | toplam (bar dahil) | hayır |  |
| 21 | Bent Over Two-Dumbbell Row | yatay çekiş | weighted | el başına | hayır |  |
| 49 | Dumbbell Incline Row | yatay çekiş | weighted | el başına | hayır |  |
| 76 | Inverted Row | yatay çekiş | bodyweight_loaded | vücut ağırlığı + ek yük | hayır | ⚠ equipment missing in source |
| 80 | Leverage High Row | yatay çekiş | weighted | makine/kablo ağırlığı | hayır |  |
| 81 | Leverage Iso Row | yatay çekiş | weighted | makine/kablo ağırlığı | hayır |  |
| 86 | Lying T-Bar Row | yatay çekiş | weighted | taraf başına (plaka) | hayır | ⚠ plate-loaded machine assumed (`per_side`); confirm loading convention |
| 93 | One-Arm Dumbbell Row | yatay çekiş | weighted | el başına | evet |  |
| 111 | Reverse Grip Bent-Over Rows | yatay çekiş | weighted | toplam (bar dahil) | hayır |  |
| 117 | Seated Cable Rows | yatay çekiş | weighted | makine/kablo ağırlığı | hayır |  |
| 142 | T-Bar Row with Handle | yatay çekiş | weighted | toplam (bar dahil) | hayır |  |
| 6 | Barbell Bench Press - Medium Grip | yatay itiş | weighted | toplam (bar dahil) | hayır |  |
| 11 | Barbell Incline Bench Press - Medium Grip | yatay itiş | weighted | toplam (bar dahil) | hayır |  |
| 24 | Cable Chest Press | yatay itiş | weighted | makine/kablo ağırlığı | hayır |  |
| 34 | Close-Grip Barbell Bench Press | yatay itiş | weighted | toplam (bar dahil) | hayır |  |
| 39 | Decline Barbell Bench Press | yatay itiş | weighted | toplam (bar dahil) | hayır |  |
| 40 | Decline Dumbbell Bench Press | yatay itiş | weighted | el başına | hayır |  |
| 46 | Dumbbell Bench Press | yatay itiş | weighted | el başına | hayır |  |
| 75 | Incline Dumbbell Press | yatay itiş | weighted | el başına | hayır |  |
| 79 | Leverage Chest Press | yatay itiş | weighted | makine/kablo ağırlığı | hayır |  |
| 87 | Machine Bench Press | yatay itiş | weighted | makine/kablo ağırlığı | hayır |  |
| 105 | Push-Ups With Feet Elevated | yatay itiş | reps_only | — | hayır |  |
| 106 | Pushups | yatay itiş | reps_only | — | hayır |  |
| 125 | Smith Machine Bench Press | yatay itiş | weighted | toplam (bar dahil) | hayır | ⚠ ambiguous name pattern: smith; smith machine: bar is counterbalanced, so `total` may overstate the load |
| 126 | Smith Machine Incline Bench Press | yatay itiş | weighted | toplam (bar dahil) | hayır | ⚠ ambiguous name pattern: smith; smith machine: bar is counterbalanced, so `total` may overstate the load |
| 153 | Wide-Grip Barbell Bench Press | yatay itiş | weighted | toplam (bar dahil) | hayır |  |
| 14 | Barbell Shrug | izolasyon-sırt/trapez | weighted | toplam (bar dahil) | hayır |  |
| 55 | Dumbbell Shrug | izolasyon-sırt/trapez | weighted | el başına | hayır |  |
| 140 | Straight-Arm Pulldown | izolasyon-sırt/trapez | weighted | makine/kablo ağırlığı | hayır |  |
| 7 | Barbell Curl | izolasyon-biceps | weighted | toplam (bar dahil) | hayır |  |
| 36 | Concentration Curls | izolasyon-biceps | weighted | el başına | evet |  |
| 37 | Cross Body Hammer Curl | izolasyon-biceps | weighted | el başına | evet |  |
| 45 | Dumbbell Alternate Bicep Curl | izolasyon-biceps | weighted | el başına | evet |  |
| 47 | Dumbbell Bicep Curl | izolasyon-biceps | weighted | el başına | hayır |  |
| 57 | EZ-Bar Curl | izolasyon-biceps | weighted | toplam (bar dahil) | hayır |  |
| 67 | Hammer Curls | izolasyon-biceps | weighted | el başına | hayır |  |
| 70 | High Cable Curls | izolasyon-biceps | weighted | makine/kablo ağırlığı | hayır |  |
| 73 | Incline Dumbbell Curl | izolasyon-biceps | weighted | el başına | hayır |  |
| 88 | Machine Bicep Curl | izolasyon-biceps | weighted | makine/kablo ağırlığı | hayır |  |
| 89 | Machine Preacher Curls | izolasyon-biceps | weighted | makine/kablo ağırlığı | hayır |  |
| 102 | Preacher Curl | izolasyon-biceps | weighted | toplam (bar dahil) | hayır |  |
| 108 | Reverse Barbell Curl | izolasyon-biceps | weighted | toplam (bar dahil) | hayır |  |
| 131 | Standing Biceps Cable Curl | izolasyon-biceps | weighted | makine/kablo ağırlığı | hayır |  |
| 155 | Zottman Curl | izolasyon-biceps | weighted | el başına | hayır |  |
| 31 | Calf Press On The Leg Press Machine | izolasyon-baldır | weighted | taraf başına (plaka) | hayır | ⚠ plate-loaded machine assumed (`per_side`); confirm loading convention |
| 44 | Donkey Calf Raises | izolasyon-baldır | weighted | toplam (bar dahil) | hayır |  |
| 118 | Seated Calf Raise | izolasyon-baldır | weighted | makine/kablo ağırlığı | hayır |  |
| 130 | Standing Barbell Calf Raise | izolasyon-baldır | weighted | toplam (bar dahil) | hayır |  |
| 132 | Standing Calf Raises | izolasyon-baldır | weighted | makine/kablo ağırlığı | hayır |  |
| 18 | Bent-Arm Dumbbell Pullover | izolasyon-göğüs | weighted | el başına | hayır | ⚠ ambiguous name pattern: pullover |
| 23 | Butterfly | izolasyon-göğüs | weighted | makine/kablo ağırlığı | hayır |  |
| 25 | Cable Crossover | izolasyon-göğüs | weighted | makine/kablo ağırlığı | hayır |  |
| 48 | Dumbbell Flyes | izolasyon-göğüs | weighted | el başına | hayır |  |
| 72 | Incline Cable Flye | izolasyon-göğüs | weighted | makine/kablo ağırlığı | hayır |  |
| 74 | Incline Dumbbell Flyes | izolasyon-göğüs | weighted | el başına | hayır |  |
| 83 | Low Cable Crossover | izolasyon-göğüs | weighted | makine/kablo ağırlığı | hayır |  |
| 97 | Palms-Down Wrist Curl Over A Bench | izolasyon-önkol | weighted | toplam (bar dahil) | hayır |  |
| 98 | Palms-Up Barbell Wrist Curl Over A Bench | izolasyon-önkol | weighted | toplam (bar dahil) | hayır |  |
| 119 | Seated Dumbbell Palms-Up Wrist Curl | izolasyon-önkol | weighted | el başına | hayır |  |
| 63 | Glute Ham Raise | izolasyon-arka bacak | weighted | makine/kablo ağırlığı | hayır |  |
| 85 | Lying Leg Curls | izolasyon-arka bacak | weighted | makine/kablo ağırlığı | hayır |  |
| 121 | Seated Leg Curl | izolasyon-arka bacak | weighted | makine/kablo ağırlığı | hayır |  |
| 135 | Standing Leg Curl | izolasyon-arka bacak | weighted | makine/kablo ağırlığı | hayır |  |
| 143 | Thigh Abductor | izolasyon-kalça yanı/iç | weighted | makine/kablo ağırlığı | hayır |  |
| 144 | Thigh Adductor | izolasyon-kalça yanı/iç | weighted | makine/kablo ağırlığı | hayır |  |
| 77 | Leg Extensions | izolasyon-ön bacak | weighted | makine/kablo ağırlığı | hayır |  |
| 20 | Bent Over Low-Pulley Side Lateral | izolasyon-omuz | weighted | makine/kablo ağırlığı | hayır |  |
| 28 | Cable Rear Delt Fly | izolasyon-omuz | weighted | makine/kablo ağırlığı | hayır |  |
| 30 | Cable Seated Lateral Raise | izolasyon-omuz | weighted | makine/kablo ağırlığı | hayır |  |
| 58 | Face Pull | izolasyon-omuz | weighted | makine/kablo ağırlığı | hayır |  |
| 62 | Front Two-Dumbbell Raise | izolasyon-omuz | weighted | el başına | hayır |  |
| 110 | Reverse Flyes | izolasyon-omuz | weighted | el başına | hayır |  |
| 113 | Reverse Machine Flyes | izolasyon-omuz | weighted | makine/kablo ağırlığı | hayır |  |
| 122 | Seated Side Lateral Raise | izolasyon-omuz | weighted | el başına | hayır |  |
| 123 | Side Lateral Raise | izolasyon-omuz | weighted | el başına | hayır |  |
| 27 | Cable One Arm Tricep Extension | izolasyon-triceps | weighted | makine/kablo ağırlığı | evet |  |
| 29 | Cable Rope Overhead Triceps Extension | izolasyon-triceps | weighted | makine/kablo ağırlığı | hayır |  |
| 52 | Dumbbell One-Arm Triceps Extension | izolasyon-triceps | weighted | el başına | evet |  |
| 84 | Lying Dumbbell Tricep Extension | izolasyon-triceps | weighted | el başına | hayır |  |
| 91 | Machine Triceps Extension | izolasyon-triceps | weighted | makine/kablo ağırlığı | hayır |  |
| 112 | Reverse Grip Triceps Pushdown | izolasyon-triceps | weighted | makine/kablo ağırlığı | hayır |  |
| 134 | Standing Dumbbell Triceps Extension | izolasyon-triceps | weighted | el başına | hayır |  |
| 137 | Standing Overhead Barbell Triceps Extension | izolasyon-triceps | weighted | toplam (bar dahil) | hayır |  |
| 146 | Tricep Dumbbell Kickback | izolasyon-triceps | weighted | el başına | evet |  |
| 147 | Triceps Pushdown | izolasyon-triceps | weighted | makine/kablo ağırlığı | hayır |  |
| 148 | Triceps Pushdown - Rope Attachment | izolasyon-triceps | weighted | makine/kablo ağırlığı | hayır |  |
| 149 | Triceps Pushdown - V-Bar Attachment | izolasyon-triceps | weighted | makine/kablo ağırlığı | hayır |  |
| 33 | Clean and Jerk | olimpik kaldırış | weighted | toplam (bar dahil) | hayır |  |
| 68 | Hang Clean | olimpik kaldırış | weighted | toplam (bar dahil) | hayır |  |
| 101 | Power Clean | olimpik kaldırış | weighted | toplam (bar dahil) | hayır |  |
| 128 | Snatch | olimpik kaldırış | weighted | toplam (bar dahil) | hayır |  |
| 9 | Barbell Full Squat | squat | weighted | toplam (bar dahil) | hayır |  |
| 12 | Barbell Lunge | squat | weighted | toplam (bar dahil) | evet |  |
| 16 | Barbell Step Ups | squat | weighted | toplam (bar dahil) | evet | ⚠ ambiguous name pattern: step_up |
| 17 | Barbell Walking Lunge | squat | weighted | toplam (bar dahil) | evet |  |
| 22 | Bodyweight Squat | squat | reps_only | — | hayır | ⚠ bodyweight exercise outside the push-up/sit-up families treated as reps_only |
| 50 | Dumbbell Lunges | squat | weighted | el başına | evet |  |
| 53 | Dumbbell Rear Lunge | squat | weighted | el başına | evet |  |
| 56 | Dumbbell Squat | squat | weighted | el başına | hayır |  |
| 61 | Front Barbell Squat | squat | weighted | toplam (bar dahil) | hayır |  |
| 64 | Goblet Squat | squat | weighted | toplam (bar dahil) | hayır |  |
| 66 | Hack Squat | squat | weighted | taraf başına (plaka) | hayır | ⚠ plate-loaded machine assumed (`per_side`); confirm loading convention |
| 78 | Leg Press | squat | weighted | taraf başına (plaka) | hayır | ⚠ plate-loaded machine assumed (`per_side`); confirm loading convention |
| 127 | Smith Machine Squat | squat | weighted | toplam (bar dahil) | hayır | ⚠ ambiguous name pattern: smith; smith machine: bar is counterbalanced, so `total` may overstate the load |
| 129 | Split Squat with Dumbbells | squat | weighted | el başına | evet |  |
| 4 | Band Assisted Pull-Up | dikey çekiş | bodyweight_loaded | vücut ağırlığı + ek yük | hayır |  |
| 32 | Chin-Up | dikey çekiş | bodyweight_loaded | vücut ağırlığı + ek yük | hayır |  |
| 35 | Close-Grip Front Lat Pulldown | dikey çekiş | weighted | makine/kablo ağırlığı | hayır |  |
| 95 | One Arm Lat Pulldown | dikey çekiş | weighted | makine/kablo ağırlığı | evet |  |
| 103 | Pullups | dikey çekiş | bodyweight_loaded | vücut ağırlığı + ek yük | hayır |  |
| 150 | Underhand Cable Pulldowns | dikey çekiş | weighted | makine/kablo ağırlığı | hayır |  |
| 151 | Upright Barbell Row | dikey çekiş | weighted | toplam (bar dahil) | hayır | ⚠ ambiguous name pattern: upright_row |
| 152 | V-Bar Pulldown | dikey çekiş | weighted | makine/kablo ağırlığı | hayır |  |
| 154 | Wide-Grip Lat Pulldown | dikey çekiş | weighted | makine/kablo ağırlığı | hayır |  |
| 3 | Arnold Dumbbell Press | dikey itiş | weighted | el başına | hayır |  |
| 13 | Barbell Shoulder Press | dikey itiş | weighted | toplam (bar dahil) | hayır |  |
| 41 | Dip Machine | dikey itiş | weighted | makine/kablo ağırlığı | hayır |  |
| 42 | Dips - Chest Version | dikey itiş | bodyweight_loaded | vücut ağırlığı + ek yük | hayır | ⚠ Dips load chest and triceps together; filed under vertical push (hands travel past the torso). Confirm. |
| 43 | Dips - Triceps Version | dikey itiş | bodyweight_loaded | vücut ağırlığı + ek yük | hayır | ⚠ Same movement as the chest version with a more upright torso; filed under vertical push. Confirm. |
| 51 | Dumbbell One-Arm Shoulder Press | dikey itiş | weighted | el başına | evet |  |
| 54 | Dumbbell Shoulder Press | dikey itiş | weighted | el başına | hayır |  |
| 82 | Leverage Shoulder Press | dikey itiş | weighted | makine/kablo ağırlığı | hayır |  |
| 90 | Machine Shoulder (Military) Press | dikey itiş | weighted | makine/kablo ağırlığı | hayır |  |
| 99 | Parallel Bar Dip | dikey itiş | bodyweight_loaded | vücut ağırlığı + ek yük | hayır | ⚠ Same dip family as above. Confirm. |
| 104 | Push Press | dikey itiş | weighted | toplam (bar dahil) | hayır |  |
| 116 | Seated Barbell Military Press | dikey itiş | weighted | toplam (bar dahil) | hayır |  |
| 120 | Seated Dumbbell Press | dikey itiş | weighted | el başına | hayır |  |
| 133 | Standing Dumbbell Press | dikey itiş | weighted | el başına | hayır |  |
| 136 | Standing Military Press | dikey itiş | weighted | toplam (bar dahil) | hayır |  |

## Çekirdek dışı

Çekirdek dışı 191 hareket kural tabanlı atandı ve `scoring_taxonomy.yaml` içinde `needs_review: true` ile işaretli; bunlar kaydedilir ama ilk sürümde yüzdelik skor üretmez.
