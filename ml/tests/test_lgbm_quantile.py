"""P051 Aday B (LightGBM çeyreklik) birim testleri — küçük sentetik veriyle."""

from __future__ import annotations

import numpy as np
import polars as pl
import pytest

from gymml.eval.interface import QUANTILES, DistributionModel
from gymml.models.lgbm_quantile import LGBMQuantile, pinball_objective

SIGMA = 0.15


def _synthetic(n: int = 4000, seed: int = 0) -> pl.DataFrame:
    rng = np.random.default_rng(seed)
    sex = rng.choice(["M", "F"], n)
    age = rng.uniform(18, 70, n)
    bw = rng.uniform(50, 130, n)
    mu = np.where(sex == "M", 1.9, 1.4) + (2 / 3) * np.log(bw) - 0.0004 * (age - 30) ** 2
    y = np.round(np.exp(mu + SIGMA * rng.standard_normal(n)) / 2.5) * 2.5
    return pl.DataFrame(
        {"sex": sex, "age": age, "bodyweight_kg": bw, "value_kg": y, "weight": np.ones(n)}
    )


@pytest.fixture(scope="module")
def fitted() -> dict[bool, LGBMQuantile]:
    df = _synthetic()
    kw = {"min_data_in_leaf": 50, "num_threads": 1}  # üretim tur sayısı (400)
    return {mono: LGBMQuantile(monotone=mono, **kw).fit(df) for mono in (True, False)}


def _x(sex: str, age, bw) -> pl.DataFrame:
    age, bw = np.broadcast_arrays(np.asarray(age, float), np.asarray(bw, float))
    return pl.DataFrame({"sex": [sex] * age.size, "age": age.ravel(), "bodyweight_kg": bw.ravel()})


def test_implements_interface(fitted):
    m = fitted[True]
    assert isinstance(m, DistributionModel)
    assert len(m.models) == len(QUANTILES) == 19
    assert m.name == "lgbm_mono" and fitted[False].name == "lgbm_free"


def test_pinball_objective_gradient():
    import lightgbm as lgb

    ds = lgb.Dataset(np.zeros((3, 1)), np.array([0.0, 1.0, 2.0]), weight=np.array([1.0, 2.0, 1.0]))
    ds.construct()
    g, h = pinball_objective(0.9)(np.array([1.0, 1.0, 1.0]), ds)
    # z < f → 1 − q ; z ≥ f → −q ; ağırlıklı
    np.testing.assert_allclose(g, [0.1, -1.8, -0.9])
    np.testing.assert_allclose(h, [1.0, 2.0, 1.0])


def test_quantiles_sorted_and_cdf_consistent(fitted):
    m = fitted[False]
    x = _x("M", np.full(50, 30.0), np.linspace(55, 125, 50))
    q = m.quantile(x, QUANTILES)
    assert q.shape == (50, 19)
    assert np.all(np.diff(q, axis=1) >= 0)
    for k in (2, 9, 16):
        np.testing.assert_allclose(m.cdf(x, q[:, k]), QUANTILES[k], atol=1e-6)


def test_crossing_rate_reported(fitted):
    for m in fitted.values():
        assert 0.0 <= m.crossing_rate <= 1.0


def test_median_close_to_truth(fitted):
    m = fitted[True]
    x = _x("M", [30.0], [90.0])
    truth = np.exp(1.9 + (2 / 3) * np.log(90.0))
    assert abs(m.quantile(x, np.array([0.5]))[0, 0] / truth - 1) < 0.06


def test_monotone_quantiles_non_decreasing_in_bodyweight(fitted):
    m = fitted[True]
    bws = np.linspace(50, 130, 81)
    for sex in ("M", "F"):
        raw = m.raw_quantiles(_x(sex, np.full(len(bws), 35.0), bws))
        assert np.all(np.diff(raw, axis=0) >= -1e-9)


def test_tail_extrapolation_beyond_5_95(fitted):
    m = fitted[True]
    x = _x("F", [40.0], [70.0])
    q = m.quantile(x, np.array([0.01, 0.05, 0.5, 0.95, 0.99]))[0]
    assert np.all(np.isfinite(q)) and q[0] > 0
    assert q[0] < q[1] < q[2] < q[3] < q[4]
    # Kuyruk log-lojit ölçeğinde doğrusal: P1 aralığı P5'e göre makul (aşırı patlamıyor).
    assert q[4] / q[3] < 1.3 and q[1] / q[0] < 1.3  # gerçek oran ≈ 1.11


def test_size_and_inference_measured(fitted):
    m = fitted[True]
    assert m.size_bytes() > 0
    assert m.single_inference_ms(_x("M", [30.0], [80.0]), repeats=3) > 0
