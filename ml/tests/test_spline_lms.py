"""P050: BCCG/BCPE dağılımlarının scipy'ye karşı doğrulanması ve Spline-LMS modelinin davranışı."""

from __future__ import annotations

import dataclasses
import math

import numpy as np
import polars as pl
import pytest
import torch
from scipy import integrate, stats

from gymml.eval.interface import DistributionModel
from gymml.models import boxcox
from gymml.models.spline_lms import SplineLMS, SplineLMSConfig
from gymml.utils.config import ML_ROOT, load_config

CASES = [
    # (μ, σ, ν, τ)
    (100.0, 0.20, 0.5, 2.0),
    (100.0, 0.25, -0.8, 1.5),
    (60.0, 0.15, 0.0, 2.5),
    (150.0, 0.30, 1.5, 3.0),
    (80.0, 0.60, 2.0, 1.2),  # kesilme belirgin: b = 1/(σν) ≈ 0.83
]
Y = np.array([30.0, 60.0, 80.0, 100.0, 120.0, 170.0, 260.0])


def z_of(y, mu, sigma, nu):
    return np.log(y / mu) / sigma if nu == 0 else ((y / mu) ** nu - 1) / (nu * sigma)


def log_jac(y, mu, sigma, nu):
    return (nu - 1) * np.log(y) - nu * np.log(mu) - np.log(sigma)


def scipy_t(family, tau, nu, sigma):
    """scipy'nin kesilmiş T dağılımı: BCCG → truncnorm, BCPE → kesilmiş gennorm."""
    b = np.inf if nu == 0 else 1 / (sigma * abs(nu))
    lo, hi = (-b, np.inf) if nu > 0 else (-np.inf, b)
    if family == "BCCG":
        return stats.truncnorm(lo, hi), lo, hi
    c = math.sqrt(2 ** (-2 / tau) * math.gamma(1 / tau) / math.gamma(3 / tau))
    base = stats.gennorm(beta=tau, scale=c * 2 ** (1 / tau))
    assert base.var() == pytest.approx(1.0, rel=1e-9)  # PE(0,1,τ) birim varyanslı
    return base, lo, hi


@pytest.mark.parametrize("family", boxcox.FAMILIES)
@pytest.mark.parametrize("mu,sigma,nu,tau", CASES)
def test_logpdf_and_cdf_match_scipy(family, mu, sigma, nu, tau):
    t, lo, hi = scipy_t(family, tau, nu, sigma)
    z = z_of(Y, mu, sigma, nu)
    inside = (z > lo) & (z < hi)
    if family == "BCCG":
        ref_logpdf = t.logpdf(z) + log_jac(Y, mu, sigma, nu)
        ref_cdf = t.cdf(z)
    else:
        mass = t.cdf(hi) - t.cdf(lo)
        ref_logpdf = t.logpdf(z) - np.log(mass) + log_jac(Y, mu, sigma, nu)
        ref_cdf = np.clip((t.cdf(z) - t.cdf(lo)) / mass, 0, 1)
    got = boxcox.logpdf(Y, mu, sigma, nu, tau, family)
    np.testing.assert_allclose(got[inside], ref_logpdf[inside], rtol=1e-9, atol=1e-9)
    assert np.all(np.isneginf(got[~inside]))
    np.testing.assert_allclose(boxcox.cdf(Y, mu, sigma, nu, tau, family), ref_cdf, atol=1e-10)


@pytest.mark.parametrize("family", boxcox.FAMILIES)
@pytest.mark.parametrize("mu,sigma,nu,tau", CASES)
def test_density_integrates_to_cdf(family, mu, sigma, nu, tau):
    def pdf(y):
        return math.exp(boxcox.logpdf(y, mu, sigma, nu, tau, family))

    total, _ = integrate.quad(pdf, 0, np.inf, limit=400)
    assert total == pytest.approx(1.0, abs=1e-6)
    for y in (0.6 * mu, mu, 1.4 * mu):
        area, _ = integrate.quad(pdf, 0, y, limit=400)
        assert boxcox.cdf(y, mu, sigma, nu, tau, family) == pytest.approx(area, abs=1e-7)


@pytest.mark.parametrize("family", boxcox.FAMILIES)
@pytest.mark.parametrize("mu,sigma,nu,tau", CASES)
def test_ppf_inverts_cdf(family, mu, sigma, nu, tau):
    p = np.array([0.001, 0.05, 0.25, 0.5, 0.75, 0.95, 0.999])
    y = boxcox.ppf(p, mu, sigma, nu, tau, family)
    assert np.all(np.diff(y) > 0) and np.all(y > 0)
    np.testing.assert_allclose(boxcox.cdf(y, mu, sigma, nu, tau, family), p, atol=1e-9)


def test_bcpe_with_tau_2_equals_bccg():
    for mu, sigma, nu, _ in CASES:
        np.testing.assert_allclose(
            boxcox.logpdf(Y, mu, sigma, nu, 2.0, "BCPE"),
            boxcox.logpdf(Y, mu, sigma, nu, 2.0, "BCCG"),
            rtol=1e-9,
        )


@pytest.mark.parametrize("family", boxcox.FAMILIES)
def test_torch_logpdf_matches_numpy(family):
    rows = [(y, *c) for c in CASES for y in Y]
    arr = np.array(rows)
    y, mu, sigma, nu, tau = arr.T
    ref = boxcox.logpdf(y, mu, sigma, nu, tau, family)
    ok = np.isfinite(ref)
    got = boxcox.torch_logpdf(
        *(torch.tensor(a[ok]) for a in (y, mu, sigma, nu, tau)), family=family
    )
    np.testing.assert_allclose(got.numpy(), ref[ok], rtol=1e-8, atol=1e-8)


def test_gammainc_gradient():
    a = torch.tensor([0.4, 0.7, 1.3], dtype=torch.float64, requires_grad=True)
    x = torch.tensor([0.3, 2.0, 0.9], dtype=torch.float64, requires_grad=True)
    assert torch.autograd.gradcheck(boxcox._GammaInc.apply, (a, x), eps=1e-6, atol=1e-5)


def test_unknown_family_rejected():
    with pytest.raises(ValueError):
        SplineLMS(SplineLMSConfig(family="LMS"))


# ------------------------------------------------------------------ model

SMALL = SplineLMSConfig(
    age_segments=5, bw_segments=4, adam_steps=100, lbfgs_rounds=8, lbfgs_iter=15
)


def synthetic(n: int = 6000, seed: int = 1) -> tuple[pl.DataFrame, callable]:
    """Bilinen gerçek: BCCG, μ = a·bw^(2/3)·exp(−k(yaş−30)²), σ = 0.18, ν = 0.5."""
    rng = np.random.default_rng(seed)
    sex = rng.choice(["M", "F"], n)
    age = rng.uniform(16, 75, n)
    bw = np.exp(rng.uniform(np.log(50), np.log(140), n))

    def mu(sex, age, bw):
        a = np.where(sex == "M", 7.0, 4.5)
        return a * bw ** (2 / 3) * np.exp(-0.0003 * (age - 30) ** 2)

    p = rng.uniform(size=n)
    y = boxcox.ppf(p, mu(sex, age, bw), 0.18, 0.5, 2.0, "BCCG")
    df = pl.DataFrame(
        {
            "athlete_id": [f"a{i // 2}" for i in range(n)],
            "sex": sex,
            "age": age,
            "bodyweight_kg": bw,
            "value_kg": y,
            "weight": np.ones(n),
        }
    )
    return df, mu


@pytest.fixture(scope="module")
def fitted():
    df, mu = synthetic()
    return SplineLMS(dataclasses.replace(SMALL, family="BCCG")).fit(df), mu


def test_model_implements_interface_and_recovers_truth(fitted):
    model, mu = fitted
    assert isinstance(model, DistributionModel)
    x = pl.DataFrame(
        {"sex": ["M", "F", "M"], "age": [25.0, 40.0, 60.0], "bodyweight_kg": [80.0, 60.0, 110.0]}
    )
    med = model.quantile(x, np.array([0.5]))[:, 0]
    true_med = mu(x["sex"].to_numpy(), x["age"].to_numpy(), x["bodyweight_kg"].to_numpy())
    np.testing.assert_allclose(med, true_med, rtol=0.04)
    p = model.params(x)
    assert np.allclose(p["sigma"], 0.18, atol=0.03)
    assert all(h["holdout_nll"] < 10 for f in model.fits.values() for h in f.history)


def test_quantiles_sorted_and_cdf_consistent(fitted):
    model, _ = fitted
    x = pl.DataFrame({"sex": ["M"] * 3, "age": [20.0, 30.0, 50.0], "bodyweight_kg": [70.0] * 3})
    q = np.linspace(0.05, 0.95, 19)
    qh = model.quantile(x, q)
    assert np.all(np.diff(qh, axis=1) > 0)
    np.testing.assert_allclose(model.cdf(x, qh[:, 9]), 0.5, atol=1e-9)


def test_inputs_are_clipped_outside_training_range(fitted):
    model, _ = fitted
    x = pl.DataFrame({"sex": ["M", "M"], "age": [5.0, 14.0], "bodyweight_kg": [10.0, 30.0]})
    p = model.params(x)
    for k in ("mu", "sigma", "nu"):
        assert p[k][0] == pytest.approx(p[k][1])


def test_unknown_sex_raises(fitted):
    model, _ = fitted
    with pytest.raises(ValueError):
        model.params(pl.DataFrame({"sex": ["X"], "age": [30.0], "bodyweight_kg": [80.0]}))


def test_to_dict_has_all_coefficients(fitted):
    model, _ = fitted
    d = model.to_dict()
    assert set(d["coef"]) == {"M", "F"}
    assert np.array(d["coef"]["M"]["mu"]).shape == (model.ka, model.kw)
    assert model.n_parameters() == 2 * 3 * model.ka * model.kw


def test_bcpe_fits_and_tau_is_positive():
    df, _ = synthetic(3000, seed=2)
    m = SplineLMS(dataclasses.replace(SMALL, family="BCPE", lbfgs_rounds=3)).fit(df)
    x = pl.DataFrame({"sex": ["M", "F"], "age": [30.0, 30.0], "bodyweight_kg": [80.0, 60.0]})
    tau = m.params(x)["tau"]
    assert np.all(tau > 0.5) and np.all(tau < 20)
    assert np.isfinite(m.log_likelihood(df))


def test_config_file_loads():
    cfg = load_config(ML_ROOT / "configs/spline_lms.yaml", SplineLMSConfig)
    assert cfg.family in boxcox.FAMILIES
    assert cfg.penalties.mu.age > 0
