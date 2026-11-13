"""Dış doğrulama: van den Hoek 2024 90. yüzdelik göreli güç değerleri (data/external/)."""

from __future__ import annotations

import numpy as np
import polars as pl

from gymml.data.cohort import ML_ROOT
from gymml.eval.interface import DistributionModel

VDH_PATH = ML_ROOT / "data/external/van_den_hoek_2024.csv"
AGE_GROUPS = {"18-35": (18.0, 35.0), ">80": (80.0, 200.0)}
GATED_GROUP = "18-35"
TOLERANCE = 0.03  # §4.3: ±%3


def load_vdh() -> pl.DataFrame:
    return pl.read_csv(VDH_PATH)


def pooled_ratio_quantile(
    model: DistributionModel, x: pl.DataFrame, p: float, iters: int = 50
) -> float:
    """Modelin, verilen kişiler (x) üzerinden toplu (kilo sınıfları birleşik) göreli güç
    dağılımında p yüzdeliği: ortalama_i F(r · bw_i | x_i) = p denklemini ikiye bölmeyle çözer."""
    bw = x["bodyweight_kg"].to_numpy()
    lo, hi = 0.0, 10.0
    for _ in range(iters):
        mid = (lo + hi) / 2
        if float(np.mean(model.cdf(x, mid * bw))) < p:
            lo = mid
        else:
            hi = mid
    return (lo + hi) / 2


def _empirical(x: pl.DataFrame, p: float) -> float | None:
    if "value_kg" not in x.columns:
        return None
    return float((x["value_kg"] / x["bodyweight_kg"]).quantile(p))


def compare(model: DistributionModel, lift: str, people: pl.DataFrame) -> pl.DataFrame:
    """`people`: referans kişilerin x sütunları (doğrulama kümesi); satır başına model ve fark."""
    rows = []
    for r in load_vdh().filter(pl.col("lift") == lift).iter_rows(named=True):
        lo, hi = AGE_GROUPS[r["age_group"]]
        x = people.filter((pl.col("sex") == r["sex"]) & pl.col("age").is_between(lo, hi))
        if x.height == 0:
            continue
        est = pooled_ratio_quantile(model, x, r["percentile"] / 100)
        rel = est / r["ratio_bw"] - 1
        rows.append(
            {
                "sex": r["sex"],
                "lift": lift,
                "age_group": r["age_group"],
                "n": x.height,
                "vdh": r["ratio_bw"],
                "model_oran": est,
                # Aynı kişilerde ağırlıksız ampirik değer: tahmin edilen nicelik (sporcu başına
                # eşit ağırlık) ile vdH'nin niceliği (tüm yarışma kayıtları) arasındaki fark için.
                "veri_ağırlıksız": _empirical(x, r["percentile"] / 100),
                "fark_%": rel * 100,
                "geçti": abs(rel) <= TOLERANCE if r["age_group"] == GATED_GROUP else None,
            }
        )
    return pl.DataFrame(rows)
