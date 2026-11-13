# Dengesizlik analizi — bulgu şeması (P059)

Referans uygulama: `ml/src/gymml/imbalance.py` (docs/03-ML-MODEL.md §10). Swift StrengthKit birebir taşır.
Parametre taslağı: `ml/params_draft/imbalance.json` (P058'de `params.json` içine birleşir). Her sayının
kaynağı dosyanın içinde yazılıdır; kaynağı olmayanlar **uzman varsayımı** olarak işaretlidir.

## Girdiler

| Tür | Alanlar |
|---|---|
| `ScoreInput` | `exercise_id`, `z` (skorun z değeri), `confidence` (`low`/`medium`/`high`), `pattern` (7 hareket kalıbı: `horizontal_push`, `vertical_push`, `horizontal_pull`, `vertical_pull`, `squat`, `hinge`, `core`), `is_machine`, `corr_key` (yalnızca çapa hareketin kendisi: `squat`/`bench`/`deadlift`), `muscles` |
| `UnilateralInput` | `exercise_id`, `left_kg`, `right_kg` (aynı hareketin e1RM'i), `confidence`, `is_machine`, `muscles` |
| Korelasyon | `variables` + matris. Taslaktaki matris **yer tutucudur**; gerçek `Corr(z_S, z_B, z_D | x)` P052/P053'ten gelir. `ImbalanceParams.with_correlation(...)` ile kişinin `x`'ine koşullu matris verilebilir. |

**Kapı:** `confidence ∈ allowed_confidence` (orta/yüksek) ve makine değil. Kapıdan geçmeyen girdi hiçbir
hesaba girmez.

## Kurallar

1. **`conditional_residual`** — standart normal varsayımıyla `E[z_t | z_g] = Σ_tg Σ_gg⁻¹ z_g`,
   `SD = sqrt(1 − Σ_tg Σ_gg⁻¹ Σ_gt)`, standart artık `(z_t − E) / SD`. En az `min_variables` (3) değişken
   gerekir. *Soyma:* en büyük |artık| eşiği aşarsa bulgu olur, değişken çıkarılır, kalanlar yeniden
   hesaplanır. Böylece zayıf bench, squat/deadlift için sahte "beklenenin üstünde" bulgusu üretmez.
2. **`ratio_rule`** — `push_pull`, `upper_lower`, `squat_deadlift`. Gruplar kalıp listeleriyle tanımlıdır;
   grup skoru §8 formülüyle (`w` = güven ağırlığı, bilinmeyen çift `r` = 0.6, iki çapa için matristeki `r`)
   birleştirilir. Skorlar aynı nüfusa göre normalize olduğundan oran z uzayında fark olarak ölçülür:
   `|z_A − z_B|` eşiği aşarsa bulgu.
3. **`left_right`** — `(güçlü − zayıf) / güçlü` e1RM (kg). Aynı hareketin iki tarafı karşılaştırıldığı için
   ham kg oranı anlamlıdır.

Şiddet merdiveni her kural için `mild < moderate < severe` eşikleridir (en yüksek aşılan basamak).

## Bulgu nesnesi (`Finding.to_dict()`, `schema_version = 1`)

| Alan | Tip | Anlam |
|---|---|---|
| `schema_version` | int | Bu tablonun sürümü |
| `kind` | `conditional_residual` \| `ratio_rule` \| `left_right` | Bulgu türü |
| `rule_id` | str | Artık: korelasyon değişkeni (`bench`…); oran: kural kimliği; sol/sağ: `exercise_id` |
| `severity` | `mild` \| `moderate` \| `severe` | Şiddet |
| `magnitude` | float ≥ 0 | Artık: \|standart artık\| (SD); oran: z farkı; sol/sağ: asimetri oranı |
| `weak_group` / `strong_group` | str | Artık: değişken adı veya `others`; oran: grup adı (`pull`…); sol/sağ: `left`/`right` |
| `weak_exercise_ids` / `strong_exercise_ids` | list[str] | İlgili hareketler (sıralı) |
| `muscles` | list[str] | Zayıf taraftaki hareketlerin kasları (sıralı, tekil) |
| `recommendation_key` | str | Yerelleştirilmiş şablon anahtarı (P069). Biçimler: `conditional_residual.<var>.below_expected` / `.above_expected`, `ratio_rule.<rule_id>.<weak_group>_behind`, `left_right.<left\|right>_behind` |
| `metrics` | {str: float} | Artık: `observed_z`, `expected_z`, `residual_sd`, `standardized_residual`; oran: `weak_z`, `strong_z`, `z_gap`; sol/sağ: `weak_kg`, `strong_kg`, `asymmetry` |

Nesnede hiçbir kullanıcı metni yoktur. Bulgular şiddete (ağırdan hafife), sonra türe, sonra `rule_id`'ye göre
sıralıdır; aynı girdi her zaman aynı listeyi verir (girdi sırasından bağımsız).
