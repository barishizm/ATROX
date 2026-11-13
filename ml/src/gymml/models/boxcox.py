"""Box-Cox Cole-Green (BCCG) ve Box-Cox Power Exponential (BCPE) dağılımları (P050).

Rigby & Stasinopoulos (2004) / GAMLSS tanımları. Y > 0 için

    z = ((y/μ)^ν − 1) / (νσ)        (ν = 0 ise z = log(y/μ)/σ)

ve z, kesilmiş bir T dağılımına uyar: BCCG'de standart normal, BCPE'de ortalama 0, varyans 1 olan
güç-üstel (PE, şekil τ; τ = 2 normaldir). Kesilme noktası b = 1/(σ|ν|): ν > 0'da z > −b, ν < 0'da
z < b. Yoğunluk

    f_Y(y) = y^(ν−1) / (μ^ν σ) · f_T(z) / F_T(b).

İki uygulama vardır: eğitimde türev için `torch_logpdf`, değerlendirmede `logpdf/cdf/ppf` (numpy +
scipy.special temel fonksiyonları). Doğruluk `tests/test_spline_lms.py` içinde scipy.stats
(`truncnorm`, `gennorm`) ve sayısal integrasyonla doğrulanır.
"""

from __future__ import annotations

import math

import numpy as np
import torch
from scipy import special

FAMILIES = ("BCCG", "BCPE")
NU_EPS = 1e-6
_LOG2 = math.log(2.0)


# --------------------------------------------------------------------------------------------
# numpy (değerlendirme)
# --------------------------------------------------------------------------------------------


def _z(y, mu, sigma, nu):
    lr = np.log(y / mu)
    small = np.abs(nu) < NU_EPS
    nu_s = np.where(small, 1.0, nu)
    return np.where(small, lr / sigma, np.expm1(nu_s * lr) / (nu_s * sigma))


def _pe_scale(tau):
    """PE için gennorm ölçeği s = c·2^(1/τ); c² = 2^(−2/τ) Γ(1/τ)/Γ(3/τ)."""
    log_c = 0.5 * ((-2.0 / tau) * _LOG2 + special.gammaln(1 / tau) - special.gammaln(3 / tau))
    return np.exp(log_c + _LOG2 / tau)


def _t_logpdf(z, tau, family):
    if family == "BCCG":
        return -0.5 * z**2 - 0.5 * math.log(2 * math.pi)
    s = _pe_scale(tau)
    return np.log(tau) - _LOG2 - np.log(s) - special.gammaln(1 / tau) - np.abs(z / s) ** tau


def _t_cdf(z, tau, family):
    if family == "BCCG":
        return special.ndtr(z)
    s = _pe_scale(tau)
    p = special.gammainc(1 / tau, np.abs(z / s) ** tau)
    return 0.5 + 0.5 * np.sign(z) * p


def _t_ppf(u, tau, family):
    if family == "BCCG":
        return special.ndtri(u)
    s = _pe_scale(tau)
    a = 1 / tau
    g = special.gammaincinv(a, np.abs(2 * u - 1))
    return np.sign(u - 0.5) * s * g ** (1 / tau)


def _bound(sigma, nu):
    return 1.0 / (sigma * np.maximum(np.abs(nu), NU_EPS))


def _check(family: str) -> None:
    if family not in FAMILIES:
        raise ValueError(f"bilinmeyen aile {family!r}; {FAMILIES}")


def logpdf(y, mu, sigma, nu, tau=2.0, family: str = "BCPE"):
    _check(family)
    y, mu, sigma, nu, tau = np.broadcast_arrays(
        *(np.asarray(a, float) for a in (y, mu, sigma, nu, tau))
    )
    z = _z(y, mu, sigma, nu)
    b = _bound(sigma, nu)
    out = (
        (nu - 1) * np.log(y)
        - nu * np.log(mu)
        - np.log(sigma)
        + _t_logpdf(z, tau, family)
        - np.log(_t_cdf(b, tau, family))
    )
    # Desteğin dışı (kesilme): ν > 0'da z ≤ −b, ν < 0'da z ≥ b imkânsız.
    outside = ((nu > 0) & (z <= -b)) | ((nu < 0) & (z >= b))
    return np.where(outside, -np.inf, out)


def cdf(y, mu, sigma, nu, tau=2.0, family: str = "BCPE"):
    _check(family)
    y, mu, sigma, nu, tau = np.broadcast_arrays(
        *(np.asarray(a, float) for a in (y, mu, sigma, nu, tau))
    )
    pos = y > 0
    ys = np.where(pos, y, 1.0)
    z = _z(ys, mu, sigma, nu)
    b = _bound(sigma, nu)
    fb = _t_cdf(b, tau, family)
    fz = _t_cdf(z, tau, family)
    out = np.where(nu > 0, (fz - (1 - fb)) / fb, fz / fb)
    return np.where(pos, np.clip(out, 0.0, 1.0), 0.0)


def ppf(p, mu, sigma, nu, tau=2.0, family: str = "BCPE"):
    _check(family)
    p, mu, sigma, nu, tau = np.broadcast_arrays(
        *(np.asarray(a, float) for a in (p, mu, sigma, nu, tau))
    )
    b = _bound(sigma, nu)
    fb = _t_cdf(b, tau, family)
    u = np.where(nu > 0, (1 - fb) + p * fb, p * fb)
    u = np.clip(u, 1e-300, 1 - 1e-16)
    z = _t_ppf(u, tau, family)
    small = np.abs(nu) < NU_EPS
    nu_s = np.where(small, 1.0, nu)
    base = np.maximum(1 + sigma * nu_s * z, 1e-300)
    return np.where(small, mu * np.exp(sigma * z), mu * base ** (1 / nu_s))


# --------------------------------------------------------------------------------------------
# torch (eğitim, otomatik türev)
# --------------------------------------------------------------------------------------------


class _GammaInc(torch.autograd.Function):
    """Düzenlenmiş alt eksik gama P(a, x). torch `a`'ya göre türev vermez; burada merkezi fark
    (a için) ve analitik türev (x için) kullanılır."""

    @staticmethod
    def forward(ctx, a, x):
        ctx.save_for_backward(a, x)
        return torch.special.gammainc(a, x)

    @staticmethod
    def backward(ctx, g):
        a, x = ctx.saved_tensors
        h = 1e-5 * a
        da = (torch.special.gammainc(a + h, x) - torch.special.gammainc(a - h, x)) / (2 * h)
        logdx = (a - 1) * torch.log(x.clamp_min(1e-300)) - x - torch.lgamma(a)
        dx = torch.where(x > 0, torch.exp(logdx), torch.zeros_like(x))
        return g * da, g * dx


def _t_log_cdf_upper_torch(b, tau, family):
    """log F_T(b), b > 0."""
    if family == "BCCG":
        return torch.special.log_ndtr(b)
    log_s = _torch_log_pe_scale(tau)
    x = torch.exp(tau * (torch.log(b) - log_s))
    return torch.log(0.5 + 0.5 * _GammaInc.apply(1 / tau, x))


def _torch_log_pe_scale(tau):
    log_c = 0.5 * ((-2.0 / tau) * _LOG2 + torch.lgamma(1 / tau) - torch.lgamma(3 / tau))
    return log_c + _LOG2 / tau


def torch_logpdf(y, mu, sigma, nu, tau=None, family: str = "BCPE"):
    """Log-yoğunluk; `mu`, `sigma`, `tau` > 0 tensörleri (log bağlantıdan), `nu` serbest."""
    _check(family)
    lr = torch.log(y) - torch.log(mu)
    small = nu.abs() < NU_EPS
    nu_s = torch.where(small, torch.ones_like(nu), nu)
    z = torch.where(small, lr / sigma, torch.expm1(nu_s * lr) / (nu_s * sigma))
    b = 1.0 / (sigma * nu.abs().clamp_min(NU_EPS))
    jac = (nu - 1) * torch.log(y) - nu * torch.log(mu) - torch.log(sigma)
    if family == "BCCG":
        lt = -0.5 * z**2 - 0.5 * math.log(2 * math.pi)
    else:
        log_s = _torch_log_pe_scale(tau)
        lt = (
            torch.log(tau)
            - _LOG2
            - log_s
            - torch.lgamma(1 / tau)
            - torch.exp(tau * (torch.log(z.abs().clamp_min(1e-300)) - log_s))
        )
    return jac + lt - _t_log_cdf_upper_torch(b, tau, family)
