"""P054 1RM modülü: özellik testleri, literatür uydurması, öz-denetimli kayıp (sentetik)."""

from __future__ import annotations

import json

import numpy as np
import pytest

from gymml.models import e1rm as m
from gymml.utils.config import ML_ROOT

REPS = np.arange(1, 31, dtype=float)


def _fitted_curves() -> dict[str, m.Curve]:
    df = m.fit_table(m.load_rep_tables())
    return {c: f.curve for c, f in m.fit_categories(df).items()}


def _all_curves() -> list[m.Curve]:
    curves = [m.Curve.default(f) for f in m.FAMILIES]
    curves += list(_fitted_curves().values())
    df = m.fit_table(m.load_rep_tables())
    for fam in m.FAMILIES:
        curves += [f.curve for f in m.fit_categories(df, fam).values()]
    return curves


ALL = _all_curves()
IDS = [f"{c.family}-{i}" for i, c in enumerate(ALL)]


# --- Özellik testleri -----------------------------------------------------------------------------


@pytest.mark.parametrize("curve", ALL, ids=IDS)
def test_one_rep_is_the_weight_itself(curve: m.Curve) -> None:
    assert curve.fraction(1.0) == pytest.approx(1.0, abs=1e-12)
    assert curve.e1rm(102.5, 1) == pytest.approx(102.5, abs=1e-9)


@pytest.mark.parametrize("curve", ALL, ids=IDS)
def test_e1rm_increases_with_reps(curve: m.Curve) -> None:
    e = curve.e1rm(100.0, REPS)
    assert np.all(np.diff(e) > 0)
    assert np.all(curve.fraction(REPS) > 0)


@pytest.mark.parametrize("curve", ALL, ids=IDS)
def test_e1rm_increases_with_weight(curve: m.Curve) -> None:
    w = np.linspace(2.5, 300, 50)
    for r in (1, 5, 12, 25):
        assert np.all(np.diff(curve.e1rm(w, r)) > 0)


def test_standard_epley_would_violate_f1_but_ours_does_not() -> None:
    # Standart Epley: e1RM = w(1 + r/30) -> 1 tekrarda w·1.033. Bizim düzeltmemiz (r − 1).
    assert 100 * (1 + 1 / 30) != pytest.approx(100.0)
    assert m.Curve.default("epley").e1rm(100, 1) == pytest.approx(100.0)
    # Düzeltilmiş Epley, p = 1 olan genel biçimle aynıdır.
    g = m.Curve("general", {"k": 30.0, "p": 1.0})
    np.testing.assert_allclose(m.Curve.default("epley").fraction(REPS), g.fraction(REPS))


def test_reps_beyond_rmax_do_not_extrapolate() -> None:
    c = m.Curve.default("brzycki")  # ham Brzycki r = 37'de sıfıra iner
    assert np.isfinite(c.e1rm(50, 60))
    assert c.e1rm(50, 60) == pytest.approx(c.e1rm(50, m.R_MAX))


def test_reps_at_inverts_fraction() -> None:
    c = _fitted_curves()["upper_push"]
    r = np.array([2.0, 5.0, 10.0, 20.0])
    np.testing.assert_allclose(c.reps_at(c.fraction(r)), r, atol=0.02)


def test_missing_param_rejected() -> None:
    with pytest.raises(ValueError):
        m.Curve("general", {"k": 30.0})


# --- Güven ağırlığı ve RIR ------------------------------------------------------------------------


def test_confidence_knots() -> None:
    c = m.confidence([1, 3, 5, 12, 20, 30, 31, 50])
    np.testing.assert_allclose(c, [1, 1, 1, 0.6, 0.25, 0, 0, 0])


def test_confidence_linear_between_knots_and_nonincreasing() -> None:
    assert m.confidence(8.5) == pytest.approx(0.8)
    assert m.confidence(16) == pytest.approx(0.425)
    assert m.confidence(25) == pytest.approx(0.125)
    grid = np.linspace(1, 40, 400)
    assert np.all(np.diff(m.confidence(grid)) <= 1e-12)


def test_confidence_zero_from_30_reps() -> None:
    for r in (30, 30.5, 45, 100):
        assert m.confidence(r) == 0.0


def test_confidence_rir_unknown_and_warmup() -> None:
    assert m.confidence(5, rir_known=False) == pytest.approx(0.85)
    assert m.confidence(12, rir_known=False) == pytest.approx(0.51)
    assert m.confidence(3, is_warmup=True) == 0.0


def test_rir_adds_to_effective_reps() -> None:
    c = _fitted_curves()["lower_compound"]
    with_rir = m.estimate_set(100, 5, c, rir=2)
    to_failure = m.estimate_set(100, 7, c, rir=0)
    assert with_rir.r_eff == 7
    assert with_rir.e1rm_kg == pytest.approx(to_failure.e1rm_kg)
    assert with_rir.confidence == pytest.approx(to_failure.confidence)


def test_missing_rir_is_not_treated_as_zero() -> None:
    c = _fitted_curves()["upper_push"]
    unknown = m.estimate_set(80, 8, c, rir=None)
    zero = m.estimate_set(80, 8, c, rir=0)
    assert unknown.e1rm_kg == pytest.approx(zero.e1rm_kg)  # değer alt sınır olarak aynı
    assert unknown.confidence == pytest.approx(0.85 * zero.confidence)


def test_warmup_set_is_excluded() -> None:
    est = m.estimate_set(60, 5, _fitted_curves()["general"], rir=3, is_warmup=True)
    assert est.confidence == 0.0


@pytest.mark.parametrize(
    ("w", "r", "rir"), [(0, 5, None), (-5, 5, None), (50, 0, None), (50, 5, -1)]
)
def test_invalid_sets_rejected(w: float, r: int, rir: float | None) -> None:
    with pytest.raises(ValueError):
        m.estimate_set(w, r, m.Curve.default("general"), rir=rir)


def test_category_for_pattern() -> None:
    assert m.category_for_pattern("squat") == "lower_compound"
    assert m.category_for_pattern("hip_hinge") == "lower_compound"
    assert m.category_for_pattern("vertical_push") == "upper_push"
    assert m.category_for_pattern("horizontal_pull") == "upper_pull"
    assert m.category_for_pattern("isolation_biceps") == "isolation"
    assert m.category_for_pattern("carry") == "general"
    assert m.category_for_pattern(None) == "general"


# --- Literatür uydurması --------------------------------------------------------------------------


@pytest.mark.parametrize("family", list(m.FAMILIES))
def test_fit_rep_table_recovers_known_curve(family: str) -> None:
    true = m.Curve.default(family)
    r = np.array([2.0, 4.0, 6.0, 8.0, 10.0, 14.0, 20.0, 26.0])
    fit = m.fit_rep_table(family, r, true.fraction(r))
    np.testing.assert_allclose(fit.curve.theta, true.theta, rtol=1e-3)
    assert fit.rmse_log < 1e-6


def test_fit_table_uses_contrasts_and_reference_only() -> None:
    raw = m.load_rep_tables()
    ft = m.fit_table(raw)
    assert set(ft["source"]) == {"nuzzo2024", "ferrari2017"}
    # Ferrari bench, karşıtlığın referansıdır; uydurmaya ayrıca girmez.
    assert ft.filter(ft["source"] == "ferrari2017")["exercise"].to_list().count("bench_press") == 0
    assert (ft["mean_reps"] <= m.R_MAX).all()
    assert (ft["se_log"] > 0).all()


def test_every_category_fitted_with_low_error() -> None:
    df = m.fit_table(m.load_rep_tables())
    fits = m.fit_categories(df)
    assert set(fits) == set(m.CATEGORIES)
    for fit in fits.values():
        assert fit.rmse_log < 0.03  # ağırlıklı göreli e1RM hatası < %3
        assert fit.n_points >= 6


def test_lower_body_allows_more_reps_than_upper_at_same_load() -> None:
    c = _fitted_curves()
    for pct in (0.6, 0.7, 0.8):
        assert c["lower_compound"].reps_at(pct) > c["upper_push"].reps_at(pct)


def test_params_draft_matches_fit_and_is_sourced() -> None:
    path = ML_ROOT / "params_draft/e1rm.json"
    params = json.loads(path.read_text(encoding="utf-8"))
    expected = m.build_params(m.load_rep_tables())
    assert params == json.loads(json.dumps(expected))  # taslak güncel (yeniden üretilebilir)
    report = (ML_ROOT / "reports/e1rm_literature.md").read_text(encoding="utf-8")
    for cat, v in params["categories"].items():
        assert v["sources"], cat
        for src in v["sources"]:
            assert src in report, src


# --- Kendi kendini denetleyen kayıp (sentetik) ----------------------------------------------------


def _synthetic(true: m.Curve, n_groups: int = 400, noise: float = 0.01, seed: int = 0):
    rng = np.random.default_rng(seed)
    groups, weights, reps = [], [], []
    for g in range(n_groups):
        one_rm = rng.uniform(40, 200)
        for r in rng.choice(np.arange(1, 16), size=rng.integers(2, 6), replace=False):
            groups.append(g)
            reps.append(float(r))
            weights.append(one_rm * float(true.fraction(r)) * np.exp(rng.normal(0, noise)))
    return np.array(groups), np.array(weights), np.array(reps)


def test_within_window_loss_is_zero_at_truth_without_noise() -> None:
    true = m.Curve("general", {"k": 28.0, "p": 1.3})
    g, w, r = _synthetic(true, n_groups=50, noise=0.0)
    assert m.within_window_loss("general", true.theta, g, w, r) < 1e-20
    assert m.within_window_loss("general", (15.0, 1.0), g, w, r) > 1e-4


@pytest.mark.parametrize(
    ("family", "params", "rtol"),
    [("general", {"k": 28.0, "p": 1.3}, 0.10), ("epley", {"k": 35.0}, 0.05)],
)
def test_self_supervised_recovers_true_parameters(
    family: str, params: dict[str, float], rtol: float
) -> None:
    true = m.Curve(family, params)
    g, w, r = _synthetic(true, noise=0.01)
    fitted = m.fit_self_supervised(family, g, w, r)
    np.testing.assert_allclose(fitted.theta, true.theta, rtol=rtol)
    # Kayıp, başlangıç (yaygın) parametrelerden daha düşük.
    assert m.within_window_loss(family, fitted.theta, g, w, r) <= m.within_window_loss(
        family, m.Curve.default(family).theta, g, w, r
    )


def test_self_supervised_ignores_single_set_groups_and_uses_confidence() -> None:
    true = m.Curve("general", {"k": 22.0, "p": 1.2})
    g, w, r = _synthetic(true, n_groups=300, noise=0.01, seed=1)
    # Tek setli gürültü grupları eklenir: sonucu bozmamalı.
    g2 = np.concatenate([g, np.arange(10_000, 10_050)])
    w2 = np.concatenate([w, np.full(50, 999.0)])
    r2 = np.concatenate([r, np.full(50, 3.0)])
    conf = m.confidence(r2)
    fitted = m.fit_self_supervised("general", g2, w2, r2, conf=conf)
    np.testing.assert_allclose(fitted.theta, true.theta, rtol=0.10)


def test_self_supervised_needs_multi_set_groups() -> None:
    with pytest.raises(ValueError):
        m.fit_self_supervised("general", np.array([1, 2]), np.array([50.0, 60.0]), np.array([5, 6]))
