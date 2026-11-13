"""P058 gelişim analitiği: sentetik serilerle testler."""

import json
import math
import random

import pytest

from gymml import progress as pg
from gymml.progress import PlateauStatus, Status


@pytest.fixture(scope="module")
def params() -> pg.ProgressParams:
    return pg.load_params()


def series(weeks: int, per_week: int, start: float, monthly: float, noise: float, seed: int):
    """Geometrik eğilimli (aylık `monthly` oranı), log-normal gürültülü oturum serisi."""
    rng = random.Random(seed)
    dpm = 30.4375
    out = []
    for i in range(weeks * per_week):
        t = i * 7.0 / per_week
        mean = start * (1 + monthly) ** (t / dpm)
        out.append((t, mean * math.exp(rng.gauss(0.0, noise))))
    return out


# ------------------------------------------------------------------ parametreler


def test_params_file_labels_assumptions():
    raw = json.loads(pg.DEFAULT_PARAMS_PATH.read_text())
    for block in ("expected_curve", "score", "plateau", "forecast", "trend"):
        assert raw[block]["provenance"] in {"assumption", "source", "convention", "definition"}
    assert raw["expected_curve"]["provenance"] == "assumption"
    assert "assumption" in raw["expected_curve"]["_doc"].lower()


def test_params_reject_unknown_key():
    raw = json.loads(pg.DEFAULT_PARAMS_PATH.read_text())
    raw["trend"]["surprise"] = 1
    with pytest.raises(ValueError):
        pg.params_from_dict(raw)


# ------------------------------------------------------------------ Theil–Sen / eğilim


def test_theil_sen_exact_line():
    ts = [0, 1, 2, 3, 4, 5]
    fit = pg.theil_sen(ts, [2 + 0.5 * t for t in ts], z=1.96)
    assert fit.slope == pytest.approx(0.5)
    assert fit.intercept == pytest.approx(2.0)
    assert fit.slope_low == pytest.approx(0.5) and fit.slope_high == pytest.approx(0.5)


@pytest.mark.parametrize("monthly", [0.04, 0.01, 0.0, -0.02])
def test_known_slope_recovered(params, monthly):
    s = series(weeks=12, per_week=3, start=100.0, monthly=monthly, noise=0.015, seed=1)
    tr = pg.trend(s, params)
    assert tr.status is Status.OK
    assert tr.monthly_pct == pytest.approx(monthly, abs=0.006)
    assert tr.monthly_pct_low <= monthly <= tr.monthly_pct_high


def test_single_outlier_does_not_break_trend(params):
    s = series(weeks=10, per_week=2, start=100.0, monthly=0.02, noise=0.0, seed=0)
    clean = pg.trend(s, params)
    spiked = list(s)
    t, w = spiked[9]
    spiked[9] = (t, w * 1.6)  # tek bir +%60 hatalı kayıt
    dirty = pg.trend(spiked, params)
    assert clean.monthly_pct == pytest.approx(0.02, abs=1e-9)
    assert dirty.monthly_pct == pytest.approx(clean.monthly_pct, abs=0.002)


def test_min_data_rule(params):
    # 3 oturum: yetersiz
    assert pg.trend([(0, 100), (7, 101), (14, 102)], params).status is Status.INSUFFICIENT_DATA
    # 6 oturum ama 2 haftalık yayılım: yetersiz
    short = [(d, 100 + d) for d in (0, 2, 4, 7, 10, 13)]
    assert pg.trend(short, params).status is Status.INSUFFICIENT_DATA
    # 4 oturum, 3 hafta: yeterli
    ok = [(0, 100), (7, 101), (14, 102), (21, 103)]
    assert pg.trend(ok, params).status is Status.OK
    assert pg.trend([], params).status is Status.INSUFFICIENT_DATA


def test_trend_uses_only_recent_window(params):
    old = [(float(d), 50.0) for d in range(0, 100, 3)]  # pencere dışında, çok düşük
    recent = series(weeks=12, per_week=3, start=100.0, monthly=0.01, noise=0.0, seed=0)
    shifted = [(t + 200.0, w) for t, w in recent]
    tr = pg.trend(old + shifted, params)
    assert tr.monthly_pct == pytest.approx(0.01, abs=1e-6)


def test_invalid_rows_ignored(params):
    s = [(0, 100), (7, 101), (10, -5), (14, 102), (17, float("nan")), (21, 103)]
    assert pg.trend(s, params).n_sessions == 4


# ------------------------------------------------------------------ beklenen eğri ve skor


def test_expected_curve_diminishing_returns(params):
    gains = [pg.expected_monthly_gain(p, params) for p in (0, 25, 50, 75, 100)]
    assert all(a > b for a, b in zip(gains, gains[1:], strict=False))
    assert pg.expected_monthly_gain(50, params, 0) > pg.expected_monthly_gain(50, params, 5)
    floor = params.expected_curve.floor_monthly_gain
    assert pg.expected_monthly_gain(100, params, 50) > floor


def test_score_anchors_and_clamp(params):
    assert pg.score_from_ratio(-5, params) == 0
    assert pg.score_from_ratio(0, params) == 30
    assert pg.score_from_ratio(1, params) == 70
    assert pg.score_from_ratio(9, params) == 100
    assert pg.score_from_ratio(0.5, params) == pytest.approx(50)


def test_same_gain_means_more_for_advanced(params):
    s = series(weeks=12, per_week=3, start=100.0, monthly=0.01, noise=0.0, seed=0)
    tr = pg.trend(s, params)
    novice = pg.progress_score(tr, 5, params)
    advanced = pg.progress_score(tr, 90, params)
    assert advanced.score > novice.score
    for sc in (novice, advanced):
        assert 0 <= sc.score_low <= sc.score <= sc.score_high <= 100


def test_score_on_track_is_70(params):
    g = pg.expected_monthly_gain(60, params)
    s = series(weeks=12, per_week=3, start=100.0, monthly=g, noise=0.0, seed=0)
    sc = pg.progress_score(pg.trend(s, params), 60, params)
    assert sc.ratio == pytest.approx(1.0, abs=1e-6)
    assert sc.score == pytest.approx(70.0, abs=1e-4)


def test_score_insufficient(params):
    sc = pg.progress_score(pg.trend([(0, 100)], params), 50, params)
    assert sc.status is Status.INSUFFICIENT_DATA and sc.score is None


# ------------------------------------------------------------------ plato


SEEDS = range(200)


def _plateau_rate(make) -> float:
    p = pg.load_params()
    hits = [pg.detect_plateau(make(seed), p).status is PlateauStatus.PLATEAU for seed in SEEDS]
    return sum(hits) / len(hits)


@pytest.mark.parametrize("noise", [0.01, 0.02, 0.03])
def test_noisy_flat_series_is_plateau(noise):
    rate = _plateau_rate(lambda seed: series(12, 3, 100.0, 0.0, noise, seed))
    assert rate >= 0.8


@pytest.mark.parametrize("noise", [0.01, 0.02])
def test_false_plateau_alarm_is_bounded(noise):
    # +%4/ay ilerleyen biri: "plato" yanlış alarmı sınırlı kalmalı.
    rate = _plateau_rate(lambda seed: series(12, 3, 100.0, 0.04, noise, seed))
    assert rate <= 0.1


def test_single_spike_does_not_cancel_plateau(params):
    s = series(weeks=12, per_week=3, start=100.0, monthly=0.0, noise=0.01, seed=3)
    s[-3] = (s[-3][0], s[-3][1] * 1.3)
    assert pg.detect_plateau(s, params).status is PlateauStatus.PLATEAU


def test_plateau_after_progress(params):
    rising = series(weeks=8, per_week=3, start=100.0, monthly=0.05, noise=0.0, seed=0)
    top = rising[-1][1]
    flat = series(weeks=9, per_week=3, start=top, monthly=0.0, noise=0.01, seed=5)
    s = rising + [(t + rising[-1][0] + 2.0, w) for t, w in flat]
    assert pg.detect_plateau(s, params).status is PlateauStatus.PLATEAU


def test_plateau_needs_frequency(params):
    sparse = [(float(d), 100.0) for d in range(0, 70, 14)]  # iki haftada bir
    assert pg.detect_plateau(sparse, params).status is PlateauStatus.INSUFFICIENT_DATA
    assert pg.detect_plateau([], params).status is PlateauStatus.INSUFFICIENT_DATA


# ------------------------------------------------------------------ tahmin


def test_forecast_band_widens_and_contains_mid(params):
    s = series(weeks=12, per_week=3, start=100.0, monthly=0.01, noise=0.02, seed=4)
    fc = pg.forecast(pg.trend(s, params), 50, params)
    assert fc.status is Status.OK
    assert [p.weeks for p in fc.points] == [4, 8, 12]
    widths = [math.log(p.high / p.low) for p in fc.points]
    assert widths[0] < widths[1] < widths[2]
    for p in fc.points:
        assert p.low < p.e1rm < p.high


def test_forecast_follows_trend_with_damping(params):
    s = series(weeks=12, per_week=3, start=100.0, monthly=0.01, noise=0.0, seed=0)
    tr = pg.trend(s, params)
    fc = pg.forecast(tr, 20, params)
    last = s[-1][1]
    mids = [p.e1rm for p in fc.points]
    assert last < mids[0] < mids[1] < mids[2]
    linear_12w = last * (1.01) ** (84 / 30.4375)
    assert mids[2] < linear_12w  # sönüm: doğrusal uzatmanın altında


def test_forecast_caps_unrealistic_slope(params):
    # Ayda %30 artış: beklenen eğrinin max_ratio katına kırpılmalı.
    s = series(weeks=6, per_week=3, start=60.0, monthly=0.30, noise=0.0, seed=0)
    tr = pg.trend(s, params)
    fc = pg.forecast(tr, 80, params)
    cap = params.forecast.max_ratio_to_expected * math.log1p(pg.expected_monthly_gain(80, params))
    assert fc.slope_used * params.days_per_month == pytest.approx(cap)
    assert fc.points[-1].e1rm < s[-1][1] * 1.30 ** (84 / 30.4375)


def test_forecast_caps_loss(params):
    s = series(weeks=6, per_week=3, start=100.0, monthly=-0.30, noise=0.0, seed=0)
    fc = pg.forecast(pg.trend(s, params), 50, params)
    floor = math.log1p(-params.forecast.max_monthly_loss)
    assert fc.slope_used * params.days_per_month == pytest.approx(floor)


def test_forecast_rejects_long_horizon(params):
    s = series(weeks=6, per_week=3, start=100.0, monthly=0.01, noise=0.0, seed=0)
    with pytest.raises(ValueError):
        pg.forecast(pg.trend(s, params), 50, params, horizons_weeks=[26])


def test_analyze_is_deterministic(params):
    s = series(weeks=12, per_week=3, start=100.0, monthly=0.02, noise=0.02, seed=9)
    a = pg.analyze(s, 40, params, training_years=1.5)
    b = pg.analyze(list(reversed(s)), 40, params, training_years=1.5)  # sıra önemsiz
    assert a == b
    assert a.trend.status is Status.OK and a.forecast.status is Status.OK
