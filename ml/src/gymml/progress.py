"""Gelişim analitiği (docs/03-ML-MODEL.md §9) — Python referans uygulaması (P058).

Swift `StrengthKit` bu modülü 1:1 taşır; bu yüzden:
- saf ve deterministik (rastgelelik, saat, global durum yok; yalnızca `math`),
- tüm ayarlanabilir sayılar `ml/params_draft/progress.json` içinde (kodda sihirli sayı yok),
- girdi: oturum başına `(gün, e1RM_kg)`; gün, herhangi bir sabit başlangıçtan bu yana geçen gün
  sayısıdır.

Bütün eğimler ln(e1RM) üzerinde hesaplanır: aylık yüzde değişim doğrudan `exp(eğim * gün/ay) - 1`
olur ve log ölçeği tek bir aykırı değerin etkisini de sınırlar.
"""

from __future__ import annotations

import json
import math
from collections.abc import Sequence
from dataclasses import dataclass
from enum import StrEnum
from pathlib import Path
from typing import Any

DAYS_PER_WEEK = 7  # tanım gereği
DEFAULT_PARAMS_PATH = Path(__file__).resolve().parents[2] / "params_draft" / "progress.json"

Session = tuple[float, float]  # (gün, e1RM kg)


# --------------------------------------------------------------------------- parametreler


@dataclass(frozen=True)
class TrendParams:
    window_weeks_max: float
    min_sessions: int
    min_span_weeks: float
    ci_level: float
    ci_z: float


@dataclass(frozen=True)
class ExpectedCurveParams:
    novice_monthly_gain: float
    floor_monthly_gain: float
    level_decay: float
    experience_half_life_years: float


@dataclass(frozen=True)
class ScoreParams:
    ratio_anchors: tuple[float, ...]
    score_anchors: tuple[float, ...]


@dataclass(frozen=True)
class PlateauParams:
    window_weeks: float
    reference_weeks: float
    reference_min_sessions: int
    median_variance_factor: float
    min_sessions_per_week: float
    k: float
    h: float
    clip_z: float
    sigma_floor: float
    mad_to_sigma: float


@dataclass(frozen=True)
class ForecastParams:
    horizons_weeks: tuple[float, ...]
    max_horizon_weeks: float
    damping_days: float
    max_ratio_to_expected: float
    max_monthly_loss: float


@dataclass(frozen=True)
class ProgressParams:
    days_per_month: float
    trend: TrendParams
    expected_curve: ExpectedCurveParams
    score: ScoreParams
    plateau: PlateauParams
    forecast: ForecastParams


def _section(raw: dict[str, Any], name: str, cls: type) -> Any:
    block = {k: v for k, v in raw[name].items() if not k.startswith("_") and k != "provenance"}
    fields = set(cls.__dataclass_fields__)
    if set(block) != fields:
        raise ValueError(
            f"progress params [{name}]: beklenen {sorted(fields)}, gelen {sorted(block)}"
        )
    return cls(**{k: tuple(v) if isinstance(v, list) else v for k, v in block.items()})


def params_from_dict(raw: dict[str, Any]) -> ProgressParams:
    p = ProgressParams(
        days_per_month=float(raw["units"]["days_per_month"]),
        trend=_section(raw, "trend", TrendParams),
        expected_curve=_section(raw, "expected_curve", ExpectedCurveParams),
        score=_section(raw, "score", ScoreParams),
        plateau=_section(raw, "plateau", PlateauParams),
        forecast=_section(raw, "forecast", ForecastParams),
    )
    ra, sa = p.score.ratio_anchors, p.score.score_anchors
    if len(ra) != len(sa) or len(ra) < 2 or list(ra) != sorted(set(ra)):
        raise ValueError("score anchors: eşit uzunlukta ve kesin artan oran dizisi gerekli")
    if list(sa) != sorted(sa):
        raise ValueError("score anchors: skor dizisi azalmayan olmalı")
    return p


def load_params(path: Path = DEFAULT_PARAMS_PATH) -> ProgressParams:
    return params_from_dict(json.loads(Path(path).read_text()))


# --------------------------------------------------------------------------- yardımcılar


def _median(xs: Sequence[float]) -> float:
    s = sorted(xs)
    n = len(s)
    if n == 0:
        raise ValueError("boş dizinin medyanı yok")
    mid = n // 2
    return s[mid] if n % 2 else 0.5 * (s[mid - 1] + s[mid])


def _clean(sessions: Sequence[Session]) -> list[Session]:
    """Geçersiz (e1RM <= 0 veya sonlu olmayan) satırları atar, güne göre sıralar."""
    out = [
        (float(t), float(w))
        for t, w in sessions
        if math.isfinite(t) and math.isfinite(w) and w > 0
    ]
    out.sort(key=lambda s: s[0])
    return out


@dataclass(frozen=True)
class TheilSen:
    slope: float  # ln(kg) / gün
    intercept: float  # t = 0'daki ln(kg)
    slope_low: float
    slope_high: float
    n: int


def theil_sen(ts: Sequence[float], ys: Sequence[float], z: float) -> TheilSen:
    """Theil–Sen eğimi + Sen (1968) sıra tabanlı güven aralığı (bağ düzeltmesi yok).

    Aynı güne düşen çiftler (dx = 0) atlanır. En az iki farklı gün gerekir.
    """
    n = len(ts)
    slopes = sorted(
        (ys[j] - ys[i]) / (ts[j] - ts[i])
        for i in range(n)
        for j in range(i + 1, n)
        if ts[j] != ts[i]
    )
    m = len(slopes)
    if m == 0:
        raise ValueError("Theil–Sen için en az iki farklı gün gerekli")
    slope = _median(slopes)
    intercept = _median([y - slope * t for t, y in zip(ts, ys, strict=True)])
    c = z * math.sqrt(n * (n - 1) * (2 * n + 5) / 18.0)
    lo_rank = max(0, min(m - 1, math.floor((m - c) / 2.0)))
    hi_rank = max(0, min(m - 1, math.ceil((m + c) / 2.0) - 1))
    return TheilSen(slope, intercept, slopes[lo_rank], slopes[hi_rank], n)


def _monthly_pct(log_slope_per_day: float, days_per_month: float) -> float:
    return math.exp(log_slope_per_day * days_per_month) - 1.0


# --------------------------------------------------------------------------- eğilim


class Status(StrEnum):
    OK = "ok"
    INSUFFICIENT_DATA = "insufficient_data"


@dataclass(frozen=True)
class Trend:
    status: Status
    n_sessions: int
    span_days: float
    fit: TheilSen | None = None
    monthly_pct: float | None = None  # ör. 0.02 = ayda %2
    monthly_pct_low: float | None = None
    monthly_pct_high: float | None = None
    sigma: float | None = None  # artıkların sağlam std. sapması (ln birimi)
    t_last: float | None = None


def _robust_sigma(
    ts: Sequence[float], ys: Sequence[float], fit: TheilSen, p: PlateauParams
) -> float:
    resid = [y - (fit.intercept + fit.slope * t) for t, y in zip(ts, ys, strict=True)]
    med = _median(resid)
    mad = _median([abs(r - med) for r in resid])
    return max(p.mad_to_sigma * mad, p.sigma_floor)


def trend(sessions: Sequence[Session], params: ProgressParams) -> Trend:
    """Son `window_weeks_max` haftalık e1RM eğilimi.

    En az veri koşulu sağlanmazsa INSUFFICIENT_DATA döner.
    """
    tp = params.trend
    data = _clean(sessions)
    if not data:
        return Trend(Status.INSUFFICIENT_DATA, 0, 0.0)
    t_last = data[-1][0]
    window = [s for s in data if s[0] >= t_last - tp.window_weeks_max * DAYS_PER_WEEK]
    span = window[-1][0] - window[0][0]
    if len(window) < tp.min_sessions or span < tp.min_span_weeks * DAYS_PER_WEEK:
        return Trend(Status.INSUFFICIENT_DATA, len(window), span)
    ts = [t for t, _ in window]
    ys = [math.log(w) for _, w in window]
    fit = theil_sen(ts, ys, tp.ci_z)
    dpm = params.days_per_month
    return Trend(
        status=Status.OK,
        n_sessions=len(window),
        span_days=span,
        fit=fit,
        monthly_pct=_monthly_pct(fit.slope, dpm),
        monthly_pct_low=_monthly_pct(fit.slope_low, dpm),
        monthly_pct_high=_monthly_pct(fit.slope_high, dpm),
        sigma=_robust_sigma(ts, ys, fit, params.plateau),
        t_last=t_last,
    )


# --------------------------------------------------------------------------- beklenen gelişim


def expected_monthly_gain(
    percentile: float, params: ProgressParams, training_years: float | None = None
) -> float:
    """Seviyeye (0–100 yüzdelik) ve deneyime göre beklenen aylık e1RM artışı (oran, ör. 0.01 = %1).

    VARSAYIM: eğrinin biçimi (azalan getiri) literatürle uyumlu, sayılar değil — bkz. progress.json.
    """
    c = params.expected_curve
    p = min(max(percentile, 0.0), 100.0) / 100.0
    level_term = math.exp(-c.level_decay * p)
    exp_term = 1.0
    if training_years is not None:
        exp_term = 1.0 / (1.0 + max(training_years, 0.0) / c.experience_half_life_years)
    span = c.novice_monthly_gain - c.floor_monthly_gain
    return c.floor_monthly_gain + span * level_term * exp_term


# --------------------------------------------------------------------------- gelişim skoru


def _interp(x: float, xs: Sequence[float], ys: Sequence[float]) -> float:
    if x <= xs[0]:
        return ys[0]
    if x >= xs[-1]:
        return ys[-1]
    for i in range(1, len(xs)):
        if x <= xs[i]:
            f = (x - xs[i - 1]) / (xs[i] - xs[i - 1])
            return ys[i - 1] + f * (ys[i] - ys[i - 1])
    return ys[-1]  # pragma: no cover - döngü her zaman döner


def score_from_ratio(ratio: float, params: ProgressParams) -> float:
    s = params.score
    return _interp(ratio, s.ratio_anchors, s.score_anchors)


@dataclass(frozen=True)
class ProgressScore:
    status: Status
    score: float | None = None
    score_low: float | None = None
    score_high: float | None = None
    ratio: float | None = None
    observed_monthly_pct: float | None = None
    expected_monthly_pct: float | None = None


def progress_score(
    tr: Trend, percentile: float, params: ProgressParams, training_years: float | None = None
) -> ProgressScore:
    """Gözlenen / beklenen aylık log-artış oranını 0–100'e eşler.

    Eğimin güven aralığı aynı eşlemeyle skor aralığına taşınır.
    """
    if tr.status is not Status.OK or tr.fit is None:
        return ProgressScore(Status.INSUFFICIENT_DATA)
    g = expected_monthly_gain(percentile, params, training_years)
    exp_log = math.log1p(g)
    dpm = params.days_per_month

    def ratio(slope: float) -> float:
        return slope * dpm / exp_log

    r = ratio(tr.fit.slope)
    return ProgressScore(
        status=Status.OK,
        score=score_from_ratio(r, params),
        score_low=score_from_ratio(ratio(tr.fit.slope_low), params),
        score_high=score_from_ratio(ratio(tr.fit.slope_high), params),
        ratio=r,
        observed_monthly_pct=tr.monthly_pct,
        expected_monthly_pct=g,
    )


# --------------------------------------------------------------------------- plato


class PlateauStatus(StrEnum):
    PLATEAU = "plateau"
    PROGRESSING = "progressing"
    INSUFFICIENT_DATA = "insufficient_data"


@dataclass(frozen=True)
class Plateau:
    status: PlateauStatus
    n_window: int
    n_reference: int
    cusum_max: float | None = None
    sigma: float | None = None


def detect_plateau(sessions: Sequence[Session], params: ProgressParams) -> Plateau:
    """Kendinden başlayan tek yönlü üst CUSUM: son `window_weeks` haftada anlamlı artış var mı?

    Her pencere oturumu, kendinden önceki yakın dönem oturumlarının (pencereden önceki
    `reference_weeks` hafta + pencerenin önceki oturumları) medyanıyla karşılaştırılır. Referans her
    adımda güncellendiği için referansın kendi hatası bütün adımlara aynı yönde yansıyıp birikmez.
    Adımlar `clip_z`'de kırpılır; tek bir aykırı yüksek değer eşiği tek başına aşamaz. Yeterli
    sıklık (pencerede ve referansta en az oturum) yoksa karar verilmez.
    """
    pp = params.plateau
    data = _clean(sessions)
    if not data:
        return Plateau(PlateauStatus.INSUFFICIENT_DATA, 0, 0)
    t_last = data[-1][0]
    w_start = t_last - pp.window_weeks * DAYS_PER_WEEK
    r_start = w_start - pp.reference_weeks * DAYS_PER_WEEK
    window = [s for s in data if s[0] > w_start]
    reference = [s for s in data if r_start < s[0] <= w_start]
    if (
        len(window) < pp.min_sessions_per_week * pp.window_weeks
        or len(reference) < pp.reference_min_sessions
    ):
        return Plateau(PlateauStatus.INSUFFICIENT_DATA, len(window), len(reference))
    # Gürültü: referans + pencere oturumlarının Theil–Sen artıklarından (yalnızca yakın dönem).
    recent = reference + window
    ts = [t for t, _ in recent]
    ys = [math.log(w) for _, w in recent]
    sigma = _robust_sigma(ts, ys, theil_sen(ts, ys, params.trend.ci_z), pp)
    prev = [math.log(w) for _, w in reference]
    s = 0.0
    s_max = 0.0
    for _, w in window:
        x = math.log(w)
        # Medyan varyansı ≈ (π/2)·σ²/n: fark (x − medyan) referansın belirsizliğini de taşır.
        scale = sigma * math.sqrt(1.0 + pp.median_variance_factor / len(prev))
        z = min((x - _median(prev)) / scale, pp.clip_z)
        s = max(0.0, s + z - pp.k)
        s_max = max(s_max, s)
        prev.append(x)
    status = PlateauStatus.PROGRESSING if s_max >= pp.h else PlateauStatus.PLATEAU
    return Plateau(status, len(window), len(reference), s_max, sigma)


# --------------------------------------------------------------------------- tahmin


@dataclass(frozen=True)
class ForecastPoint:
    weeks: float
    e1rm: float
    low: float
    high: float


@dataclass(frozen=True)
class Forecast:
    status: Status
    points: tuple[ForecastPoint, ...] = ()
    slope_used: float | None = None  # ln(kg)/gün, kırpılmış


def forecast(
    tr: Trend,
    percentile: float,
    params: ProgressParams,
    training_years: float | None = None,
    horizons_weeks: Sequence[float] | None = None,
) -> Forecast:
    """4/8/12 hafta e1RM tahmini.

    Sönümlü eğilim; eğim gerçekçi sınırlara kırpılır; belirsizlik bandı zamanla genişler.
    """
    fp = params.forecast
    horizons = tuple(fp.horizons_weeks if horizons_weeks is None else horizons_weeks)
    for h in horizons:
        if not 0 < h <= fp.max_horizon_weeks:
            raise ValueError(f"tahmin ufku (0, {fp.max_horizon_weeks}] hafta dışında: {h}")
    if tr.status is not Status.OK or tr.fit is None or tr.t_last is None or tr.sigma is None:
        return Forecast(Status.INSUFFICIENT_DATA)
    dpm = params.days_per_month
    exp_log_month = math.log1p(expected_monthly_gain(percentile, params, training_years))
    hi = fp.max_ratio_to_expected * exp_log_month / dpm
    lo = math.log1p(-fp.max_monthly_loss) / dpm
    slope = min(max(tr.fit.slope, lo), hi)
    se_slope = (tr.fit.slope_high - tr.fit.slope_low) / (2.0 * params.trend.ci_z)
    level = tr.fit.intercept + tr.fit.slope * tr.t_last
    z = params.trend.ci_z
    d = fp.damping_days
    pts = []
    for h in horizons:
        eff = d * (1.0 - math.exp(-h * DAYS_PER_WEEK / d))  # sönümlü etkin gün sayısı
        mid = level + slope * eff
        half = z * math.sqrt(tr.sigma**2 + (se_slope * eff) ** 2)
        pts.append(ForecastPoint(h, math.exp(mid), math.exp(mid - half), math.exp(mid + half)))
    return Forecast(Status.OK, tuple(pts), slope)


# --------------------------------------------------------------------------- toplu


@dataclass(frozen=True)
class ProgressReport:
    trend: Trend
    score: ProgressScore
    plateau: Plateau
    forecast: Forecast


def analyze(
    sessions: Sequence[Session],
    percentile: float,
    params: ProgressParams,
    training_years: float | None = None,
) -> ProgressReport:
    tr = trend(sessions, params)
    return ProgressReport(
        trend=tr,
        score=progress_score(tr, percentile, params, training_years),
        plateau=detect_plateau(sessions, params),
        forecast=forecast(tr, percentile, params, training_years),
    )
