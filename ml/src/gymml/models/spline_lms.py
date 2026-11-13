"""Aday A — Spline-LMS (docs/03-ML-MODEL.md §4.2, P050).

GAMLSS tarzı referans eğrisi modeli: kaldırış ve cinsiyet başına

    Y | yaş, kilo ~ BCCG(μ, σ, ν)  veya  BCPE(μ, σ, ν, τ)
    log μ, log σ, ν, log τ = B(yaş, log kilo) · β_k

B, yaş ve log-kilo üzerindeki kübik B-spline tabanlarının tensör çarpımıdır (dört parametre aynı
tabanı paylaşır, düzgünlük parametreye özgü cezayla ayarlanır). Ceza, katsayı ızgarasında her eksen
boyunca ikinci farkların karesidir (Eilers & Marx P-spline). Amaç, ağırlıklı ortalama negatif
log-olabilirlik + ceza; Adam ile ısınma, ardından L-BFGS. Erken durdurma, eğitim kümesinin içinden
sporcu bazında ayrılan bir iç doğrulama payının olabilirliğine göre yapılır (dış doğrulama kümesi
yalnızca değerlendirme içindir).

Eğitim aralığı dışındaki girdiler (yaş, kilo) aralık sınırlarına kırpılır; Swift tarafı da aynı
kuralı uygulamalıdır.
"""

from __future__ import annotations

import dataclasses
import math
from dataclasses import dataclass, field
from typing import Any

import numpy as np
import polars as pl
import torch
from scipy.interpolate import BSpline

from gymml.models import boxcox

PARAMS = ("mu", "sigma", "nu", "tau")


@dataclass(frozen=True)
class Penalty:
    """İkinci fark cezası katsayıları (yaş ekseni, log-kilo ekseni)."""

    age: float = 1e-3
    bw: float = 1e-3


@dataclass(frozen=True)
class Penalties:
    mu: Penalty = field(default_factory=lambda: Penalty(1e-3, 1e-3))
    sigma: Penalty = field(default_factory=lambda: Penalty(1e-2, 1e-2))
    nu: Penalty = field(default_factory=lambda: Penalty(1e-1, 1e-1))
    tau: Penalty = field(default_factory=lambda: Penalty(1e-1, 1e-1))


@dataclass(frozen=True)
class SplineLMSConfig:
    family: str = "BCPE"
    degree: int = 3
    age_segments: int = 10
    bw_segments: int = 8
    age_min: float = 14.0
    age_max: float = 85.0
    bw_min: float = 30.0
    bw_max: float = 250.0
    penalties: Penalties = field(default_factory=Penalties)
    adam_steps: int = 300
    adam_lr: float = 0.05
    lbfgs_rounds: int = 30
    lbfgs_iter: int = 20
    patience: int = 3
    min_improvement: float = 1e-6
    holdout_frac: float = 0.1
    seed: int = 20260101


def _knots(lo: float, hi: float, segments: int, degree: int) -> np.ndarray:
    h = (hi - lo) / segments
    return lo + h * np.arange(-degree, segments + degree + 1)


def _design(x: np.ndarray, t: np.ndarray, degree: int) -> np.ndarray:
    lo, hi = t[degree], t[-degree - 1]
    x = np.clip(x, lo, hi)
    return BSpline.design_matrix(x, t, degree).toarray()


def _second_diff(n: int) -> np.ndarray:
    return np.diff(np.eye(n), 2, axis=0)


@dataclass
class _SexFit:
    coef: dict[str, np.ndarray]  # her biri (ka, kw)
    history: list[dict[str, float]]


class SplineLMS:
    """`gymml.eval.interface.DistributionModel` uyumlu Spline-LMS adayı."""

    def __init__(self, cfg: SplineLMSConfig | None = None):
        self.cfg = cfg or SplineLMSConfig()
        boxcox._check(self.cfg.family)
        self.name = f"spline_lms_{self.cfg.family.lower()}"
        c = self.cfg
        self.t_age = _knots(c.age_min, c.age_max, c.age_segments, c.degree)
        self.t_bw = _knots(math.log(c.bw_min), math.log(c.bw_max), c.bw_segments, c.degree)
        self.ka = c.age_segments + c.degree
        self.kw = c.bw_segments + c.degree
        self.fits: dict[str, _SexFit] = {}

    @property
    def param_names(self) -> tuple[str, ...]:
        return PARAMS if self.cfg.family == "BCPE" else PARAMS[:3]

    def n_parameters(self) -> int:
        return len(self.fits) * len(self.param_names) * self.ka * self.kw

    # ---------------------------------------------------------------- taban
    def basis(self, age: np.ndarray, bw: np.ndarray) -> np.ndarray:
        """(n, ka·kw) tensör çarpımı tabanı; girdiler eğitim aralığına kırpılır."""
        ba = _design(np.asarray(age, float), self.t_age, self.cfg.degree)
        bb = _design(np.log(np.asarray(bw, float)), self.t_bw, self.cfg.degree)
        return (ba[:, :, None] * bb[:, None, :]).reshape(len(ba), -1)

    # ---------------------------------------------------------------- eğitim
    def fit(self, df: pl.DataFrame) -> SplineLMS:
        for sex in ("M", "F"):
            d = df.filter(pl.col("sex") == sex)
            if d.height:
                self.fits[sex] = self._fit_sex(d)
        return self

    def _holdout_mask(self, d: pl.DataFrame) -> np.ndarray:
        rng = np.random.default_rng(self.cfg.seed)
        if "athlete_id" in d.columns:
            ids = d["athlete_id"].to_numpy()
            uniq = np.unique(ids)
            held = set(uniq[rng.random(len(uniq)) < self.cfg.holdout_frac].tolist())
            return np.fromiter((i in held for i in ids), bool, len(ids))
        return rng.random(d.height) < self.cfg.holdout_frac

    def _links(self, eta: torch.Tensor) -> dict[str, torch.Tensor]:
        out = {
            "mu": torch.exp(eta[:, 0]),
            "sigma": torch.exp(eta[:, 1].clamp(-6.0, 2.0)),
            "nu": eta[:, 2].clamp(-5.0, 5.0),
        }
        out["tau"] = (
            torch.exp(eta[:, 3].clamp(math.log(0.5), math.log(20.0)))
            if self.cfg.family == "BCPE"
            else torch.full_like(eta[:, 0], 2.0)
        )
        return out

    def _nll(self, theta, B, y, w):
        p = self._links(B @ theta)
        ll = boxcox.torch_logpdf(y, p["mu"], p["sigma"], p["nu"], p["tau"], self.cfg.family)
        return -(w * ll).sum() / w.sum()

    def _penalty(self, theta):
        da = torch.as_tensor(_second_diff(self.ka))
        dw = torch.as_tensor(_second_diff(self.kw))
        total = theta.new_zeros(())
        for j, name in enumerate(self.param_names):
            pen: Penalty = getattr(self.cfg.penalties, name)
            beta = theta[:, j].reshape(self.ka, self.kw)
            total = total + pen.age * ((da @ beta) ** 2).sum() + pen.bw * ((beta @ dw.T) ** 2).sum()
        return total

    def _fit_sex(self, d: pl.DataFrame) -> _SexFit:
        torch.manual_seed(self.cfg.seed)
        hold = self._holdout_mask(d)
        y_all = d["value_kg"].to_numpy().astype(float)
        w_all = d["weight"].to_numpy().astype(float)
        B_all = self.basis(d["age"].to_numpy(), d["bodyweight_kg"].to_numpy())

        def tens(a, m):
            return torch.as_tensor(np.ascontiguousarray(a[m]), dtype=torch.float64)

        tr, ho = ~hold, hold
        Bt, yt, wt = tens(B_all, tr), tens(y_all, tr), tens(w_all, tr)
        Bh, yh, wh = tens(B_all, ho), tens(y_all, ho), tens(w_all, ho)
        del B_all

        # B-spline tabanı birimi böldüğü için sabit katsayı = sabit fonksiyon.
        ly = np.log(y_all)
        init = [
            float(np.average(ly, weights=w_all)),
            math.log(float(np.std(ly))),
            0.5,
            math.log(2.0),
        ]
        P = len(self.param_names)
        theta = torch.tensor(
            np.tile(init[:P], (self.ka * self.kw, 1)), dtype=torch.float64, requires_grad=True
        )

        def objective():
            return self._nll(theta, Bt, yt, wt) + self._penalty(theta)

        def holdout_nll() -> float:
            with torch.no_grad():
                return float(self._nll(theta, Bh, yh, wh))

        history: list[dict[str, float]] = []
        best = (math.inf, theta.detach().clone())

        def record(stage: str, step: int) -> bool:
            nonlocal best
            h = holdout_nll()
            history.append({"stage": stage, "step": step, "holdout_nll": h})
            improved = h < best[0] - self.cfg.min_improvement
            if h < best[0]:
                best = (h, theta.detach().clone())
            return improved

        adam = torch.optim.Adam([theta], lr=self.cfg.adam_lr)
        for step in range(1, self.cfg.adam_steps + 1):
            adam.zero_grad()
            loss = objective()
            loss.backward()
            adam.step()
            if step % 50 == 0 or step == self.cfg.adam_steps:
                record("adam", step)

        lbfgs = torch.optim.LBFGS(
            [theta],
            lr=1.0,
            max_iter=self.cfg.lbfgs_iter,
            history_size=20,
            line_search_fn="strong_wolfe",
        )

        def closure():
            lbfgs.zero_grad()
            loss = objective()
            loss.backward()
            return loss

        stale = 0
        for rnd in range(1, self.cfg.lbfgs_rounds + 1):
            lbfgs.step(closure)
            if not torch.isfinite(theta).all():
                break
            stale = 0 if record("lbfgs", rnd) else stale + 1
            if stale >= self.cfg.patience:
                break

        coef_mat = best[1].numpy()
        coef = {
            name: coef_mat[:, j].reshape(self.ka, self.kw)
            for j, name in enumerate(self.param_names)
        }
        return _SexFit(coef=coef, history=history)

    # ---------------------------------------------------------------- tahmin
    def params(self, x: pl.DataFrame) -> dict[str, Any]:
        n = x.height
        out = {k: np.empty(n) for k in PARAMS}
        sex = x["sex"].to_numpy()
        for s, f in self.fits.items():
            m = sex == s
            if not m.any():
                continue
            B = self.basis(x["age"].to_numpy()[m], x["bodyweight_kg"].to_numpy()[m])
            eta = {k: B @ v.ravel() for k, v in f.coef.items()}
            out["mu"][m] = np.exp(eta["mu"])
            out["sigma"][m] = np.exp(np.clip(eta["sigma"], -6.0, 2.0))
            out["nu"][m] = np.clip(eta["nu"], -5.0, 5.0)
            out["tau"][m] = (
                np.exp(np.clip(eta["tau"], math.log(0.5), math.log(20.0))) if "tau" in eta else 2.0
            )
        unknown = ~np.isin(sex, list(self.fits))
        if unknown.any():
            raise ValueError(f"modelde olmayan cinsiyet: {sorted(set(sex[unknown]))}")
        return out

    def quantile(self, x: pl.DataFrame, q: np.ndarray) -> np.ndarray:
        p = self.params(x)
        q = np.asarray(q, float)[None, :]
        return boxcox.ppf(q, *(p[k][:, None] for k in PARAMS), family=self.cfg.family)

    def cdf(self, x: pl.DataFrame, y: np.ndarray) -> np.ndarray:
        p = self.params(x)
        return boxcox.cdf(np.asarray(y, float), *(p[k] for k in PARAMS), family=self.cfg.family)

    def log_likelihood(self, df: pl.DataFrame) -> float:
        """Ağırlıklı ortalama log-olabilirlik (aileleri karşılaştırmak için)."""
        p = self.params(df)
        ll = boxcox.logpdf(
            df["value_kg"].to_numpy(), *(p[k] for k in PARAMS), family=self.cfg.family
        )
        return float(np.average(ll, weights=df["weight"].to_numpy()))

    def to_dict(self) -> dict[str, Any]:
        """Dışa aktarım için düğümler ve katsayılar (P060'ta Core ML/params.json'a çevrilecek)."""
        return {
            "family": self.cfg.family,
            "degree": self.cfg.degree,
            "knots_age": self.t_age.tolist(),
            "knots_log_bw": self.t_bw.tolist(),
            "clip": {
                "age": [self.cfg.age_min, self.cfg.age_max],
                "bodyweight_kg": [self.cfg.bw_min, self.cfg.bw_max],
            },
            "coef": {s: {k: v.tolist() for k, v in f.coef.items()} for s, f in self.fits.items()},
            "config": dataclasses.asdict(self.cfg),
        }
