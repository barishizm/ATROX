"""Ortak metrikler: pinball, CRPS yaklaşımı, PIT, katman kapsaması (docs/03-ML-MODEL.md §4.3)."""

from __future__ import annotations

from dataclasses import dataclass

import numpy as np
import polars as pl

from gymml.data.cohort import AGE_BAND_EDGES, BW_BAND_EDGES, band
from gymml.eval.interface import QUANTILES, DistributionModel

MIN_STRATUM_N = 500
COVERAGE_QUANTILES = np.round(np.arange(1, 10) / 10, 2)  # 0.1 … 0.9
COVERAGE_GATE_PP = 2.0
# Kapı (§4.3, 2026-11-13 onayı): sapma ≤ max(2 puan, gürültü bandı); bandı aşan katman oranı ≤ %10.
MAX_STRATA_OUTSIDE_SHARE = 0.10
PIT_BINS = 10
# Kayıtlar 2.5 kg adımlarla yuvarlanır; PIT için gözlem ±yarım adım titreştirilir.
ROUNDING_STEP_KG = 2.5
# Gürültü bandı: katman başına 9 çeyrekte Bonferroni, %95 aile düzeyi → z = Φ⁻¹(1 − 0.05/18).
NOISE_Z = 2.77


def pinball(y: np.ndarray, qhat: np.ndarray, q: np.ndarray, w: np.ndarray | None = None) -> float:
    """Çeyrekler üzerinden ortalama pinball kaybı (kg). `qhat`: (n, len(q))."""
    diff = y[:, None] - qhat
    loss = np.maximum(q * diff, (q - 1) * diff).mean(axis=1)
    return float(np.average(loss, weights=w))


def pinball_per_quantile(
    y: np.ndarray, qhat: np.ndarray, q: np.ndarray, w: np.ndarray | None = None
) -> np.ndarray:
    diff = y[:, None] - qhat
    loss = np.maximum(q * diff, (q - 1) * diff)
    return np.average(loss, axis=0, weights=w)


def crps_approx(
    y: np.ndarray, qhat: np.ndarray, q: np.ndarray, w: np.ndarray | None = None
) -> float:
    """CRPS ≈ 2 · ortalama pinball (eşit aralıklı çeyrek ızgarası üzerinden)."""
    return 2.0 * pinball(y, qhat, q, w)


def randomized_pit(
    model: DistributionModel, x: pl.DataFrame, y: np.ndarray, seed: int = 0
) -> np.ndarray:
    rng = np.random.default_rng(seed)
    jitter = rng.uniform(-ROUNDING_STEP_KG / 2, ROUNDING_STEP_KG / 2, size=len(y))
    return model.cdf(x, y + jitter)


@dataclass(frozen=True)
class PitSummary:
    hist: list[float]  # ağırlıklı bin oranları
    ks: float  # tekdüze dağılıma Kolmogorov–Smirnov uzaklığı
    max_bin_dev: float  # |bin oranı − 1/B| en büyüğü


def pit_summary(pit: np.ndarray, w: np.ndarray | None = None) -> PitSummary:
    w = np.ones_like(pit) if w is None else w
    hist, _ = np.histogram(pit, bins=PIT_BINS, range=(0, 1), weights=w)
    hist = hist / hist.sum()
    order = np.argsort(pit)
    cdf = np.cumsum(w[order]) / w.sum()
    ks = float(np.max(np.abs(cdf - pit[order])))
    return PitSummary(hist.tolist(), ks, float(np.max(np.abs(hist - 1 / PIT_BINS))))


def coverage_table(model: DistributionModel, df: pl.DataFrame, seed: int = 0) -> pl.DataFrame:
    """Katman (cinsiyet × yaş bandı × kilo bandı, n ≥ 500) başına 10–90 çeyreklerinde
    gözlenen − beklenen kapsama farkının en büyüğü (yüzde puan)."""
    d = df.with_columns(band("age", AGE_BAND_EDGES), band("bodyweight_kg", BW_BAND_EDGES))
    y = d["value_kg"].to_numpy()
    rng = np.random.default_rng(seed)
    y_j = y + rng.uniform(-ROUNDING_STEP_KG / 2, ROUNDING_STEP_KG / 2, size=len(y))
    qhat = model.quantile(d, COVERAGE_QUANTILES)
    hits = (y_j[:, None] <= qhat).astype(float)
    cols = {f"c{int(q * 100)}": hits[:, i] for i, q in enumerate(COVERAGE_QUANTILES)}
    d = d.with_columns(**{k: pl.Series(v) for k, v in cols.items()})
    w = pl.col("weight")
    agg = (
        d.filter(pl.col("age_band").is_not_null() & pl.col("bodyweight_kg_band").is_not_null())
        .group_by("sex", "age_band", "bodyweight_kg_band")
        .agg(
            pl.len().alias("n"),
            (w.sum() ** 2 / (w**2).sum()).alias("n_eff"),
            *[((pl.col(k) * w).sum() / w.sum()).alias(k) for k in cols],
        )
        .filter(pl.col("n") >= MIN_STRATUM_N)
    )
    devs = [(pl.col(f"c{int(q * 100)}") - q).abs() * 100 for q in COVERAGE_QUANTILES]
    # q = 0.5'te örnekleme gürültüsü (Kish etkin örneklem); §4.3 kapısının parçası.
    noise = NOISE_Z * 100 * (0.25 / pl.col("n_eff")).sqrt()
    return (
        agg.with_columns(max_dev_pp=pl.max_horizontal(devs), noise_pp=noise)
        .with_columns(
            within_noise=pl.col("max_dev_pp")
            <= pl.max_horizontal(pl.lit(COVERAGE_GATE_PP), "noise_pp")
        )
        .sort("sex", "age_band", "bodyweight_kg_band")
    )


def evaluate(model: DistributionModel, df: pl.DataFrame) -> dict:
    """Bir kaldırışın değerlendirme kümesi üzerinde tüm olasılıksal metrikler."""
    y = df["value_kg"].to_numpy()
    w = df["weight"].to_numpy()
    qhat = model.quantile(df, QUANTILES)
    pit = pit_summary(randomized_pit(model, df, y), w)
    cov = coverage_table(model, df)
    return {
        "n": len(y),
        "pinball": pinball(y, qhat, QUANTILES, w),
        "crps": crps_approx(y, qhat, QUANTILES, w),
        "crossing_rate": float(np.mean(np.any(np.diff(qhat, axis=1) < 0, axis=1))),
        "pit_hist": pit.hist,
        "pit_ks": pit.ks,
        "pit_max_bin_dev": pit.max_bin_dev,
        "strata": cov.height,
        "strata_max_dev_pp": float(cov["max_dev_pp"].max()) if cov.height else float("nan"),
        "strata_failing": int((cov["max_dev_pp"] > COVERAGE_GATE_PP).sum()),
        "strata_failing_noise_aware": int((~cov["within_noise"]).sum()) if cov.height else 0,
        "strata_outside_share": float((~cov["within_noise"]).mean()) if cov.height else 1.0,
        "coverage_gate_pass": bool(
            cov.height and (~cov["within_noise"]).mean() <= MAX_STRATA_OUTSIDE_SHARE
        ),
    }
