"""P049 değerlendirme: bölme, metrikler, akıl sağlığı, dış doğrulama, temel çizgiler."""

from __future__ import annotations

from typing import Any

import numpy as np
import polars as pl
import pytest
from scipy import stats

from gymml.eval import external, metrics, sanity
from gymml.eval.data import make_splits, splits_digest
from gymml.eval.interface import QUANTILES, DistributionModel, grid_cdf, grid_quantile
from gymml.models.baselines import (
    CellEmpirical,
    DotsEmpirical,
    dots_coefficient,
    weighted_quantiles,
)

SIGMA = 0.18


class LogNormalTruth:
    """Bilinen gerçek dağılım: log Y = a_sex + (2/3)·log bw − k·(yaş − 30)² + σ·ε."""

    name = "truth"
    A = {"M": 1.95, "F": 1.45}

    def __init__(self, age_k: float = 0.0004, bw_power: float = 2 / 3):
        self.age_k, self.bw_power = age_k, bw_power

    def mu(self, x: pl.DataFrame) -> np.ndarray:
        a = np.array([self.A[s] for s in x["sex"]])
        age = x["age"].to_numpy()
        return (
            a + self.bw_power * np.log(x["bodyweight_kg"].to_numpy()) - self.age_k * (age - 30) ** 2
        )

    def fit(self, df: pl.DataFrame) -> LogNormalTruth:
        return self

    def quantile(self, x: pl.DataFrame, q: np.ndarray) -> np.ndarray:
        return np.exp(self.mu(x)[:, None] + SIGMA * stats.norm.ppf(np.asarray(q))[None, :])

    def cdf(self, x: pl.DataFrame, y: np.ndarray) -> np.ndarray:
        return stats.norm.cdf((np.log(np.maximum(y, 1e-9)) - self.mu(x)) / SIGMA)

    def params(self, x: pl.DataFrame) -> dict[str, Any]:
        return {"mu": self.mu(x), "sigma": SIGMA}


def synthetic(n: int, seed: int = 0, model: LogNormalTruth | None = None) -> pl.DataFrame:
    rng = np.random.default_rng(seed)
    model = model or LogNormalTruth()
    x = pl.DataFrame(
        {
            "sex": rng.choice(["M", "F"], n),
            "age": rng.uniform(16, 70, n).round(1),
            "bodyweight_kg": rng.uniform(52, 125, n).round(1),
        }
    )
    y = np.exp(model.mu(x) + SIGMA * rng.standard_normal(n))
    y = np.round(y / 2.5) * 2.5  # yarışma kayıtları gibi 2.5 kg adım
    return x.with_columns(value_kg=pl.Series(y), weight=pl.lit(1.0))


def test_truth_satisfies_protocol():
    assert isinstance(LogNormalTruth(), DistributionModel)
    assert isinstance(CellEmpirical(), DistributionModel)
    assert isinstance(DotsEmpirical(), DistributionModel)


# --- bölme ---


def test_splits_grouped_deterministic_and_proportional():
    ids = pl.Series([f"a{i:05d}" for i in range(10_000)] * 3)  # her sporcu 3 kayıt
    s1, s2 = make_splits(ids, seed=1), make_splits(ids.shuffle(seed=9), seed=1)
    assert s1.height == 10_000  # sporcu başına tek satır → aynı sporcu iki bölmede olamaz
    assert splits_digest(s1) == splits_digest(s2)  # girdi sırasından bağımsız
    assert splits_digest(make_splits(ids, seed=2)) != splits_digest(s1)
    counts = dict(s1.group_by("split").len().iter_rows())
    assert counts == {"train": 7000, "val": 1500, "test": 1500}


# --- ızgara yardımcıları ---


def test_grid_quantile_and_cdf_are_inverse():
    p = np.round(np.arange(1, 200) / 200, 3)
    g = np.vstack([stats.norm.ppf(p, 100, 15), stats.norm.ppf(p, 60, 10)])
    q = np.array([0.1, 0.5, 0.9])
    qq = grid_quantile(g, p, q)
    assert qq[0] == pytest.approx(stats.norm.ppf(q, 100, 15), rel=1e-3)
    back = grid_cdf(np.repeat(g, 3, axis=0), p, qq.ravel())
    assert back == pytest.approx(np.tile(q, 2), abs=1e-3)
    assert grid_cdf(g, p, np.array([-1e9, 1e9])).tolist() == [0.0, 1.0]


def test_weighted_quantiles_respects_weights():
    v = np.array([1.0, 2.0, 3.0])
    assert weighted_quantiles(v, np.array([1.0, 1.0, 1.0]), np.array([0.5]))[0] == 2.0
    assert weighted_quantiles(v, np.array([0.0, 0.0, 1.0]), np.array([0.5]))[0] == 3.0


# --- metrikler ---


def test_pinball_known_value():
    y = np.array([10.0])
    qhat = np.array([[8.0, 12.0]])
    q = np.array([0.1, 0.9])
    # q=0.1: (10-8)*0.1 = 0.2 ; q=0.9: (10-12)*(0.9-1) = 0.2
    assert metrics.pinball(y, qhat, q) == pytest.approx(0.2)


def test_true_model_is_calibrated_and_beats_wrong_one():
    df = synthetic(60_000)
    truth = metrics.evaluate(LogNormalTruth(), df)
    wrong = metrics.evaluate(LogNormalTruth(age_k=0.0, bw_power=0.4), df)
    assert truth["pit_ks"] < 0.01
    assert truth["pit_max_bin_dev"] < 0.01
    assert truth["crossing_rate"] == 0.0
    assert truth["pinball"] < wrong["pinball"]
    assert wrong["pit_ks"] > truth["pit_ks"]


def test_coverage_table_true_model_within_noise():
    df = synthetic(80_000, seed=3)
    cov = metrics.coverage_table(LogNormalTruth(), df)
    assert cov.height > 0 and (cov["n"] >= metrics.MIN_STRATUM_N).all()
    # Katman başına %95 aile düzeyi bant: doğru modelde katmanların azı dışarıda.
    assert (~cov["within_noise"]).mean() <= 0.12
    bad = metrics.coverage_table(LogNormalTruth(bw_power=0.3), df)
    assert (~bad["within_noise"]).mean() > 0.5


# --- akıl sağlığı ---


def test_sanity_passes_on_well_behaved_model():
    # Kilo üssü < 1: aynı yükte kilo arttıkça yüzdelik düşer; yaş eğrisi 30'da tepe.
    results = sanity.run_all(LogNormalTruth(), "bench")
    assert all(r.passed for r in results), [(r.name, r.detail) for r in results if not r.passed]


def test_sanity_catches_bodyweight_and_age_violations():
    class Inverted(LogNormalTruth):
        def mu(self, x):  # ağır kişi daha zayıf + yaşla artan (tepe 80'de)
            age = x["age"].to_numpy()
            a = np.array([self.A[s] for s in x["sex"]])
            return a + 3.0 - 0.5 * np.log(x["bodyweight_kg"].to_numpy()) + 0.005 * age

    res = {r.name: r.passed for r in sanity.run_all(Inverted(), "bench")}
    assert not res["aynı yükte skor kiloyla artmıyor"]
    assert not next(v for k, v in res.items() if k.startswith("yaş eğrisi"))


def test_sanity_catches_bad_extrapolation():
    class Exploding(LogNormalTruth):
        def mu(self, x):
            return super().mu(x) + np.where(x["bodyweight_kg"].to_numpy() > 200, 5.0, 0.0)

    r = sanity.extrapolation(Exploding(), sanity.SanityConfig(), "bench")
    assert not r.passed and "fiziksel" in r.detail


# --- dış doğrulama ---


def test_pooled_ratio_quantile_recovers_known_value():
    # Kiloya oranla dağılım kiloya bağımsız (üs 1) ve yaş etkisiz → toplu 90. yüzdelik analitik.
    m = LogNormalTruth(age_k=0.0, bw_power=1.0)
    x = synthetic(5_000, model=m).filter(pl.col("sex") == "M")
    est = external.pooled_ratio_quantile(m, x, 0.9)
    assert est == pytest.approx(np.exp(m.A["M"] + SIGMA * stats.norm.ppf(0.9)), rel=1e-4)


def test_vdh_file_is_sourced():
    d = external.load_vdh()
    assert d.height == 12
    assert d["source"].str.contains("pubmed.ncbi.nlm.nih.gov/39060209").all()
    assert d["accessed"].is_not_null().all()


# --- temel çizgiler ---


def test_dots_coefficient_clamps_bodyweight():
    sex = np.array(["M", "M", "F", "F"])
    c = dots_coefficient(sex, np.array([210.0, 260.0, 150.0, 200.0]))
    assert c[0] == c[1] and c[2] == c[3]


# DOTS yaşı kullanmaz; sentetik veride yaş etkisi olduğu için daha geniş pay.
@pytest.mark.parametrize(("cls", "slack"), [(CellEmpirical, 1.15), (DotsEmpirical, 1.6)])
def test_baselines_fit_and_are_reasonable(cls, slack):
    train, val = synthetic(80_000, seed=1), synthetic(20_000, seed=2)
    m = cls().fit(train)
    q = m.quantile(val, QUANTILES)
    assert np.all(np.diff(q, axis=1) >= 0)
    res = metrics.evaluate(m, val)
    truth = metrics.evaluate(LogNormalTruth(), val)
    assert res["pit_ks"] < 0.05
    assert truth["pinball"] < res["pinball"] < slack * truth["pinball"]


def test_cell_model_falls_back_outside_bands():
    m = CellEmpirical().fit(synthetic(20_000))
    x = pl.DataFrame({"sex": ["M"], "age": [95.0], "bodyweight_kg": [300.0]})
    assert m.params(x)["cell_found"] == [False]
    assert np.isfinite(m.quantile(x, np.array([0.5]))).all()
