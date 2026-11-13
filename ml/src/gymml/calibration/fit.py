"""Yer-ölçek kalibrasyonu (δ, κ) kestirimi (P055, docs/03-ML-MODEL.md §5).

Model (log-kg ölçeğinde, g ∈ {gym, general}):

    m_g(x) = m_c(x) − δ_g(cinsiyet, kaldırış, yaş bandı)
    s_g(x) = κ_g · s_c(x)
    δ_g(cinsiyet, kaldırış, bant) = D_g(cinsiyet) + L(cinsiyet, kaldırış) + A_g(cinsiyet, bant)

L bench için 0'dır ve iki nüfus arasında ortaktır (kaldırışlar arası fark aynı varsayılır; genel
nüfusta deadlift çapası olmadığı için gerekli). A referans bantta (20-39) 0'dır. κ nüfus başına tek
değerdir (cinsiyet/kaldırış başına ayrı κ'yı taşıyacak kadar çapa yok: genel nüfus kadın κ'sı ayrı
kestirildiğinde bootstrap aralığı negatife iniyordu; salonda E/K κ'sı 1.80/1.98 ile zaten yakındı).

Bir çapa (p, v) için tahmin: log v = m_c − δ + κ · s_c · Φ⁻¹(p) → parametrelerde doğrusal. Kestirim
ağırlıklı en küçük karelerdir; zayıf önseller (A ~ N(0, 0.5²), κ ~ N(1, 1²), D, L ~ N(0, 2²))
yalnızca çapası olmayan parametreleri tanımlı tutar. Çapa ağırlığı = reliability / sqrt(kaynaktaki
satır sayısı) — çok satırlı tek bir kaynak sonucu domine etmesin diye.
"""

from __future__ import annotations

from collections import defaultdict
from collections.abc import Callable
from dataclasses import dataclass, field

import numpy as np
from scipy.stats import norm

from gymml.calibration.anchors import POPULATIONS, Anchor, relative_key
from gymml.calibration.reference import (
    AGE_BANDS,
    LIFTS,
    REF_BAND,
    SEXES,
    CompetitorReference,
)

SIGMA0 = 0.05  # bir çapanın nominal log hatası (ağırlık 1 için)
PRIOR_SD = {"D": 2.0, "L": 2.0, "A": 0.5, "K": 1.0}
PRIOR_MEAN = {"D": 0.0, "L": 0.0, "A": 0.0, "K": 1.0}
# Yaşa göreli çapalarda kaldırışlar ortak göreli VA ile karşılaştırılır.
REL_BODYWEIGHT = {"M": 80.0, "F": 65.0}

# BMI düzeltmesi (§7) için bir kullanıcının "etkin" vücut ağırlığını veren fonksiyon.
BodyweightFn = Callable[[str, float], float]


def _identity_bw(sex: str, bw: float) -> float:
    return bw


def param_names() -> list[str]:
    names = [f"D|{p}|{s}" for p in POPULATIONS for s in SEXES]
    names += [f"L|{s}|{lift}" for s in SEXES for lift in LIFTS if lift != "bench"]
    names += [f"A|{p}|{s}|{b}" for p in POPULATIONS for s in SEXES for b in AGE_BANDS
              if b != REF_BAND]
    names += [f"K|{p}" for p in POPULATIONS]
    return names


@dataclass
class Calibration:
    theta: dict[str, float]
    reference_name: str
    weights_mode: str = "reliability/sqrt(n_source)"
    meta: dict = field(default_factory=dict)

    def delta(self, pop: str, sex: str, lift: str, band: str) -> float:
        if pop == "competitor":
            return 0.0
        d = self.theta[f"D|{pop}|{sex}"]
        if lift != "bench":
            d += self.theta[f"L|{sex}|{lift}"]
        if band != REF_BAND:
            d += self.theta[f"A|{pop}|{sex}|{band}"]
        return d

    def kappa(self, pop: str, sex: str) -> float:
        return 1.0 if pop == "competitor" else self.theta[f"K|{pop}"]

    def z_score(self, ref: CompetitorReference, pop: str, sex: str, lift: str, band: str,
                bodyweight_kg: float, value_kg: float) -> float:
        m_c, s_c = ref.location_scale(sex, lift, band, bodyweight_kg)
        return (np.log(value_kg) - m_c + self.delta(pop, sex, lift, band)) / (
            self.kappa(pop, sex) * s_c)

    def percentile(self, ref: CompetitorReference, pop: str, sex: str, lift: str, band: str,
                   bodyweight_kg: float, value_kg: float) -> float:
        """0–100 yüzdelik (skor, kırpılmadan)."""
        return 100.0 * float(norm.cdf(self.z_score(ref, pop, sex, lift, band, bodyweight_kg,
                                                   value_kg)))

    def quantile_kg(self, ref: CompetitorReference, pop: str, sex: str, lift: str, band: str,
                    bodyweight_kg: float, percentile: float) -> float:
        m_c, s_c = ref.location_scale(sex, lift, band, bodyweight_kg)
        z = norm.ppf(percentile / 100.0)
        return float(np.exp(m_c - self.delta(pop, sex, lift, band)
                            + self.kappa(pop, sex) * s_c * z))


@dataclass
class Equation:
    anchor: Anchor
    row: np.ndarray
    y: float
    weight: float


def _mean_delta_m(ref: CompetitorReference, sex: str, lift: str, band: str
                  ) -> tuple[float, float, float]:
    """(Δm_c, s_c(bant), s_c(ref)) — grip için üç kaldırışın ortalaması."""
    bw = REL_BODYWEIGHT[sex]
    lifts = LIFTS if lift == "grip" else (lift,)
    dm, sb, sr = [], [], []
    for lf in lifts:
        mb, s_b = ref.location_scale(sex, lf, band, bw)
        mr, s_r = ref.location_scale(sex, lf, REF_BAND, bw)
        dm.append(mb - mr)
        sb.append(s_b)
        sr.append(s_r)
    return float(np.mean(dm)), float(np.mean(sb)), float(np.mean(sr))


def build_equations(anchors: list[Anchor], ref: CompetitorReference,
                    weights_mode: str = "reliability/sqrt(n_source)",
                    bodyweight_fn: BodyweightFn = _identity_bw) -> list[Equation]:
    names = param_names()
    idx = {n: i for i, n in enumerate(names)}
    per_source: dict[str, int] = defaultdict(int)
    for a in anchors:
        per_source[a.source] += 1

    def weight(a: Anchor) -> float:
        if weights_mode == "equal":
            return 1.0
        if weights_mode == "reliability":
            return float(a.reliability)
        return a.reliability / np.sqrt(per_source[a.source])

    def delta_row(a: Anchor, include_level: bool) -> np.ndarray:
        r = np.zeros(len(names))
        if include_level:
            r[idx[f"D|{a.population}|{a.sex}"]] = -1.0
            if a.lift != "bench":
                r[idx[f"L|{a.sex}|{a.lift}"]] = -1.0
        if a.age_band != REF_BAND:
            r[idx[f"A|{a.population}|{a.sex}|{a.age_band}"]] = -1.0
        return r

    eqs: list[Equation] = []
    # Göreli grupların referans seviyesi (aynı grubun 20-39 satırlarının log ortalaması).
    ref_level: dict[tuple, float] = {}
    groups: dict[tuple, list[Anchor]] = defaultdict(list)
    for a in anchors:
        if a.relative:
            groups[relative_key(a)].append(a)
    for key, rows in groups.items():
        ref_level[key] = float(np.mean([np.log(r.value_kg) for r in rows
                                        if r.age_band == REF_BAND]))

    for a in anchors:
        z = norm.ppf(a.percentile / 100.0)
        if not a.relative:
            if a.lift == "grip":
                raise ValueError("grip mutlak çapa olamaz")
            bw = bodyweight_fn(a.sex, a.bodyweight_kg)
            m_c, s_c = ref.location_scale(a.sex, a.lift, a.age_band, bw)
            r = delta_row(a, include_level=True)
            r[idx[f"K|{a.population}"]] = s_c * z
            eqs.append(Equation(a, r, float(np.log(a.value_kg) - m_c), weight(a)))
        elif a.age_band != REF_BAND:
            dm, s_b, s_r = _mean_delta_m(ref, a.sex, a.lift, a.age_band)
            r = delta_row(a, include_level=False)
            r[idx[f"K|{a.population}"]] = (s_b - s_r) * z
            y = np.log(a.value_kg) - ref_level[relative_key(a)] - dm
            eqs.append(Equation(a, r, float(y), weight(a)))
    return eqs


def solve(eqs: list[Equation]) -> np.ndarray:
    names = param_names()
    k = len(names)
    rows = [e.row * np.sqrt(e.weight) / SIGMA0 for e in eqs]
    ys = [e.y * np.sqrt(e.weight) / SIGMA0 for e in eqs]
    for i, n in enumerate(names):
        kind = n.split("|")[0]
        r = np.zeros(k)
        r[i] = 1.0 / PRIOR_SD[kind]
        rows.append(r)
        ys.append(PRIOR_MEAN[kind] / PRIOR_SD[kind])
    theta, *_ = np.linalg.lstsq(np.vstack(rows), np.array(ys), rcond=None)
    return theta


def fit(anchors: list[Anchor], ref: CompetitorReference,
        weights_mode: str = "reliability/sqrt(n_source)",
        bodyweight_fn: BodyweightFn = _identity_bw) -> Calibration:
    eqs = build_equations(anchors, ref, weights_mode, bodyweight_fn)
    theta = solve(eqs)
    cal = Calibration(dict(zip(param_names(), map(float, theta), strict=True)), ref.name,
                      weights_mode)
    cal.meta["weighted_rss"] = weighted_rss(cal, eqs)
    cal.meta["n_equations"] = len(eqs)
    return cal


def residuals(cal: Calibration, eqs: list[Equation]) -> np.ndarray:
    theta = np.array([cal.theta[n] for n in param_names()])
    return np.array([e.y - e.row @ theta for e in eqs])


def weighted_rss(cal: Calibration, eqs: list[Equation]) -> float:
    r = residuals(cal, eqs)
    w = np.array([e.weight for e in eqs])
    return float(np.sum(w * r**2) / np.sum(w))


def bootstrap(anchors: list[Anchor], ref: CompetitorReference, n_boot: int = 500,
              seed: int = 55, weights_mode: str = "reliability/sqrt(n_source)",
              bodyweight_fn: BodyweightFn = _identity_bw) -> list[Calibration]:
    """Kaynak içinde tabakalı satır yeniden örneklemesi."""
    rng = np.random.default_rng(seed)
    by_src: dict[str, list[Anchor]] = defaultdict(list)
    for a in anchors:
        by_src[a.source].append(a)
    out = []
    for _ in range(n_boot):
        sample: list[Anchor] = []
        for rows in by_src.values():
            pick = rng.integers(0, len(rows), len(rows))
            sample += [rows[i] for i in pick]
            # Göreli grupların referans satırı kaybolmasın.
            sample += [r for r in rows if r.relative and r.age_band == REF_BAND]
        out.append(fit(sample, ref, weights_mode, bodyweight_fn))
    return out


@dataclass
class HeldOut:
    anchor: Anchor
    predicted_percentile: float | None  # mutlak çapalar
    percentile_error: float | None
    log_error: float


def leave_one_source_out(anchors: list[Anchor], ref: CompetitorReference,
                         weights_mode: str = "reliability/sqrt(n_source)",
                         bodyweight_fn: BodyweightFn = _identity_bw
                         ) -> dict[str, tuple[Calibration, list[HeldOut]]]:
    out: dict[str, tuple[Calibration, list[HeldOut]]] = {}
    for src in sorted({a.source for a in anchors}):
        train = [a for a in anchors if a.source != src]
        test = [a for a in anchors if a.source == src]
        cal = fit(train, ref, weights_mode, bodyweight_fn)
        eqs = build_equations(test, ref, weights_mode, bodyweight_fn)
        res = residuals(cal, eqs)
        held: list[HeldOut] = []
        for e, r in zip(eqs, res, strict=True):
            a = e.anchor
            if a.relative:
                held.append(HeldOut(a, None, None, float(r)))
            else:
                bw = bodyweight_fn(a.sex, a.bodyweight_kg)
                p = cal.percentile(ref, a.population, a.sex, a.lift, a.age_band, bw, a.value_kg)
                held.append(HeldOut(a, p, p - a.percentile, float(r)))
        out[src] = (cal, held)
    return out
