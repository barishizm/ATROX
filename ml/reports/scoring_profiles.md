# Örnek profil skorları (P057)

Üretim: `python -m gymml.scoring_run profiles`. Her hareket için 2 oturum (3 ve 10 gün önce), aynı set, RIR 1.
Referans grubu: salon (varsayılan); çapa hareketlerde yarışmacı referansı da verilir. Skor 1–99, bant = ±1
belirsizlik (kalibrasyon bandı ⊕ oran τ). Seviye anahtarları uygulamada yerelleştirilir.

## Erkek yeni başlayan (cinsiyet M, 30 yaş, 80 kg)

| hareket | set | salon skoru | bant | güven | seviye | yarışmacı skoru |
|---|---|---|---|---|---|---|
| barbell-full-squat | 60 kg × 5 | 27 | 20–35 | medium | developing | 1 |
| barbell-bench-press-medium-grip | 50 kg × 5 | 20 | 14–26 | medium | beginner | 1 |
| barbell-deadlift | 80 kg × 5 | 30 | 23–38 | medium | developing | 1 |
| standing-military-press | 30 kg × 5 | 27 | 8–57 | low | developing | 10 |
| bent-over-barbell-row | 40 kg × 8 | 32 | 11–63 | low | developing | 13 |
| pullups | 0 kg × 3 | 38 | 14–69 | low | developing | 18 |
| dumbbell-bench-press | 18 kg × 8 | 20 | 10–35 | medium | developing | 1 |
| barbell-curl | 25 kg × 8 | 32 | 10–62 | low | developing | 13 |
| leg-press | 40 kg × 10 | 34 | 11–67 | low | developing | 13 |
| pushups | 15 tekrar | 32 | 1–99 | low | developing | 32 |

Kas grupları: chest 20, quadriceps 28, hamstrings 28, lats 33, shoulders 23, biceps 32, triceps 21

**Genel Güç Skoru: 24** (developing; kalıplar: horizontal_push, vertical_push, horizontal_pull, vertical_pull, squat, hip_hinge)

## Erkek orta (cinsiyet M, 30 yaş, 80 kg)

| hareket | set | salon skoru | bant | güven | seviye | yarışmacı skoru |
|---|---|---|---|---|---|---|
| barbell-full-squat | 120 kg × 5 | 59 | 50–67 | medium | intermediate | 5 |
| barbell-bench-press-medium-grip | 90 kg × 5 | 56 | 47–64 | medium | intermediate | 14 |
| barbell-deadlift | 150 kg × 5 | 63 | 54–71 | medium | advanced | 6 |
| standing-military-press | 55 kg × 5 | 50 | 22–79 | low | intermediate | 29 |
| bent-over-barbell-row | 75 kg × 8 | 64 | 33–87 | low | advanced | 45 |
| pullups | 10 kg × 6 | 48 | 20–77 | low | intermediate | 27 |
| dumbbell-bench-press | 32 kg × 8 | 50 | 33–68 | medium | intermediate | 15 |
| barbell-curl | 40 kg × 8 | 52 | 23–80 | low | intermediate | 31 |
| leg-press | 100 kg × 10 | 59 | 26–86 | low | intermediate | 33 |
| pushups | 35 tekrar | 80 | 1–99 | low | expert | 80 |

Kas grupları: chest 61, quadriceps 60, hamstrings 61, lats 57, shoulders 58, biceps 54, triceps 59

**Genel Güç Skoru: 60** (advanced; kalıplar: horizontal_push, vertical_push, horizontal_pull, vertical_pull, squat, hip_hinge)

## Erkek ileri (cinsiyet M, 30 yaş, 85 kg)

| hareket | set | salon skoru | bant | güven | seviye | yarışmacı skoru |
|---|---|---|---|---|---|---|
| barbell-full-squat | 180 kg × 3 | 84 | 78–89 | medium | expert | 44 |
| barbell-bench-press-medium-grip | 130 kg × 3 | 82 | 76–87 | medium | expert | 65 |
| barbell-deadlift | 220 kg × 3 | 89 | 84–93 | medium | expert | 57 |
| standing-military-press | 80 kg × 3 | 68 | 38–90 | low | advanced | 51 |
| bent-over-barbell-row | 100 kg × 6 | 76 | 47–93 | low | advanced | 62 |
| pullups | 30 kg × 5 | 59 | 28–84 | low | intermediate | 38 |
| dumbbell-bench-press | 45 kg × 8 | 77 | 61–88 | medium | advanced | 55 |
| barbell-curl | 55 kg × 6 | 67 | 36–89 | low | advanced | 48 |
| leg-press | 160 kg × 8 | 79 | 48–95 | low | advanced | 59 |
| pushups | 55 tekrar | 80 | 1–99 | low | expert | 80 |

Kas grupları: chest 82, quadriceps 86, hamstrings 88, lats 76, shoulders 78, biceps 68, triceps 80

**Genel Güç Skoru: 84** (expert; kalıplar: horizontal_push, vertical_push, horizontal_pull, vertical_pull, squat, hip_hinge)

## Kadın yeni başlayan (cinsiyet F, 30 yaş, 62 kg)

| hareket | set | salon skoru | bant | güven | seviye | yarışmacı skoru |
|---|---|---|---|---|---|---|
| barbell-full-squat | 35 kg × 5 | 31 | 24–39 | medium | developing | 1 |
| barbell-bench-press-medium-grip | 25 kg × 5 | 16 | 11–21 | medium | beginner | 1 |
| barbell-deadlift | 50 kg × 5 | 33 | 25–41 | medium | developing | 1 |
| standing-military-press | 17.5 kg × 5 | 26 | 9–52 | low | developing | 10 |
| bent-over-barbell-row | 25 kg × 8 | 39 | 16–66 | low | developing | 21 |
| pullups | 0 kg × 1 | 59 | 31–82 | low | intermediate | 44 |
| dumbbell-bench-press | 8 kg × 8 | 11 | 5–19 | medium | beginner | 1 |
| barbell-curl | 12 kg × 8 | 24 | 8–50 | low | developing | 9 |
| leg-press | 30 kg × 10 | 41 | 15–71 | low | intermediate | 12 |
| pushups | 5 tekrar | 20 | 1–99 | low | developing | 20 |

Kas grupları: chest 12, quadriceps 32, hamstrings 32, lats 46, shoulders 18, biceps 33, triceps 13

**Genel Güç Skoru: 26** (developing; kalıplar: horizontal_push, vertical_push, horizontal_pull, vertical_pull, squat, hip_hinge)

## Kadın orta (cinsiyet F, 30 yaş, 62 kg)

| hareket | set | salon skoru | bant | güven | seviye | yarışmacı skoru |
|---|---|---|---|---|---|---|
| barbell-full-squat | 70 kg × 5 | 66 | 58–74 | medium | advanced | 7 |
| barbell-bench-press-medium-grip | 45 kg × 5 | 56 | 47–64 | medium | intermediate | 28 |
| barbell-deadlift | 95 kg × 5 | 73 | 65–80 | medium | advanced | 13 |
| standing-military-press | 30 kg × 5 | 56 | 29–80 | low | intermediate | 41 |
| bent-over-barbell-row | 40 kg × 8 | 68 | 41–88 | low | advanced | 58 |
| pullups | 0 kg × 3 | 62 | 35–85 | low | advanced | 50 |
| dumbbell-bench-press | 16 kg × 8 | 50 | 35–65 | medium | intermediate | 24 |
| barbell-curl | 20 kg × 8 | 52 | 26–78 | low | intermediate | 36 |
| leg-press | 60 kg × 10 | 66 | 34–89 | low | advanced | 34 |
| pushups | 18 tekrar | 54 | 1–99 | low | intermediate | 54 |

Kas grupları: chest 54, quadriceps 69, hamstrings 71, lats 69, shoulders 57, biceps 59, triceps 54

**Genel Güç Skoru: 67** (advanced; kalıplar: horizontal_push, vertical_push, horizontal_pull, vertical_pull, squat, hip_hinge)

## Kadın ileri (cinsiyet F, 30 yaş, 62 kg)

| hareket | set | salon skoru | bant | güven | seviye | yarışmacı skoru |
|---|---|---|---|---|---|---|
| barbell-full-squat | 115 kg × 3 | 93 | 89–95 | medium | expert | 71 |
| barbell-bench-press-medium-grip | 70 kg × 3 | 85 | 79–89 | medium | expert | 87 |
| barbell-deadlift | 145 kg × 3 | 95 | 93–97 | medium | elite | 81 |
| standing-military-press | 45 kg × 3 | 77 | 51–93 | low | advanced | 70 |
| bent-over-barbell-row | 60 kg × 6 | 85 | 63–96 | low | expert | 82 |
| pullups | 10 kg × 5 | 75 | 49–92 | low | advanced | 68 |
| dumbbell-bench-press | 25 kg × 8 | 83 | 72–91 | medium | expert | 82 |
| barbell-curl | 30 kg × 6 | 74 | 48–91 | low | advanced | 66 |
| leg-press | 100 kg × 8 | 87 | 63–97 | low | expert | 68 |
| pushups | 35 tekrar | 80 | 1–99 | low | expert | 80 |

Kas grupları: chest 86, quadriceps 94, hamstrings 95, lats 88, shoulders 84, biceps 79, triceps 85

**Genel Güç Skoru: 92** (expert; kalıplar: horizontal_push, vertical_push, horizontal_pull, vertical_pull, squat, hip_hinge)

## Cinsiyet belirtilmemiş orta (cinsiyet —, 30 yaş, 72 kg)

| hareket | set | salon skoru | bant | güven | seviye | yarışmacı skoru |
|---|---|---|---|---|---|---|
| barbell-full-squat | 95 kg × 5 | 64 | 56–71 | medium | advanced | 14 |
| barbell-bench-press-medium-grip | 65 kg × 5 | 58 | 51–65 | medium | intermediate | 39 |
| barbell-deadlift | 120 kg × 5 | 67 | 60–74 | medium | advanced | 18 |
| standing-military-press | 42.5 kg × 5 | 57 | 31–81 | low | intermediate | 42 |
| bent-over-barbell-row | 55 kg × 8 | 65 | 39–86 | low | advanced | 52 |
| pullups | 0 kg × 5 | 55 | 29–80 | low | intermediate | 40 |
| dumbbell-bench-press | 22 kg × 8 | 50 | 36–65 | medium | intermediate | 30 |
| barbell-curl | 30 kg × 8 | 57 | 31–81 | low | intermediate | 42 |
| leg-press | 80 kg × 10 | 64 | 33–87 | low | advanced | 37 |
| pushups | 25 tekrar | 71 | 1–99 | low | advanced | 71 |

Kas grupları: chest 59, quadriceps 66, hamstrings 66, lats 62, shoulders 60, biceps 59, triceps 59

**Genel Güç Skoru: 65** (advanced; kalıplar: horizontal_push, vertical_push, horizontal_pull, vertical_pull, squat, hip_hinge)

## Notlar

- Birleştirme §8 formülüyle: korelasyon 1'den küçükken eşit skorların birleşimi aynı yönde daha uçtur
  (r = 0.6 iken iki 60 → ≈ 61; 50 her zaman 50). Bu yüzden kas grubu/genel skor tek tek hareket
  skorlarının ortalamasından biraz daha uçta çıkar. Prompt'taki "eşit iki skorun birleşimi aynı skor"
  özelliği yalnızca r = 1'de birebir sağlanır; gösterim kararı kullanıcıda.
- C sınıfı oranlar yarışmacı ölçeğinde (s ≈ 0.2) uç skoru engeller; salon referansında yayılım κ ≈ 1.95 kat
  geniş olduğundan τ = 0.4 büzülmesi zayıflar ve C sınıfı bir hareket 95'i aşabilir (ör. çok ağır askeri pres).
  P056'nın `tau_c_min` hesabı yarışmacı yayılımına göre yapılmıştı; salon için gözden geçirilmeli.
- `reps_only` (şınav) normları en fazla 80. yüzdeliğe kadar tablolu; bant 1–99 (düşük güven).

