# Veri sözlüğü — `data/interim/opl.parquet`

Kaynak: OpenPowerlifting toplu CSV (kamu malı; bkz. [`../data/SOURCES.md`](../data/SOURCES.md)).
Ham sütun belgeleri: <https://openpowerlifting.gitlab.io/opl-csv/bulk-csv-docs.html>.
Üretim: `make data` (`gymml/data/opl.py`). Satır = bir sporcunun bir yarışmadaki bir kaydı.

**Kişi adı yoktur.** `Name` sütunu okunur okunmaz `athlete_id`'ye çevrilir ve atılır; yarışma adı, şehir ve
eyalet gibi sütunlar da tutulmaz. Ham CSV içe aktarma sonunda diskten silinir.

| Sütun | Tür | Anlamı | Not |
|---|---|---|---|
| `athlete_id` | string(16) | Sporcu kimliği: `SHA-256("atrox-opl-v1\|" + casefold(Name))` ilk 16 hex | OPL aynı adlı kişileri `#n` ile ayırır, bu ayrım korunur. Takma ad, anonimleştirme değil. Aynı sporcunun kayıtlarını bağlar; **eğitim/test bölmesi bu kimliğe göre yapılır** |
| `sex` | string | Yarıştığı cinsiyet kategorisi: `M`, `F`, `Mx` | Model yalnızca M/F ile eğitilir (§4.5) |
| `event` | string | `SBD`, `BD`, `SD`, `SB`, `S`, `B`, `D` | Squat-Bench-Deadlift harfleri |
| `equipment` | string | `Raw`, `Wraps`, `Single-ply`, `Multi-ply`, `Unlimited`, `Straps` | Kategori; sporcunun fiilen giydiği değil. Hedef: `Raw` (squat için `Wraps` ayrı bayrak) |
| `age` | float32 | Yarışma günü yaş; `n+0.5` yaklaşık yaş (doğum yılı bilinen) | ~%36 boş; `age_class` ile doldurma P048'de |
| `age_class` | string | Yaş sınıfı, ör. `40-44` | Yaş boşken orta nokta kullanımı P048 |
| `bodyweight_kg` | float32 | Tartı vücut ağırlığı (kg) | Boş olabilir |
| `squat_kg`, `bench_kg`, `deadlift_kg` | float32 | Üç denemenin en iyi başarılısı (kg) | Negatif = bazı federasyonlarda "başarısız en düşük deneme"; hedef olarak `> 0` süzülür (P048) |
| `total_kg` | float32 | S+B+D toplamı; hiçbiri başarısızsa dolu | Diskalifiyede boş |
| `place` | string | Sıra (sayı) veya `G` misafir, `DQ` diskalifiye, `DD` doping diskalifiyesi, `NS` gelmedi | P048'de `G/DQ/DD/NS` çıkarılır |
| `dots` | float32 | Dots puanı | Yalnızca sağlama/EDA için; model girdisi değil |
| `tested` | bool | Kategori ilaç testli ise `true` | Kayıt "testli sayılır" anlamında, fiilen test edildiği değil |
| `country` | string | Sporcunun ülkesi (biliniyorsa) | |
| `federation` | string | Yarışmayı düzenleyen federasyon | |
| `parent_federation` | string | Üst federasyon | |
| `date` | date | Yarışma başlangıç tarihi | Takvim yılı = tekrarlı ölçüm grubu (§4.1) |

## Bilerek atılan ham sütunlar
`Name` (kimliğe çevrildi), `BirthYearClass`, `Division`, `WeightClassKg`, tüm `Squat1..4Kg/Bench1..4Kg/Deadlift1..4Kg`
(deneme düzeyi; modelde yalnızca en iyi başarılı kaldırış kullanılır), `Wilks`, `Glossbrenner`, `Goodlift`,
`State`, `MeetCountry`, `MeetState`, `MeetTown`, `MeetName`, `Sanctioned`.

# Kohort tabloları — `data/processed/` (P048, `make eda`)

`cohort_long.parquet` — satır = sporcu × takvim yılı × kaldırış × `wraps` başına en iyi başarılı kaldırış.

| Sütun | Anlamı |
|---|---|
| `athlete_id`, `year`, `sex`, `tested`, `federation`, `event` | `opl.parquet`'ten; `year` = yarışma yılı |
| `age`, `bodyweight_kg` | En iyi kaydın yapıldığı yarışmadaki yaş ve kilo |
| `age_imputed` | Yaş AgeClass orta noktasından mı (varsayılan kapalı, hep `false`) |
| `lift`, `value_kg` | `squat` / `bench` / `deadlift`, kg |
| `wraps` | Yalnızca squat'ta `true` olabilir (Wraps kategorisi); model hedefi `false` satırlar |
| `weight` | Ters-frekans örnek ağırlığı; bir sporcunun bir kaldırıştaki ağırlıkları toplamı 1 |
| `age_band`, `bodyweight_kg_band` | Kalibrasyon katmanları (`AGE_BAND_EDGES`, `BW_BAND_EDGES`) |

`cohort_sbd.parquet` — aynı yarışmada S, B, D üçü de başarılı kayıtlar; sporcu × yıl × `wraps` başına en iyi
toplam; `squat_kg`, `bench_kg`, `deadlift_kg`, `total_kg`, `weight` (sporcu başına toplam 1). Oranları
tutarsız (veri giriş hatası şüphesi) kayıtlar atılır. `cohort_flow.json` süzgeç akışını ve yapılandırmayı tutar.
