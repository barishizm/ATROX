"""Aday C (P052): sinirsel dağılımsal regresyon + Gauss kopula korelasyon başlığı.

docs/03-ML-MODEL.md §4.2 (C satırı) ve §4.4.

Yapı
----
- Girdi: cinsiyet (M = 1, F = 0), standartlaştırılmış yaş, standartlaştırılmış log-kilo —
  **önce kırpılır** (bkz. `InputClip`; Swift aynı kuralı aynen uygular).
- Gövde: 2–3 gizli katmanlı küçük MLP, pürüzsüz aktivasyon (SiLU/tanh). Üç kaldırış ortak
  gövdeyi paylaşır.
- Kaldırış başına başlık: 4 dağılım parametresi.
  * `bcpe`  — Box-Cox Power Exponential (Rigby & Stasinopoulos 2004), (μ, σ, ν, τ).
  * `shash` — log ölçekte sinh-arcsinh (Jones & Pewsey 2009), (μ_log, s, ε, δ).
- Korelasyon başlığı: SBD üçlüsünde normal skorların koşullu korelasyon matrisi R(x) —
  Cholesky parametreli (birim köşegen için satırları normalize edilmiş alt üçgen L, R = L Lᵀ),
  Gauss kopula olabilirliği. İki aşamalı (IFM): önce marjinaller, sonra marjinaller
  dondurulup kopula başlığı.
- Düzenlileştirme: AdamW ağırlık azaltma, iç (sporcu-gruplu) ayrık kümeyle erken durdurma,
  girdi-Jacobian cezası (Hutchinson tahmini, pürüzsüzlük) ve kiloda monotonluk cezası
  (aynı yükte z-skoru kiloyla artmasın).

Değerlendirme kümesi (val) eğitimde hiç kullanılmaz; erken durdurma train bölmesinin içinden
ayrılan %10'luk sporcu-gruplu parçayla yapılır.
"""

from __future__ import annotations

import copy
import hashlib
import math
from dataclasses import asdict, dataclass, field
from typing import Any

import numpy as np
import polars as pl
import torch
from scipy import special, stats
from torch import nn

from gymml.data.cohort import LIFTS
from gymml.eval.data import PROCESSED, DataSpec, ensure_splits, load_lift
from gymml.eval.metrics import ROUNDING_STEP_KG

# ----------------------------------------------------------------------------------------------
# Girdi kırpma ve standartlaştırma (Swift `StrengthKit` bu bölümü birebir kopyalar)
# ----------------------------------------------------------------------------------------------

AGE_CENTER, AGE_SCALE = 35.0, 15.0
LOGBW_CENTER, LOGBW_SCALE = math.log(80.0), 0.3
CLIP_QUANTILES = (0.0, 1.0)  # min–max: eğitim desteğinin tamamı


@dataclass(frozen=True)
class InputClip:
    """Kırpma kuralı: yaş ve kilo, eğitim verisinin desteğine (en küçük – en büyük gözlem)
    kırpılır; sınırlar 0.5'e dışa yuvarlanır. Yaş tüm veri üzerinden, kilo cinsiyete göre ayrı.
    Sınırlar `params.json`'a yazılır; Swift değerleri oradan okur ve `clamp(x, lo, hi)` uygular —
    model hiçbir zaman eğitim aralığının dışında değerlendirilmez.

    Not: %0.1–%99.9 dilimleri denendi; sınır noktasındaki eğim kırığı (ör. yaş 79, erkek kilo
    47) olağan kullanıcı aralığının içinde kaldığı için pürüzsüzlük testini bozdu
    (reports/candidate_c.md)."""

    age: tuple[float, float] = (14.0, 85.0)
    bw: dict[str, tuple[float, float]] = field(
        default_factory=lambda: {"M": (31.0, 247.0), "F": (30.0, 226.0)}
    )

    @staticmethod
    def from_frames(frames: list[pl.DataFrame]) -> InputClip:
        df = pl.concat([f.select("sex", "age", "bodyweight_kg") for f in frames])
        lo, hi = CLIP_QUANTILES

        def rng(s: pl.Series) -> tuple[float, float]:
            a, b = np.quantile(s.to_numpy(), [lo, hi])
            return (math.floor(a * 2) / 2, math.ceil(b * 2) / 2)

        bw = {
            s: rng(df.filter(pl.col("sex") == s)["bodyweight_kg"])
            for s in ("M", "F")
            if df.filter(pl.col("sex") == s).height
        }
        return InputClip(age=rng(df["age"]), bw=bw)

    def features(self, x: pl.DataFrame) -> np.ndarray:
        """(n, 3): [erkek mi, (yaş_k − 35)/15, (log kilo_k − log 80)/0.3], `_k` = kırpılmış."""
        sex = x["sex"].to_numpy()
        male = (sex == "M").astype(np.float64)
        age = np.clip(x["age"].to_numpy().astype(np.float64), *self.age)
        bw = x["bodyweight_kg"].to_numpy().astype(np.float64)
        bw_c = np.empty_like(bw)
        for s, (lo, hi) in self.bw.items():
            m = sex == s
            bw_c[m] = np.clip(bw[m], lo, hi)
        other = ~np.isin(sex, list(self.bw))
        if other.any():
            raise ValueError("cinsiyet M veya F olmalı (karışım üst katmanda yapılır, §4.5)")
        return np.stack(
            [male, (age - AGE_CENTER) / AGE_SCALE, (np.log(bw_c) - LOGBW_CENTER) / LOGBW_SCALE],
            axis=1,
        )

    def to_dict(self) -> dict:
        return {"age": list(self.age), "bodyweight_kg": {k: list(v) for k, v in self.bw.items()}}


# ----------------------------------------------------------------------------------------------
# BCPE (numpy/scipy) — gamlss.dist::BCPE ile aynı tanım
# ----------------------------------------------------------------------------------------------

_NU_EPS = 1e-9
COHORT_SBD = PROCESSED / "cohort_sbd.parquet"


def pe_c(tau):
    """Birim varyanslı güç-üstel dağılımın ölçek sabiti c(τ)."""
    tau = np.asarray(tau, float)
    return np.exp(
        0.5 * (-2.0 / tau * np.log(2.0) + special.gammaln(1 / tau) - special.gammaln(3 / tau))
    )


def pe_logpdf(z, tau):
    tau = np.asarray(tau, float)
    c = pe_c(tau)
    return (
        np.log(tau)
        - 0.5 * np.abs(z / c) ** tau
        - np.log(c)
        - (1 + 1 / tau) * np.log(2.0)
        - special.gammaln(1 / tau)
    )


def pe_cdf(z, tau):
    tau = np.asarray(tau, float)
    c = pe_c(tau)
    with np.errstate(over="ignore"):
        g = special.gammainc(1 / tau, 0.5 * np.abs(z / c) ** tau)
    return 0.5 + 0.5 * np.sign(z) * g


def pe_ppf(p, tau):
    tau = np.asarray(tau, float)
    c = pe_c(tau)
    g = special.gammaincinv(1 / tau, np.abs(2 * np.asarray(p, float) - 1))
    return np.sign(p - 0.5) * c * (2 * g) ** (1 / tau)


def _safe_nu(nu):
    nu = np.asarray(nu, float)
    return np.where(np.abs(nu) < _NU_EPS, np.where(nu < 0, -_NU_EPS, _NU_EPS), nu)


def bcpe_z(y, mu, sigma, nu):
    nu = _safe_nu(nu)
    return np.expm1(nu * np.log(y / mu)) / (nu * sigma)


def _bcpe_trunc(sigma, nu, tau):
    """(F2, F3): F3 = F_T(1/(σ|ν|)), F2 = F_T(−1/(σ|ν|)) ν > 0 ise, aksi hâlde 0."""
    nu = _safe_nu(nu)
    t = 1.0 / (sigma * np.abs(nu))
    f3 = pe_cdf(t, tau)
    f2 = np.where(nu > 0, pe_cdf(-t, tau), 0.0)
    return f2, f3


def bcpe_logpdf(y, mu, sigma, nu, tau):
    y = np.asarray(y, float)
    z = bcpe_z(y, mu, sigma, nu)
    _, f3 = _bcpe_trunc(sigma, nu, tau)
    return nu * np.log(y / mu) - np.log(y) - np.log(sigma) + pe_logpdf(z, tau) - np.log(f3)


def bcpe_cdf(y, mu, sigma, nu, tau):
    y = np.asarray(y, float)
    pos = y > 0
    ys = np.where(pos, y, 1.0)
    f2, f3 = _bcpe_trunc(sigma, nu, tau)
    out = (pe_cdf(bcpe_z(ys, mu, sigma, nu), tau) - f2) / f3
    return np.where(pos, np.clip(out, 0.0, 1.0), 0.0)


def bcpe_ppf(p, mu, sigma, nu, tau):
    f2, f3 = _bcpe_trunc(sigma, nu, tau)
    za = pe_ppf(np.asarray(p, float) * f3 + f2, tau)
    nu = _safe_nu(nu)
    base = np.maximum(1 + nu * sigma * za, 1e-300)
    return mu * np.exp(np.log(base) / nu)


# ----------------------------------------------------------------------------------------------
# Log-ölçekte sinh-arcsinh (numpy)
# ----------------------------------------------------------------------------------------------


def shash_z(y, mu, s, eps, delta):
    u = (np.log(y) - mu) / s
    return np.sinh(delta * np.arcsinh(u) - eps)


def shash_logpdf(y, mu, s, eps, delta):
    y = np.asarray(y, float)
    u = (np.log(y) - mu) / s
    a = delta * np.arcsinh(u) - eps
    return (
        np.log(delta)
        + np.log(np.cosh(a))
        - np.log(s)
        - 0.5 * np.log1p(u**2)
        + stats.norm.logpdf(np.sinh(a))
        - np.log(y)
    )


def shash_cdf(y, mu, s, eps, delta):
    y = np.asarray(y, float)
    pos = y > 0
    return np.where(pos, stats.norm.cdf(shash_z(np.where(pos, y, 1.0), mu, s, eps, delta)), 0.0)


def shash_ppf(p, mu, s, eps, delta):
    z = stats.norm.ppf(p)
    return np.exp(mu + s * np.sinh((np.arcsinh(z) + eps) / delta))


HEADS = {
    "bcpe": (("mu", "sigma", "nu", "tau"), bcpe_cdf, bcpe_ppf, bcpe_logpdf),
    "shash": (("mu_log", "s", "eps", "delta"), shash_cdf, shash_ppf, shash_logpdf),
}


# ----------------------------------------------------------------------------------------------
# Torch karşılıkları (eğitim)
# ----------------------------------------------------------------------------------------------

_LOG2 = math.log(2.0)


def _t_pe_logc(tau):
    return 0.5 * (-2.0 / tau * _LOG2 + torch.lgamma(1 / tau) - torch.lgamma(3 / tau))


def _t_pe_logpdf(z, tau):
    logc = _t_pe_logc(tau)
    return (
        torch.log(tau)
        - 0.5 * torch.abs(z * torch.exp(-logc)) ** tau
        - logc
        - (1 + 1 / tau) * _LOG2
        - torch.lgamma(1 / tau)
    )


def _t_pe_cdf_pos(t, tau):
    """F_T(t), t > 0. gammainc'in a-gradyanı yok: a = 1/τ bu terimde sabit tutulur (kesme terimi
    σ|ν| küçükken ~1'dir; ihmal edilebilir yanlılık)."""
    logc = _t_pe_logc(tau)
    arg = 0.5 * (t * torch.exp(-logc)) ** tau
    return 0.5 + 0.5 * torch.special.gammainc((1 / tau).detach(), arg)


def _t_safe_nu(nu):
    small = torch.abs(nu) < _NU_EPS
    return torch.where(small, torch.where(nu < 0, -_NU_EPS, _NU_EPS) + 0 * nu, nu)


def t_bcpe_z(y, mu, sigma, nu, tau=None):
    nu = _t_safe_nu(nu)
    return torch.expm1(nu * torch.log(y / mu)) / (nu * sigma)


def t_bcpe_logpdf(y, mu, sigma, nu, tau):
    z = t_bcpe_z(y, mu, sigma, nu)
    nus = _t_safe_nu(nu)
    f3 = _t_pe_cdf_pos(1.0 / (sigma * torch.abs(nus)), tau)
    return (
        nu * torch.log(y / mu)
        - torch.log(y)
        - torch.log(sigma)
        + _t_pe_logpdf(z, tau)
        - torch.log(f3.clamp_min(1e-12))
    )


def t_shash_z(y, mu, s, eps, delta):
    return torch.sinh(delta * torch.asinh((torch.log(y) - mu) / s) - eps)


def t_shash_logpdf(y, mu, s, eps, delta):
    u = (torch.log(y) - mu) / s
    a = delta * torch.asinh(u) - eps
    z = torch.sinh(a)
    return (
        torch.log(delta)
        + torch.log(torch.cosh(a))
        - torch.log(s)
        - 0.5 * torch.log1p(u**2)
        - 0.5 * z**2
        - 0.5 * math.log(2 * math.pi)
        - torch.log(y)
    )


T_HEADS = {"bcpe": (t_bcpe_z, t_bcpe_logpdf), "shash": (t_shash_z, t_shash_logpdf)}


# ----------------------------------------------------------------------------------------------
# Korelasyon: Cholesky parametrizasyonu ve Gauss kopula
# ----------------------------------------------------------------------------------------------


def t_cholesky_corr(raw: torch.Tensor) -> torch.Tensor:
    """raw (n, 3) → L (n, 3, 3): birim köşegenli alt üçgen, satırları birim normlu; R = L Lᵀ."""
    n = raw.shape[0]
    one, zero = torch.ones(n, dtype=raw.dtype), torch.zeros(n, dtype=raw.dtype)
    rows = [
        torch.stack([one, zero, zero], 1),
        torch.stack([raw[:, 0], one, zero], 1),
        torch.stack([raw[:, 1], raw[:, 2], one], 1),
    ]
    L = torch.stack(rows, 1)
    return L / torch.linalg.norm(L, dim=2, keepdim=True)


def t_copula_nll(L: torch.Tensor, z: torch.Tensor) -> torch.Tensor:
    """−log c(z; R) satır başına: ½ log|R| + ½ zᵀ(R⁻¹ − I)z."""
    w = torch.linalg.solve_triangular(L, z.unsqueeze(-1), upper=False).squeeze(-1)
    logdet = 2 * torch.log(torch.diagonal(L, dim1=1, dim2=2)).sum(1)
    return 0.5 * logdet + 0.5 * ((w**2).sum(1) - (z**2).sum(1))


def corr_from_raw(raw: np.ndarray) -> np.ndarray:
    with torch.no_grad():
        L = t_cholesky_corr(torch.as_tensor(raw, dtype=torch.float64))
        return (L @ L.transpose(1, 2)).numpy()


# ----------------------------------------------------------------------------------------------
# Ağ
# ----------------------------------------------------------------------------------------------

ACTIVATIONS = {"silu": nn.SiLU, "tanh": nn.Tanh, "gelu": nn.GELU}


class _Net(nn.Module):
    def __init__(self, lifts, hidden, activation, head, init_scale: dict[str, float]):
        super().__init__()
        act = ACTIVATIONS[activation]
        layers, d = [], 3
        for h in hidden:
            layers += [nn.Linear(d, h), act()]
            d = h
        self.trunk = nn.Sequential(*layers)
        self.head_kind = head
        self.heads = nn.ModuleDict({lift: nn.Linear(d, 4) for lift in lifts})
        self.offset = {lift: math.log(init_scale[lift]) for lift in lifts}
        for h in self.heads.values():
            nn.init.zeros_(h.weight)
            nn.init.zeros_(h.bias)
            nn.init.normal_(h.weight, std=0.01)
        self.corr = nn.Linear(d, 3)
        nn.init.zeros_(self.corr.weight)
        with torch.no_grad():  # başlangıç: tüm çiftlerde ~0.7
            self.corr.bias.copy_(torch.tensor([1.0, 0.8, 0.8]))

    def dist_params(self, feats: torch.Tensor, lift: str) -> tuple[torch.Tensor, ...]:
        r = self.heads[lift](self.trunk(feats))
        off = self.offset[lift]
        if self.head_kind == "bcpe":
            mu = torch.exp(r[:, 0] + off)
            sigma = nn.functional.softplus(r[:, 1] - 1.4) + 1e-3  # başlangıç ≈ 0.22
            nu = 3.0 * torch.tanh((r[:, 2] + 0.5) / 3.0)  # başlangıç 0.5, (−3, 3)
            tau = 1.0 + 9.0 * torch.sigmoid(r[:, 3] - 2.08)  # başlangıç ≈ 2, (1, 10)
            return mu, sigma, nu, tau
        mu = r[:, 0] + off
        s = nn.functional.softplus(r[:, 1] - 1.4) + 1e-3
        eps = r[:, 2]
        delta = nn.functional.softplus(r[:, 3] + 0.54) + 0.1  # başlangıç ≈ 1
        return mu, s, eps, delta

    def corr_raw(self, feats: torch.Tensor) -> torch.Tensor:
        return self.corr(self.trunk(feats).detach())


# ----------------------------------------------------------------------------------------------
# Eğitim yapılandırması ve ortak model
# ----------------------------------------------------------------------------------------------


@dataclass
class NeuralConfig:
    head: str = "bcpe"  # "bcpe" | "shash"
    hidden: tuple[int, ...] = (64, 64)
    activation: str = "silu"
    lr: float = 3e-3
    weight_decay: float = 1e-4
    batch_size: int = 8192
    max_epochs: int = 30
    patience: int = 3
    lambda_jac: float = 1e-3  # girdi-Jacobian (pürüzsüzlük) cezası
    lambda_mono: float = 1.0  # aynı yükte kiloyla artan z-skoru cezası
    penalty_rows: int = 1024  # cezaların hesaplandığı alt örneklem
    holdout_frac: float = 0.10  # train içinden sporcu-gruplu erken durdurma kümesi
    corr_epochs: int = 15
    max_rows_per_lift: int | None = None  # hızlı deneme için alt örnekleme
    seed: int = 0
    spec: DataSpec = field(default_factory=DataSpec)


def _holdout_mask(ids: np.ndarray, frac: float, seed: int) -> np.ndarray:
    """Sporcu kimliğinin tohumlu özetiyle deterministik grup ayrımı."""

    def h(a: str) -> float:
        return int(hashlib.sha1(f"{seed}:{a}".encode()).hexdigest()[:8], 16) / 0xFFFFFFFF

    uniq = np.unique(ids)
    held = {a for a in uniq if h(a) < frac}
    return np.fromiter((a in held for a in ids), bool, len(ids))


def _weighted_median(y: np.ndarray, w: np.ndarray) -> float:
    o = np.argsort(y)
    cw = np.cumsum(w[o])
    return float(y[o][np.searchsorted(cw, cw[-1] / 2)])


class NeuralDistributional:
    """Üç kaldırışın ortak gövdeli dağılım modeli + kopula başlığı."""

    def __init__(self, cfg: NeuralConfig | None = None):
        self.cfg = cfg or NeuralConfig()
        if self.cfg.head not in HEADS:
            raise ValueError(f"bilinmeyen başlık: {self.cfg.head}")
        self.net: _Net | None = None
        self.clip = InputClip()
        self.lifts: tuple[str, ...] = ()
        self.history: list[dict] = []
        self.corr_history: list[dict] = []
        self.corr_fitted = False

    # ---- yardımcılar ---------------------------------------------------------------------
    @property
    def fitted(self) -> bool:
        return self.net is not None

    def n_params(self) -> int:
        assert self.net is not None
        return sum(p.numel() for p in self.net.parameters())

    def _feats(self, x: pl.DataFrame) -> torch.Tensor:
        return torch.as_tensor(self.clip.features(x), dtype=torch.float32)

    def params(self, x: pl.DataFrame, lift: str) -> dict[str, np.ndarray]:
        assert self.net is not None
        names = HEADS[self.cfg.head][0]
        with torch.no_grad():
            ps = self.net.dist_params(self._feats(x), lift)
        return {k: v.double().numpy() for k, v in zip(names, ps, strict=True)}

    def quantile(self, x: pl.DataFrame, lift: str, q: np.ndarray) -> np.ndarray:
        p = self.params(x, lift)
        ppf = HEADS[self.cfg.head][2]
        args = [v[:, None] for v in p.values()]
        return ppf(np.asarray(q, float)[None, :], *args)

    def cdf(self, x: pl.DataFrame, lift: str, y: np.ndarray) -> np.ndarray:
        p = self.params(x, lift)
        return HEADS[self.cfg.head][1](np.asarray(y, float), *p.values())

    def normal_scores(self, x: pl.DataFrame, lift: str, y: np.ndarray) -> np.ndarray:
        u = np.clip(self.cdf(x, lift, y), 1e-6, 1 - 1e-6)
        return stats.norm.ppf(u)

    def correlation(self, x: pl.DataFrame) -> np.ndarray:
        """(n, 3, 3) koşullu korelasyon matrisi; sıra `LIFTS` (squat, bench, deadlift)."""
        assert self.net is not None
        with torch.no_grad():
            raw = self.net.corr_raw(self._feats(x)).double().numpy()
        return corr_from_raw(raw)

    # ---- aşama 1: marjinaller ------------------------------------------------------------
    def fit(self, frames: dict[str, pl.DataFrame], sbd: pl.DataFrame | None = None):
        cfg = self.cfg
        torch.manual_seed(cfg.seed)
        rng = np.random.default_rng(cfg.seed)
        self.lifts = tuple(frames)
        if cfg.max_rows_per_lift:
            frames = {
                k: (
                    f.sample(cfg.max_rows_per_lift, seed=cfg.seed)
                    if f.height > cfg.max_rows_per_lift
                    else f
                )
                for k, f in frames.items()
            }
        self.clip = InputClip.from_frames(list(frames.values()))
        scale = {
            k: _weighted_median(f["value_kg"].to_numpy(), f["weight"].to_numpy())
            for k, f in frames.items()
        }
        self.net = _Net(self.lifts, cfg.hidden, cfg.activation, cfg.head, scale)

        X, Y, W, L, H = [], [], [], [], []
        for i, f in enumerate(frames.values()):
            X.append(self.clip.features(f))
            Y.append(f["value_kg"].to_numpy())
            W.append(f["weight"].to_numpy())
            L.append(np.full(f.height, i))
            H.append(_holdout_mask(f["athlete_id"].to_numpy(), cfg.holdout_frac, cfg.seed))
        X, Y, W, L, H = map(np.concatenate, (X, Y, W, L, H))
        tr, ho = ~H, H
        Xt = torch.as_tensor(X, dtype=torch.float32)
        Wt = torch.as_tensor(W, dtype=torch.float32)
        Lt = torch.as_tensor(L)

        opt = torch.optim.AdamW(self.net.parameters(), lr=cfg.lr, weight_decay=cfg.weight_decay)
        idx_tr = np.flatnonzero(tr)
        steps = max(1, math.ceil(len(idx_tr) / cfg.batch_size))
        sched = torch.optim.lr_scheduler.CosineAnnealingLR(opt, cfg.max_epochs * steps)
        best, best_state, bad = math.inf, None, 0
        # Erken durdurma kümesi sabit titreşimle (tekrarlanabilir ölçüm).
        y_ho = torch.as_tensor(
            Y[ho] + rng.uniform(-ROUNDING_STEP_KG / 2, ROUNDING_STEP_KG / 2, ho.sum()),
            dtype=torch.float32,
        )
        for epoch in range(cfg.max_epochs):
            self.net.train()
            yj = torch.as_tensor(
                Y + rng.uniform(-ROUNDING_STEP_KG / 2, ROUNDING_STEP_KG / 2, len(Y)),
                dtype=torch.float32,
            )
            perm = rng.permutation(idx_tr)
            tot = 0.0
            for b in range(steps):
                ib = torch.as_tensor(perm[b * cfg.batch_size : (b + 1) * cfg.batch_size])
                loss = self._batch_loss(Xt[ib], yj[ib], Wt[ib], Lt[ib], penalties=True)
                opt.zero_grad()
                loss.backward()
                nn.utils.clip_grad_norm_(self.net.parameters(), 5.0)
                opt.step()
                sched.step()
                tot += float(loss.detach())
            self.net.eval()
            with torch.no_grad():
                iho = torch.as_tensor(np.flatnonzero(ho))
                val = float(self._batch_loss(Xt[iho], y_ho, Wt[iho], Lt[iho], penalties=False))
            self.history.append({"epoch": epoch, "train_loss": tot / steps, "holdout_nll": val})
            if val < best - 1e-4:
                best, best_state, bad = val, copy.deepcopy(self.net.state_dict()), 0
            else:
                bad += 1
                if bad >= cfg.patience:
                    break
        if best_state is not None:
            self.net.load_state_dict(best_state)
        if sbd is not None:
            self.fit_correlation(sbd)
        return self

    def _batch_loss(self, x, y, w, lift_idx, penalties: bool) -> torch.Tensor:
        assert self.net is not None
        z_fn, logpdf = T_HEADS[self.cfg.head]
        nll = torch.zeros((), dtype=torch.float32)
        pen = torch.zeros((), dtype=torch.float32)
        for i, lift in enumerate(self.lifts):
            m = lift_idx == i
            if not bool(m.any()):
                continue
            ps = self.net.dist_params(x[m], lift)
            nll = nll + -(w[m] * logpdf(y[m], *ps)).sum()
            if penalties and (self.cfg.lambda_jac > 0 or self.cfg.lambda_mono > 0):
                k = min(int(m.sum()), self.cfg.penalty_rows)
                xs = x[m][:k].clone().requires_grad_(True)
                ps2 = self.net.dist_params(xs, lift)
                if self.cfg.lambda_mono > 0:
                    z = z_fn(y[m][:k], *ps2)
                    (gz,) = torch.autograd.grad(z.sum(), xs, create_graph=True)
                    pen = pen + self.cfg.lambda_mono * torch.relu(gz[:, 2]).pow(2).mean()
                if self.cfg.lambda_jac > 0:
                    loc = ps2[0] if self.cfg.head == "shash" else torch.log(ps2[0])
                    raw = torch.stack([loc, torch.log(ps2[1]), ps2[2], ps2[3]], 1)
                    r = torch.randn_like(raw)
                    (gj,) = torch.autograd.grad((raw * r).sum(), xs, create_graph=True)
                    pen = pen + self.cfg.lambda_jac * gj.pow(2).sum(1).mean()
        return nll / w.sum() + pen

    # ---- aşama 2: kopula ----------------------------------------------------------------
    def sbd_scores(self, sbd: pl.DataFrame, seed: int = 0) -> np.ndarray:
        """SBD satırları için (n, 3) normal skorlar (titreştirilmiş yük, marjinal CDF → Φ⁻¹)."""
        rng = np.random.default_rng(seed)
        cols = {"squat": "squat_kg", "bench": "bench_kg", "deadlift": "deadlift_kg"}
        out = []
        for lift in LIFTS:
            y = sbd[cols[lift]].to_numpy()
            y = y + rng.uniform(-ROUNDING_STEP_KG / 2, ROUNDING_STEP_KG / 2, len(y))
            out.append(self.normal_scores(sbd, lift, y))
        return np.stack(out, 1)

    def fit_correlation(self, sbd: pl.DataFrame) -> NeuralDistributional:
        assert self.net is not None and set(LIFTS) <= set(self.lifts)
        cfg = self.cfg
        z = torch.as_tensor(self.sbd_scores(sbd, cfg.seed), dtype=torch.float32)
        Xt = self._feats(sbd)
        W = torch.as_tensor(sbd["weight"].to_numpy().copy(), dtype=torch.float32)
        ho = torch.as_tensor(
            _holdout_mask(sbd["athlete_id"].to_numpy(), cfg.holdout_frac, cfg.seed)
        )
        for p in self.net.parameters():
            p.requires_grad_(False)
        for p in self.net.corr.parameters():
            p.requires_grad_(True)
        opt = torch.optim.AdamW(self.net.corr.parameters(), lr=1e-2, weight_decay=cfg.weight_decay)
        g = torch.Generator().manual_seed(cfg.seed)
        idx_tr = torch.nonzero(~ho).squeeze(1)
        idx_ho = torch.nonzero(ho).squeeze(1)

        def loss(ix):
            L = t_cholesky_corr(self.net.corr_raw(Xt[ix]))
            return (W[ix] * t_copula_nll(L, z[ix])).sum() / W[ix].sum()

        best, best_state, bad = math.inf, None, 0
        for epoch in range(cfg.corr_epochs):
            perm = idx_tr[torch.randperm(len(idx_tr), generator=g)]
            for b in range(0, len(perm), cfg.batch_size):
                opt.zero_grad()
                lo = loss(perm[b : b + cfg.batch_size])
                lo.backward()
                opt.step()
            with torch.no_grad():
                v = float(loss(idx_ho))
            self.corr_history.append({"epoch": epoch, "holdout_copula_nll": v})
            if v < best - 1e-5:
                best, best_state, bad = v, copy.deepcopy(self.net.corr.state_dict()), 0
            else:
                bad += 1
                if bad >= cfg.patience:
                    break
        if best_state is not None:
            self.net.corr.load_state_dict(best_state)
        for p in self.net.parameters():
            p.requires_grad_(True)
        self.corr_fitted = True
        return self

    def copula_nll(self, sbd: pl.DataFrame) -> float:
        """Ağırlıklı ortalama −log c (0 = bağımsızlık; negatif = korelasyon bilgi taşıyor)."""
        z = torch.as_tensor(self.sbd_scores(sbd), dtype=torch.float64)
        with torch.no_grad():
            raw = self.net.corr_raw(self._feats(sbd)).double()
            v = t_copula_nll(t_cholesky_corr(raw), z).numpy()
        w = sbd["weight"].to_numpy()
        return float((w * v).sum() / w.sum())

    def describe(self) -> dict[str, Any]:
        d = asdict(self.cfg)
        d["spec"] = asdict(self.cfg.spec)
        return {"config": d, "clip": self.clip.to_dict(), "n_params": self.n_params()}


# ----------------------------------------------------------------------------------------------
# Kaldırış başına `DistributionModel` bağdaştırıcısı
# ----------------------------------------------------------------------------------------------


class NeuralLift:
    """`gymml.eval.interface.DistributionModel` — tek kaldırış görünümü.

    `fit(df)`: ortak model henüz eğitilmediyse, `df`'nin kaldırışı + (varsa `train_other_lifts`)
    diğer kaldırışların AYNI bölmedeki (train) verisiyle ortak gövdeyi eğitir. Böylece
    `evaluate_factory` kaldırış başına çağırsa da gövde bir kez eğitilir (ilk kaldırışın
    `fit_seconds` değeri tüm eğitimi içerir).
    """

    def __init__(
        self,
        joint: NeuralDistributional | None = None,
        train_other_lifts: bool = True,
        sbd: pl.DataFrame | None = None,
    ):
        self.joint = joint or NeuralDistributional()
        self.train_other_lifts = train_other_lifts
        self.sbd = sbd
        self.lift: str | None = None
        self.name = f"neural_{self.joint.cfg.head}"

    def fit(self, df: pl.DataFrame) -> NeuralLift:
        lifts = df["lift"].unique().to_list() if "lift" in df.columns else []
        if len(lifts) != 1:
            raise ValueError("df tek bir kaldırış içermeli (`lift` sütunu)")
        self.lift = lifts[0]
        if not self.joint.fitted:
            frames = {self.lift: df}
            if self.train_other_lifts:
                splits = set(df["split"].unique().to_list()) if "split" in df.columns else {"train"}
                if splits != {"train"}:
                    raise ValueError("ortak gövde yalnızca train bölmesiyle eğitilir")
                frames = {
                    lift: (
                        df if lift == self.lift else load_lift(lift, "train", self.joint.cfg.spec)
                    )
                    for lift in LIFTS
                }
            self.joint.fit(frames, self.sbd)
        elif self.lift not in self.joint.lifts:
            raise ValueError(f"ortak model {self.lift} için eğitilmedi")
        return self

    def quantile(self, x: pl.DataFrame, q: np.ndarray) -> np.ndarray:
        return self.joint.quantile(x, self.lift, q)

    def cdf(self, x: pl.DataFrame, y: np.ndarray) -> np.ndarray:
        return self.joint.cdf(x, self.lift, y)

    def params(self, x: pl.DataFrame) -> dict[str, Any]:
        return self.joint.params(x, self.lift)


def load_sbd(split: str, spec: DataSpec | None = None) -> pl.DataFrame:
    """SBD üçlüsü tam kayıtlar (cohort_sbd), aynı referans tanımı ve sporcu bölmesiyle."""
    spec = spec or DataSpec()
    df = pl.read_parquet(COHORT_SBD)
    if spec.tested_only:
        df = df.filter(pl.col("tested"))
    if not spec.include_wraps:
        df = df.filter(~pl.col("wraps"))
    if spec.unweighted:
        df = df.with_columns(weight=pl.lit(1.0))
    return df.join(ensure_splits(), on="athlete_id").filter(pl.col("split") == split)


def shared_factory(joint: NeuralDistributional, sbd: pl.DataFrame | None = None):
    """`evaluate_factory` için: her çağrı aynı ortak modele bakan yeni bir `NeuralLift`."""
    return lambda: NeuralLift(joint, sbd=sbd)
