"""Akıl sağlığı testleri (docs/03-ML-MODEL.md §4.3 madde 3); her biri `SanityResult` döndürür."""

from __future__ import annotations

from dataclasses import dataclass, field

import numpy as np
import polars as pl

from gymml.data.cohort import CohortConfig
from gymml.eval.interface import DistributionModel

TYPICAL_BW = {"M": 90.0, "F": 65.0}


@dataclass(frozen=True)
class SanityConfig:
    ages: tuple[float, ...] = (20.0, 30.0, 45.0, 60.0)
    bodyweights: tuple[float, ...] = (55.0, 75.0, 95.0, 120.0)
    load_step_kg: float = 2.5
    # Aynı yük için kilo arttıkça CDF artmamalı; sayısal/basamak gürültüsü toleransı.
    bw_tolerance: float = 0.005
    # §4.3: "medyan 20'lerin ortasında tepe yapıp sonra azalmalı". P048 EDA'da ham veride tepe
    # 27–34 (bench 32–41); aralık kullanıcı onayına kadar geniş tutuldu (reports/baselines.md).
    peak_age_range: tuple[float, float] = (20.0, 40.0)
    max_year_jump: float = 0.04  # ardışık iki yaş arasında medyanın en çok göreli değişimi
    # Sıçrama sınırı yalnızca yetişkinlere (2026-11-13 kullanıcı onayı): gençlerde yıllık artış
    # verinin kendisinde %4–10; gençlerdeki ani kırılmaları pürüzsüzlük (ikinci fark) testi yakalar.
    jump_min_age: float = 20.0
    max_rel_second_diff: float = 0.01  # 1 kg / 1 yıl adımında |Δ²medyan| / medyan sınırı
    extrapolation_ages: tuple[float, ...] = (10.0, 14.0, 85.0, 95.0)
    extrapolation_bws: tuple[float, ...] = (25.0, 30.0, 250.0, 300.0)
    max_lift_kg: dict[str, float] = field(default_factory=lambda: CohortConfig().max_lift_kg)


@dataclass(frozen=True)
class SanityResult:
    name: str
    passed: bool
    detail: str


def _x(sex: str, age, bw) -> pl.DataFrame:
    age, bw = np.broadcast_arrays(np.asarray(age, float), np.asarray(bw, float))
    return pl.DataFrame({"sex": [sex] * age.size, "age": age.ravel(), "bodyweight_kg": bw.ravel()})


def monotone_in_load(m: DistributionModel, cfg: SanityConfig) -> SanityResult:
    worst = np.inf
    for sex in ("M", "F"):
        for age in cfg.ages:
            for bw in cfg.bodyweights:
                x1 = _x(sex, [age], [bw])
                lo, hi = m.quantile(x1, np.array([0.05, 0.95]))[0]
                ys = np.arange(lo, hi + cfg.load_step_kg, cfg.load_step_kg)
                c = m.cdf(_x(sex, np.full(len(ys), age), np.full(len(ys), bw)), ys)
                worst = min(worst, float(np.min(np.diff(c))))
    return SanityResult(
        "skor yükte kesin artan (Q05–Q95 arası, 2.5 kg adım)",
        worst > 0,
        f"en küçük CDF artışı {worst:.2e}",
    )


def bodyweight_non_increasing(m: DistributionModel, cfg: SanityConfig) -> SanityResult:
    worst = -np.inf
    bws = np.arange(45.0, 160.0, 1.0)
    for sex in ("M", "F"):
        for age in cfg.ages:
            for q in (0.25, 0.5, 0.75):
                y = m.quantile(_x(sex, [age], [TYPICAL_BW[sex]]), np.array([q]))[0, 0]
                c = m.cdf(_x(sex, np.full(len(bws), age), bws), np.full(len(bws), y))
                worst = max(worst, float(np.max(np.diff(c))))
    return SanityResult(
        "aynı yükte skor kiloyla artmıyor",
        worst <= cfg.bw_tolerance,
        f"kilo +1 kg'da en büyük CDF artışı {worst:.4f} (tolerans {cfg.bw_tolerance})",
    )


def age_shape(m: DistributionModel, cfg: SanityConfig) -> SanityResult:
    ages = np.arange(16.0, 81.0, 1.0)
    peaks, jumps, unimodal = [], [], True
    for sex in ("M", "F"):
        med = m.quantile(_x(sex, ages, np.full(len(ages), TYPICAL_BW[sex])), np.array([0.5]))[:, 0]
        peaks.append(float(ages[np.argmax(med)]))
        adult = ages[:-1] >= cfg.jump_min_age
        jumps.append(float(np.max((np.abs(np.diff(med)) / med[:-1])[adult])))
        # Tek tepelilik: tepeden önce azalmayan, sonra artmayan (yarım adım tolerans).
        k = int(np.argmax(med))
        tol = 0.005 * med.max()
        unimodal &= bool(np.all(np.diff(med[: k + 1]) >= -tol) and np.all(np.diff(med[k:]) <= tol))
    lo, hi = cfg.peak_age_range
    ok = all(lo <= p <= hi for p in peaks) and max(jumps) <= cfg.max_year_jump and unimodal
    return SanityResult(
        f"yaş eğrisi tek tepeli, tepe {lo:g}–{hi:g}, {cfg.jump_min_age:g}+ yaşta sıçrama yok",
        ok,
        f"tepe yaşı M/F {peaks}, {cfg.jump_min_age:g}+ yaşta en büyük yıllık değişim "
        f"{max(jumps):.3f}, tek tepeli={unimodal}",
    )


def smoothness(m: DistributionModel, cfg: SanityConfig) -> SanityResult:
    worst = 0.0
    for sex in ("M", "F"):
        bws = np.arange(45.0, 150.0, 1.0)
        for age in cfg.ages:
            med = m.quantile(_x(sex, np.full(len(bws), age), bws), np.array([0.5]))[:, 0]
            worst = max(worst, float(np.max(np.abs(np.diff(med, 2)) / med[1:-1])))
        ages = np.arange(16.0, 81.0, 1.0)
        for bw in cfg.bodyweights:
            med = m.quantile(_x(sex, ages, np.full(len(ages), bw)), np.array([0.5]))[:, 0]
            worst = max(worst, float(np.max(np.abs(np.diff(med, 2)) / med[1:-1])))
    return SanityResult(
        "pürüzsüzlük (ikinci fark sınırı)",
        worst <= cfg.max_rel_second_diff,
        f"en büyük |Δ²medyan|/medyan {worst:.4f} (sınır {cfg.max_rel_second_diff})",
    )


def extrapolation(m: DistributionModel, cfg: SanityConfig, lift: str) -> SanityResult:
    ages, bws = np.meshgrid(cfg.extrapolation_ages, cfg.extrapolation_bws)
    problems = []
    for sex in ("M", "F"):
        q = m.quantile(_x(sex, ages, bws), np.array([0.05, 0.5, 0.95]))
        if not np.all(np.isfinite(q)):
            problems.append(f"{sex}: sonsuz/NaN")
            continue
        if np.any(q[:, 0] <= 0):
            problems.append(f"{sex}: Q05 ≤ 0")
        if np.any(np.diff(q, axis=1) < 0):
            problems.append(f"{sex}: çeyrek kesişmesi")
        if np.any(q[:, 2] > 1.2 * cfg.max_lift_kg[lift]):
            problems.append(f"{sex}: Q95 > 1.2 × fiziksel sınır")
    return SanityResult(
        "eğitim aralığı dışında makul davranış",
        not problems,
        "; ".join(problems) or "sonlu, pozitif, sıralı, fiziksel sınır içinde",
    )


def run_all(
    m: DistributionModel, lift: str, cfg: SanityConfig = SanityConfig()
) -> list[SanityResult]:
    return [
        monotone_in_load(m, cfg),
        bodyweight_non_increasing(m, cfg),
        age_shape(m, cfg),
        smoothness(m, cfg),
        extrapolation(m, cfg, lift),
    ]
