"""P052 Aday C: BCPE/SHASH matematiği (scipy'ye karşı), kopula, kırpma, küçük uçtan uca eğitim."""

from __future__ import annotations

import numpy as np
import polars as pl
import pytest
import torch
from scipy import integrate, stats

from gymml.eval import sanity
from gymml.eval.interface import QUANTILES, DistributionModel
from gymml.models import neural as nn_

# ---------------------------------------------------------------- güç-üstel ve BCPE


@pytest.mark.parametrize("tau", [1.0, 1.5, 2.0, 3.5, 8.0])
def test_pe_matches_scipy_gennorm(tau):
    c = nn_.pe_c(tau)
    ref = stats.gennorm(beta=tau, scale=c * 2 ** (1 / tau))
    z = np.linspace(-4, 4, 41)
    np.testing.assert_allclose(np.exp(nn_.pe_logpdf(z, tau)), ref.pdf(z), rtol=1e-10)
    np.testing.assert_allclose(nn_.pe_cdf(z, tau), ref.cdf(z), atol=1e-12)
    p = np.array([0.01, 0.2, 0.5, 0.77, 0.999])
    np.testing.assert_allclose(nn_.pe_ppf(p, tau), ref.ppf(p), rtol=1e-8, atol=1e-10)
    assert ref.var() == pytest.approx(1.0)  # birim varyans


def test_bcpe_reduces_to_lognormal():
    mu, sigma = 120.0, 0.2
    ref = stats.lognorm(s=sigma, scale=mu)
    y = np.linspace(40, 300, 30)
    np.testing.assert_allclose(
        np.exp(nn_.bcpe_logpdf(y, mu, sigma, 0.0, 2.0)), ref.pdf(y), rtol=1e-6
    )
    np.testing.assert_allclose(nn_.bcpe_cdf(y, mu, sigma, 0.0, 2.0), ref.cdf(y), atol=1e-7)
    np.testing.assert_allclose(
        nn_.bcpe_ppf(QUANTILES, mu, sigma, 0.0, 2.0), ref.ppf(QUANTILES), rtol=1e-6
    )


@pytest.mark.parametrize("nu,tau", [(0.6, 1.4), (-0.7, 3.0), (1.5, 2.0), (-2.0, 1.2)])
def test_bcpe_density_cdf_quantile_consistent(nu, tau):
    mu, sigma = 100.0, 0.25
    pdf = lambda t: np.exp(nn_.bcpe_logpdf(t, mu, sigma, nu, tau))  # noqa: E731
    total, _ = integrate.quad(pdf, 1e-9, np.inf, limit=400)
    assert total == pytest.approx(1.0, abs=1e-6)
    for y in (60.0, 100.0, 150.0):
        part, _ = integrate.quad(pdf, 1e-9, y, limit=400)
        assert nn_.bcpe_cdf(y, mu, sigma, nu, tau) == pytest.approx(part, abs=1e-6)
    q = nn_.bcpe_ppf(QUANTILES, mu, sigma, nu, tau)
    np.testing.assert_allclose(nn_.bcpe_cdf(q, mu, sigma, nu, tau), QUANTILES, atol=1e-8)
    assert np.all(np.diff(q) > 0)
    # Kesme terimi küçükken (σ|ν| ≤ 0.15) medyan ≈ μ.
    if sigma * abs(nu) <= 0.15:
        assert nn_.bcpe_ppf(0.5, mu, sigma, nu, tau) == pytest.approx(mu, rel=1e-3)


def test_bcpe_torch_matches_numpy():
    rng = np.random.default_rng(0)
    y = rng.uniform(40, 250, 50)
    mu, sigma, nu, tau = 120.0, 0.22, rng.uniform(-1, 1.5, 50), rng.uniform(1.2, 6, 50)
    ref = nn_.bcpe_logpdf(y, mu, sigma, nu, tau)
    t = lambda a: torch.as_tensor(np.broadcast_to(a, y.shape).copy(), dtype=torch.float64)  # noqa: E731
    got = nn_.t_bcpe_logpdf(t(y), t(mu), t(sigma), t(nu), t(tau)).numpy()
    np.testing.assert_allclose(got, ref, rtol=1e-9)
    np.testing.assert_allclose(
        nn_.t_bcpe_z(t(y), t(mu), t(sigma), t(nu)).numpy(), nn_.bcpe_z(y, mu, sigma, nu), rtol=1e-10
    )


# ---------------------------------------------------------------- sinh-arcsinh


def test_shash_reduces_to_lognormal_and_is_consistent():
    m, s = np.log(120.0), 0.2
    ref = stats.lognorm(s=s, scale=120.0)
    y = np.linspace(40, 300, 30)
    np.testing.assert_allclose(np.exp(nn_.shash_logpdf(y, m, s, 0.0, 1.0)), ref.pdf(y), rtol=1e-10)
    np.testing.assert_allclose(nn_.shash_cdf(y, m, s, 0.0, 1.0), ref.cdf(y), atol=1e-12)
    eps, delta = 0.4, 1.6
    pdf = lambda t: np.exp(nn_.shash_logpdf(t, m, s, eps, delta))  # noqa: E731
    assert integrate.quad(pdf, 5.0, 5000.0, points=[120.0], limit=400)[0] == pytest.approx(
        1.0, abs=1e-6
    )
    q = nn_.shash_ppf(QUANTILES, m, s, eps, delta)
    np.testing.assert_allclose(nn_.shash_cdf(q, m, s, eps, delta), QUANTILES, atol=1e-10)
    t = lambda a: torch.as_tensor(np.broadcast_to(a, y.shape).copy(), dtype=torch.float64)  # noqa: E731
    np.testing.assert_allclose(
        nn_.t_shash_logpdf(t(y), t(m), t(s), t(eps), t(delta)).numpy(),
        nn_.shash_logpdf(y, m, s, eps, delta),
        rtol=1e-10,
    )


# ---------------------------------------------------------------- korelasyon / kopula


def test_cholesky_corr_and_copula_match_mvn():
    rng = np.random.default_rng(1)
    raw = torch.as_tensor(rng.normal(size=(20, 3)), dtype=torch.float64)
    L = nn_.t_cholesky_corr(raw)
    R = (L @ L.transpose(1, 2)).numpy()
    np.testing.assert_allclose(np.diagonal(R, axis1=1, axis2=2), 1.0, atol=1e-12)
    assert np.all(np.linalg.eigvalsh(R) > 0)
    z = rng.normal(size=(20, 3))
    got = nn_.t_copula_nll(L, torch.as_tensor(z)).numpy()
    ref = np.array(
        [
            -(stats.multivariate_normal(cov=R[i]).logpdf(z[i]) - stats.norm.logpdf(z[i]).sum())
            for i in range(20)
        ]
    )
    np.testing.assert_allclose(got, ref, rtol=1e-9, atol=1e-12)


# ---------------------------------------------------------------- kırpma kuralı


def test_input_clip_rule():
    clip = nn_.InputClip(age=(14.0, 80.0), bw={"M": (47.0, 180.0), "F": (40.0, 155.0)})
    x = pl.DataFrame(
        {
            "sex": ["M", "M", "F", "F"],
            "age": [5.0, 95.0, 30.0, 30.0],
            "bodyweight_kg": [300.0, 20.0, 20.0, 60.0],
        }
    )
    f = clip.features(x)
    np.testing.assert_allclose(f[:, 0], [1, 1, 0, 0])
    np.testing.assert_allclose(f[:, 1], (np.array([14, 80, 30, 30]) - 35) / 15)
    np.testing.assert_allclose(f[:, 2], (np.log([180, 47, 40, 60]) - np.log(80)) / 0.3)
    with pytest.raises(ValueError):
        clip.features(x.with_columns(pl.lit("X").alias("sex")))
    # Veriden türetme: en küçük – en büyük, 0.5'e dışa yuvarlama.
    df = pl.DataFrame(
        {
            "sex": ["M"] * 1001,
            "age": np.linspace(20.2, 70.2, 1001),
            "bodyweight_kg": np.linspace(60.3, 160.3, 1001),
        }
    )
    c2 = nn_.InputClip.from_frames([df])
    assert c2.age == (20.0, 70.5) and c2.bw["M"] == (60.0, 160.5)


# ---------------------------------------------------------------- küçük uçtan uca eğitim

R_TRUE = np.array([[1.0, 0.6, 0.8], [0.6, 1.0, 0.6], [0.8, 0.6, 1.0]])
A = {"squat": {"M": 1.8, "F": 1.3}, "bench": {"M": 1.5, "F": 0.8}, "deadlift": {"M": 2.0, "F": 1.5}}


def _synthetic(n: int, seed: int = 0):
    rng = np.random.default_rng(seed)
    sex = rng.choice(["M", "F"], n)
    age = rng.uniform(16, 70, n)
    bw = np.where(sex == "M", rng.normal(88, 15, n), rng.normal(68, 12, n)).clip(45, 160)
    z = rng.multivariate_normal(np.zeros(3), R_TRUE, n)
    ids = np.array([f"a{i:06d}" for i in range(n)])
    out, sbd = (
        {},
        {"athlete_id": ids, "sex": sex, "age": age, "bodyweight_kg": bw, "weight": np.ones(n)},
    )
    for j, lift in enumerate(nn_.LIFTS):
        a = np.array([A[lift][s] for s in sex])
        logy = a + 0.66 * np.log(bw) - 0.0003 * (age - 30) ** 2 + 0.18 * z[:, j]
        y = np.round(np.exp(logy) / 2.5) * 2.5
        sbd[f"{lift}_kg"] = y
        out[lift] = pl.DataFrame(
            {
                "athlete_id": ids,
                "sex": sex,
                "age": age,
                "bodyweight_kg": bw,
                "value_kg": y,
                "weight": np.ones(n),
                "lift": [lift] * n,
                "split": ["train"] * n,
            }
        )
    return out, pl.DataFrame(sbd)


@pytest.fixture(scope="module", params=["bcpe", "shash"])
def trained(request):
    frames, sbd = _synthetic(6000)
    cfg = nn_.NeuralConfig(
        head=request.param,
        hidden=(16, 16),
        batch_size=1024,
        max_epochs=40,
        patience=6,
        corr_epochs=40,
        lr=1e-2,
        penalty_rows=256,
    )
    return nn_.NeuralDistributional(cfg).fit(frames, sbd), frames, sbd


def test_trained_model_implements_interface_and_fits(trained):
    joint, frames, _ = trained
    m = nn_.NeuralLift(joint).fit(frames["bench"])
    assert isinstance(m, DistributionModel)
    assert joint.n_params() < 50_000
    df = frames["bench"]
    q = m.quantile(df, QUANTILES)
    assert q.shape == (df.height, len(QUANTILES)) and np.all(np.diff(q, axis=1) > 0)
    cover = np.mean(df["value_kg"].to_numpy()[:, None] <= q, axis=0)
    np.testing.assert_allclose(cover, QUANTILES, atol=0.05)
    c = m.cdf(df, q[:, 9])
    np.testing.assert_allclose(c, 0.5, atol=1e-6)
    assert set(m.params(df[:3])) == set(nn_.HEADS[joint.cfg.head][0])


def test_correlation_recovered(trained):
    joint, _, sbd = trained
    R = joint.correlation(sbd[:500]).mean(0)
    np.testing.assert_allclose(np.diagonal(R), 1.0, atol=1e-9)
    np.testing.assert_allclose(R, R_TRUE, atol=0.08)
    assert joint.copula_nll(sbd) < -0.3  # bağımsızlığa göre belirgin kazanç


def test_out_of_range_inputs_do_not_explode(trained):
    joint, frames, _ = trained
    m = nn_.NeuralLift(joint).fit(frames["squat"])
    ages, bws = np.meshgrid([1.0, 10.0, 100.0, 150.0], [5.0, 25.0, 300.0, 1000.0])
    for sex in ("M", "F"):
        x = pl.DataFrame(
            {"sex": [sex] * ages.size, "age": ages.ravel(), "bodyweight_kg": bws.ravel()}
        )
        q = m.quantile(x, np.array([0.05, 0.5, 0.95]))
        assert np.all(np.isfinite(q)) and np.all(q > 0) and np.all(np.diff(q, axis=1) > 0)
        # Kırpma: aralık dışındaki girdi, sınır değeriyle birebir aynı çıktıyı verir.
        lo_a, hi_a = joint.clip.age
        lo_b, hi_b = joint.clip.bw[sex]
        xc = x.with_columns(
            pl.col("age").clip(lo_a, hi_a), pl.col("bodyweight_kg").clip(lo_b, hi_b)
        )
        np.testing.assert_allclose(q, m.quantile(xc, np.array([0.05, 0.5, 0.95])), rtol=1e-12)
    assert sanity.extrapolation(m, sanity.SanityConfig(), "squat").passed


def test_monotone_in_load(trained):
    joint, frames, _ = trained
    m = nn_.NeuralLift(joint).fit(frames["deadlift"])
    assert sanity.monotone_in_load(m, sanity.SanityConfig()).passed


def test_lift_view_guards(trained):
    joint, frames, _ = trained
    with pytest.raises(ValueError):
        nn_.NeuralLift(joint).fit(pl.concat([frames["bench"], frames["squat"]]))
    fresh = nn_.NeuralLift(nn_.NeuralDistributional())
    with pytest.raises(ValueError):
        fresh.fit(frames["bench"].with_columns(pl.lit("val").alias("split")))
