"""P048: OpenPowerlifting temizleme ve kohort tabloları (docs/03-ML-MODEL.md §4.1).

Girdi: `data/interim/opl.parquet` (P047). Çıktılar (`data/processed/`, git'e girmez):

- `cohort_long.parquet` — uzun biçim: sporcu × takvim yılı × kaldırış (× squat'ta wraps)
  başına en iyi kayıt, sporcu başına ters-frekans ağırlığı (`weight`; bir sporcunun bir
  kaldırıştaki ağırlıkları toplamı 1).
- `cohort_sbd.parquet` — SBD üçlüsü aynı yarışmada tam olan kayıtlar, sporcu × yıl başına
  en iyi toplam (kaldırışlar arası korelasyon için, §4.4).
- `cohort_flow.json` — her süzgeçten sonra kalan satır sayısı.

Tüm eşikler `CohortConfig` içindedir; kodda sihirli sayı yoktur.
"""

from __future__ import annotations

import argparse
import dataclasses
import json
from dataclasses import dataclass, field
from pathlib import Path

import polars as pl

from gymml.utils.config import RunConfig, load_config

ML_ROOT = Path(__file__).resolve().parents[3]

LIFTS: tuple[str, ...] = ("squat", "bench", "deadlift")
LIFT_LETTER = {"squat": "S", "bench": "B", "deadlift": "D"}
EXCLUDED_PLACES: tuple[str, ...] = ("DQ", "DD", "G", "NS")

# Katman tanımı (P049 kalibrasyon tablosu da bunu kullanır). Sol kapalı, sağ açık aralıklar.
AGE_BAND_EDGES: tuple[float, ...] = (14, 19, 24, 35, 40, 50, 60, 70, 86)
BW_BAND_EDGES: tuple[float, ...] = (30, 50, 60, 70, 80, 90, 100, 110, 125, 140, 250)


@dataclass(frozen=True)
class CohortConfig:
    sexes: tuple[str, ...] = ("M", "F")
    # Wraps kategorisi yalnızca squat'ı etkiler (dizlik sargısı); bench/deadlift için Raw sayılır.
    equipment: tuple[str, ...] = ("Raw", "Wraps")
    age_min: float = 14.0
    age_max: float = 85.0
    bw_min: float = 30.0
    bw_max: float = 250.0
    # Yaş boşsa AgeClass orta noktası kullanılsın mı? Etki eda.md'de ölçülür; karar orada.
    impute_age_from_class: bool = False
    min_lift_kg: float = 15.0
    # Fiziksel üst sınırlar: ham (Raw) dünya rekorlarının biraz üstü ve vücut ağırlığı katı.
    max_lift_kg: dict[str, float] = field(
        default_factory=lambda: {"squat": 520.0, "bench": 380.0, "deadlift": 480.0}
    )
    max_ratio_bw: dict[str, float] = field(
        default_factory=lambda: {"squat": 5.0, "bench": 4.0, "deadlift": 5.5}
    )
    # SBD ortak tablosunda veri giriş hatası işareti (oranlar bu aralığın dışındaysa atılır).
    bench_to_squat: tuple[float, float] = (0.3, 1.5)
    deadlift_to_squat: tuple[float, float] = (0.6, 2.2)


def age_class_midpoint(age_class: pl.Expr) -> pl.Expr:
    """`"40-44"` → 42.0; açık uçlu `"90-999"` gibi sınıflar yaş süzgecinde zaten elenir."""
    parts = age_class.str.split_exact("-", 1)
    lo = parts.struct.field("field_0").cast(pl.Float64, strict=False)
    hi = parts.struct.field("field_1").cast(pl.Float64, strict=False)
    return (lo + hi) / 2


def band_labels(edges: tuple[float, ...]) -> list[str]:
    return [f"{int(a)}-{int(b) - 1}" for a, b in zip(edges[:-1], edges[1:], strict=True)]


def band(col: str, edges: tuple[float, ...]) -> pl.Expr:
    """Sol kapalı, sağ açık aralık etiketi; aralık dışı → null."""
    x = pl.col(col)
    expr = pl.when(pl.lit(False)).then(pl.lit(None, dtype=pl.String))
    for (a, b), label in zip(
        zip(edges[:-1], edges[1:], strict=True), band_labels(edges), strict=True
    ):
        expr = expr.when((x >= a) & (x < b)).then(pl.lit(label))
    return expr.otherwise(None).alias(f"{col}_band")


def clean_wide(df: pl.DataFrame, cfg: CohortConfig) -> tuple[pl.DataFrame, list[dict]]:
    """Kayıt (yarışma) düzeyindeki süzgeçler. Akış tablosunu da döndürür."""
    flow: list[dict] = [{"step": "girdi (opl.parquet)", "rows": df.height}]

    def step(name: str, frame: pl.DataFrame) -> pl.DataFrame:
        flow.append({"step": name, "rows": frame.height})
        return frame

    df = step("sex ∈ {M,F}", df.filter(pl.col("sex").is_in(list(cfg.sexes))))
    df = step(
        f"equipment ∈ {{{','.join(cfg.equipment)}}}",
        df.filter(pl.col("equipment").is_in(list(cfg.equipment))),
    )
    df = step(
        "diskalifiye/doping/misafir/gelmedi hariç",
        df.filter(pl.col("place").is_not_null() & ~pl.col("place").is_in(list(EXCLUDED_PLACES))),
    )
    age = pl.col("age").cast(pl.Float64)
    if cfg.impute_age_from_class:
        df = df.with_columns(
            age_imputed=age.is_null() & age_class_midpoint(pl.col("age_class")).is_not_null(),
            age=pl.coalesce(age, age_class_midpoint(pl.col("age_class"))),
        )
    else:
        df = df.with_columns(age_imputed=pl.lit(False), age=age)
    df = step(
        "yaş biliniyor" + (" (AgeClass orta noktası dahil)" if cfg.impute_age_from_class else ""),
        df.filter(pl.col("age").is_not_null()),
    )
    df = step(
        f"yaş {cfg.age_min:g}–{cfg.age_max:g}",
        df.filter(pl.col("age").is_between(cfg.age_min, cfg.age_max)),
    )
    df = step(
        f"vücut ağırlığı {cfg.bw_min:g}–{cfg.bw_max:g} kg",
        df.filter(pl.col("bodyweight_kg").cast(pl.Float64).is_between(cfg.bw_min, cfg.bw_max)),
    )
    return df, flow


def to_long(df: pl.DataFrame, cfg: CohortConfig) -> pl.DataFrame:
    """Kayıt başına kaldırış satırları; başarılı (> 0) kaldırışlar."""
    frames = []
    for lift in LIFTS:
        frames.append(
            df.filter(pl.col("event").str.contains(LIFT_LETTER[lift])).select(
                "athlete_id",
                pl.col("date").dt.year().alias("year"),
                "sex",
                pl.col("age").cast(pl.Float64),
                "age_imputed",
                pl.col("bodyweight_kg").cast(pl.Float64),
                pl.lit(lift).alias("lift"),
                pl.col(f"{lift}_kg").cast(pl.Float64).alias("value_kg"),
                "tested",
                "federation",
                "event",
                # Wraps yalnızca squat için anlamlı.
                ((pl.col("equipment") == "Wraps") & pl.lit(lift == "squat")).alias("wraps"),
            )
        )
    return pl.concat(frames).filter(pl.col("value_kg") > 0)


def outlier_mask(df: pl.DataFrame, cfg: CohortConfig) -> pl.Expr:
    """True = fiziksel olarak makul (tutulur)."""
    max_abs = pl.col("lift").replace_strict(cfg.max_lift_kg, return_dtype=pl.Float64)
    max_ratio = pl.col("lift").replace_strict(cfg.max_ratio_bw, return_dtype=pl.Float64)
    return (
        (pl.col("value_kg") >= cfg.min_lift_kg)
        & (pl.col("value_kg") <= max_abs)
        & (pl.col("value_kg") / pl.col("bodyweight_kg") <= max_ratio)
    )


def best_per_year(long: pl.DataFrame) -> pl.DataFrame:
    """Sporcu × yıl × kaldırış × wraps başına en iyi kayıt (o kaydın yaşı ve kilosuyla)."""
    keys = ["athlete_id", "year", "lift", "wraps"]
    return long.sort(
        [*keys, "value_kg", "bodyweight_kg"], descending=[False] * 4 + [True, False]
    ).unique(subset=keys, keep="first", maintain_order=True)


def add_weights(df: pl.DataFrame) -> pl.DataFrame:
    """Ters-frekans: sporcunun bir kaldırıştaki (wraps ayrımıyla) yıl kayıtlarının toplamı 1."""
    n = pl.len().over(["athlete_id", "lift", "wraps"])
    return df.with_columns(weight=(1.0 / n).cast(pl.Float64))


def sbd_joint(wide: pl.DataFrame, cfg: CohortConfig) -> tuple[pl.DataFrame, int]:
    """SBD üçlüsü aynı yarışmada tam olan kayıtlar; sporcu × yıl başına en iyi toplam.

    Dönüş: (tablo, oran tutarsızlığı nedeniyle atılan satır sayısı).
    """
    sbd = wide.filter(
        (pl.col("event") == "SBD")
        & (pl.col("squat_kg") > 0)
        & (pl.col("bench_kg") > 0)
        & (pl.col("deadlift_kg") > 0)
    ).select(
        "athlete_id",
        pl.col("date").dt.year().alias("year"),
        "sex",
        pl.col("age").cast(pl.Float64),
        "age_imputed",
        pl.col("bodyweight_kg").cast(pl.Float64),
        *[pl.col(f"{lift}_kg").cast(pl.Float64) for lift in LIFTS],
        "tested",
        "federation",
        (pl.col("equipment") == "Wraps").alias("wraps"),
    )
    ok = pl.lit(True)
    for lift in LIFTS:
        v = pl.col(f"{lift}_kg")
        ok = (
            ok
            & (v >= cfg.min_lift_kg)
            & (v <= cfg.max_lift_kg[lift])
            & (v / pl.col("bodyweight_kg") <= cfg.max_ratio_bw[lift])
        )
    b_s = pl.col("bench_kg") / pl.col("squat_kg")
    d_s = pl.col("deadlift_kg") / pl.col("squat_kg")
    consistent = b_s.is_between(*cfg.bench_to_squat) & d_s.is_between(*cfg.deadlift_to_squat)
    sbd = sbd.filter(ok)
    dropped = sbd.filter(~consistent).height
    sbd = sbd.filter(consistent).with_columns(
        total_kg=pl.col("squat_kg") + pl.col("bench_kg") + pl.col("deadlift_kg")
    )
    keys = ["athlete_id", "year", "wraps"]
    sbd = sbd.sort([*keys, "total_kg"], descending=[False, False, False, True]).unique(
        subset=keys, keep="first", maintain_order=True
    )
    n = pl.len().over(["athlete_id", "wraps"])
    return sbd.with_columns(weight=(1.0 / n).cast(pl.Float64)), dropped


@dataclass
class Cohort:
    long: pl.DataFrame
    sbd: pl.DataFrame
    flow: list[dict]
    sbd_inconsistent_dropped: int


def build(opl: pl.DataFrame, cfg: CohortConfig) -> Cohort:
    wide, flow = clean_wide(opl, cfg)
    long = to_long(wide, cfg)
    flow.append({"step": "uzun biçim, başarılı kaldırış > 0", "rows": long.height})
    long = long.filter(outlier_mask(long, cfg))
    flow.append({"step": "aykırı değer (mutlak sınır, kilo katı) hariç", "rows": long.height})
    long = best_per_year(long)
    flow.append({"step": "sporcu × yıl × kaldırış en iyisi", "rows": long.height})
    long = add_weights(long).with_columns(
        band("age", AGE_BAND_EDGES), band("bodyweight_kg", BW_BAND_EDGES)
    )
    sbd, dropped = sbd_joint(wide, cfg)
    return Cohort(long=long, sbd=sbd, flow=flow, sbd_inconsistent_dropped=dropped)


def write(cohort: Cohort, out_dir: Path, cfg: CohortConfig) -> None:
    out_dir.mkdir(parents=True, exist_ok=True)
    cohort.long.write_parquet(out_dir / "cohort_long.parquet", compression="zstd")
    cohort.sbd.write_parquet(out_dir / "cohort_sbd.parquet", compression="zstd")
    meta = {
        "config": dataclasses.asdict(cfg),
        "flow": cohort.flow,
        "sbd_rows": cohort.sbd.height,
        "sbd_inconsistent_dropped": cohort.sbd_inconsistent_dropped,
    }
    (out_dir / "cohort_flow.json").write_text(
        json.dumps(meta, indent=2, ensure_ascii=False), encoding="utf-8"
    )


def run(config_path: Path | None = None, cfg: CohortConfig | None = None) -> Cohort:
    run_cfg: RunConfig = load_config(config_path or ML_ROOT / "configs/smoke.yaml")
    cfg = cfg or CohortConfig()
    opl = pl.read_parquet(ML_ROOT / run_cfg.data.opl_parquet)
    cohort = build(opl, cfg)
    write(cohort, ML_ROOT / run_cfg.paths.processed, cfg)
    for row in cohort.flow:
        print(f"{row['rows']:>10,}  {row['step']}")
    return cohort


def main() -> None:
    argparse.ArgumentParser(prog="gymml.data.cohort").parse_args()
    run()


if __name__ == "__main__":
    main()
