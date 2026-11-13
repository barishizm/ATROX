"""P057 skor hattı: özellik ve birim testleri (sentetik çapa modeliyle; CI'da pickle gerekmez)."""

from __future__ import annotations

import itertools
from dataclasses import replace
from datetime import date, timedelta
from pathlib import Path

import numpy as np
import polars as pl
import pytest
from scipy.stats import norm

from gymml.scoring import (
    AnchorModel,
    CurrentStrength,
    Exercise,
    LoggedSet,
    Params,
    User,
    calibrate_z,
    combine,
    current_strength,
    exercise_score,
    level_key,
    muscle_group_scores,
    overall_score,
    score_set,
)

P = Params.load()
TODAY = date(2026, 11, 13)
SIGMA = 0.2


class Truth:
    """Log-normal çapa: log Y = a(sex, lift) + (2/3) log bw − 0.0004 (yaş − 30)²."""

    A = {("M", "squat"): 2.0, ("M", "bench"): 1.6, ("M", "deadlift"): 2.2,
         ("F", "squat"): 1.6, ("F", "bench"): 1.0, ("F", "deadlift"): 1.8}  # fmt: skip

    def __init__(self, lift: str):
        self.lift = lift

    def mu(self, x: pl.DataFrame) -> np.ndarray:
        a = np.array([self.A[(s, self.lift)] for s in x["sex"]])
        return (
            a
            + (2 / 3) * np.log(x["bodyweight_kg"].to_numpy())
            - 0.0004 * (x["age"].to_numpy() - 30) ** 2
        )

    def quantile(self, x, q):
        return np.exp(self.mu(x)[:, None] + SIGMA * norm.ppf(np.asarray(q))[None, :])

    def cdf(self, x, y):
        return norm.cdf((np.log(np.asarray(y, float)) - self.mu(x)) / SIGMA)


MODEL = AnchorModel({lift: Truth(lift) for lift in ("squat", "bench", "deadlift")}, P)
MAN = User("M", 30, 80)


def ex(
    id_="bench",
    anchor="bench",
    ratio=1.0,
    tau=0.02,
    grade="A",
    src="anchor",
    pattern="horizontal_push",
    stype="weighted",
    conv="total",
    prim=("chest",),
    sec=("triceps",),
    equipment="barbell",
    bw_fraction=None,
):
    return Exercise(
        id_, pattern, stype, conv, anchor, ratio, tau, grade, bw_fraction, src, prim, sec, equipment
    )


BENCH = ex()
SQUAT = ex("squat", "squat", pattern="squat", prim=("quadriceps",), sec=("glutes",))
DEAD = ex("deadlift", "deadlift", pattern="hip_hinge", prim=("hamstrings",), sec=("lower_back",))
OHP = ex(
    "ohp", "bench", 0.65, 0.4, "C", "expert", "vertical_push", prim=("shoulders",), sec=("triceps",)
)
ROW = ex(
    "row", "bench", 0.8, 0.4, "C", "expert", "horizontal_pull", prim=("lats",), sec=("biceps",)
)
LEGPRESS = ex("legpress", "squat", 0.85, 0.5, "C", "expert", "squat", conv="per_side",
              prim=("quadriceps",), equipment="machine")  # fmt: skip
PULLUP = ex("pullup", "bench", 1.15, 0.4, "C", "expert", "vertical_pull", stype="bodyweight_loaded",
            conv="bodyweight_plus", prim=("lats",), sec=("biceps",), bw_fraction=1.0)  # fmt: skip
CATALOG = {e.id: e for e in (BENCH, SQUAT, DEAD, OHP, ROW, LEGPRESS, PULLUP)}


def sessions(weight, reps=5, days=(3, 10, 17, 24), rir=1):
    return [LoggedSet(TODAY - timedelta(days=d), weight, reps, rir) for d in days]


def score_of(e: Exercise, weight, user=MAN, pop="gym", **kw):
    cs = current_strength(e, sessions(weight, **kw), user, TODAY, P)
    return exercise_score(e, cs, user, MODEL, P, pop)


# --- set ve güncel güç ---


def test_single_rep_e1rm_is_the_weight_and_confidence_drops_with_reps():
    s1 = score_set(BENCH, LoggedSet(TODAY, 100, 1, rir=0), MAN, P)
    s12 = score_set(BENCH, LoggedSet(TODAY, 100, 12, rir=0), MAN, P)
    assert s1.e1rm_kg == pytest.approx(100.0)
    assert s12.e1rm_kg > 100 and s12.confidence < s1.confidence
    assert score_set(BENCH, LoggedSet(TODAY, 100, 5, is_warmup=True), MAN, P).confidence == 0


def test_bodyweight_loaded_uses_effective_load():
    s = score_set(PULLUP, LoggedSet(TODAY, 0, 1, rir=0), MAN, P)
    assert s.e1rm_kg == pytest.approx(80.0)


def test_current_strength_window_and_confidence():
    cs = current_strength(BENCH, sessions(100), MAN, TODAY, P)
    assert cs.sessions_in_window == 4 and cs.confidence == "high" and not cs.stale
    one = current_strength(BENCH, sessions(100, days=(3,)), MAN, TODAY, P)
    assert one.confidence == "low"


def test_outlier_jump_is_flagged_until_confirmed():
    sets = sessions(100, days=(20, 13)) + [LoggedSet(TODAY - timedelta(days=2), 125, 5, 1)]
    cs = current_strength(BENCH, sets, MAN, TODAY, P)
    assert len(cs.flagged) == 1
    base = current_strength(BENCH, sessions(100, days=(20, 13)), MAN, TODAY, P)
    assert cs.e1rm_kg == pytest.approx(base.e1rm_kg)
    sets[-1] = replace(sets[-1], confirmed=True)
    assert current_strength(BENCH, sets, MAN, TODAY, P).e1rm_kg > base.e1rm_kg


def test_stale_data_decays_and_is_low_confidence():
    fresh = current_strength(BENCH, sessions(100, days=(3,)), MAN, TODAY, P)
    old = current_strength(BENCH, sessions(100, days=(42 + 70,)), MAN, TODAY, P)
    assert old.stale and old.confidence == "low"
    assert old.e1rm_kg == pytest.approx(fresh.e1rm_kg * (1 - 0.005) ** 10, rel=1e-3)


# --- hareket skoru ---


def test_competitor_anchor_score_matches_model_percentile():
    s = score_of(BENCH, 100, reps=1, rir=0, pop="competitor")
    x = pl.DataFrame({"sex": ["M"], "age": [30.0], "bodyweight_kg": [80.0]})
    expected = 100 * Truth("bench").cdf(x, [100.0])[0]
    shrink = 1 / np.sqrt(1 + (0.02 / SIGMA) ** 2)
    assert s.score == pytest.approx(100 * norm.cdf(norm.ppf(expected / 100) * shrink), abs=0.05)


def test_gym_population_scores_higher_than_competitors():
    assert score_of(BENCH, 80, pop="gym").score > score_of(BENCH, 80, pop="competitor").score


def test_calibrate_identity_for_competitor():
    assert calibrate_z(0.3, 0.2, "competitor", "M", "bench", 30, P) == (0.3, 0.2)


def test_c_grade_is_shrunk_toward_the_middle():
    # Aynı çapa eşdeğeri (OHP 0.65 × bench): C sınıfı A'dan daha az uç, güven düşük.
    for bench_kg in (60, 140, 200):
        a = score_of(BENCH, bench_kg, pop="competitor")
        c = score_of(OHP, bench_kg * 0.65, pop="competitor")
        assert abs(c.score - 50) < abs(a.score - 50) and c.confidence == "low"
    # Yarışmacı ölçeğinde (s ≈ 0.2) |z_çapa| = 3 bile C sınıfında [5, 95] içinde kalır (P056).
    x = pl.DataFrame({"sex": ["M"], "age": [30.0], "bodyweight_kg": [80.0]})
    q3 = float(Truth("bench").quantile(x, [norm.cdf(3)])[0, 0])
    assert score_of(OHP, q3 * 0.65, reps=1, rir=0, pop="competitor").score <= 95


def test_machine_is_low_confidence():
    s = score_of(LEGPRESS, 150)
    assert s.is_machine and s.confidence == "low"


def test_unspecified_sex_is_between_male_and_female():
    m = score_of(BENCH, 70, user=User("M", 30, 70)).score
    f = score_of(BENCH, 70, user=User("F", 30, 70)).score
    u = score_of(BENCH, 70, user=User(None, 30, 70)).score
    assert min(m, f) < u < max(m, f)


def test_band_contains_score_and_none_for_unscorable():
    s = score_of(OHP, 60)
    assert s.band[0] <= s.score <= s.band[1]
    none = Exercise("stretch", "mobility", "none")
    assert exercise_score(none, CurrentStrength(None, "low", False, 0), MAN, MODEL, P) is None


def test_levels():
    assert [level_key(v, P) for v in (5, 25, 45, 65, 85, 97)] == [
        "beginner", "developing", "intermediate", "advanced", "expert", "elite"]  # fmt: skip


# --- birleştirme özellikleri (prompt P057) ---


def test_single_exercise_group_equals_that_exercise():
    s = score_of(BENCH, 90)
    only = Exercise(**{**BENCH.__dict__, "secondary_muscles": ()})
    g = muscle_group_scores([s], {"bench": only}, P)
    assert g["chest"].score == pytest.approx(s.score) and g["chest"].z == pytest.approx(s.z)


def test_equal_scores_combine_to_same_score_when_perfectly_correlated():
    # §8 formülü varyansı 1'e geri ölçekler: r = 1'de birleşim aynı skor; r < 1'de aynı yönde uç
    # (bkz. reports/scoring_profiles.md notu). 50 her durumda 50 kalır.
    for z in (-1.2, 0.0, 0.7):
        assert combine([z, z], [1, 1], np.array([[1, 1.0], [1.0, 1]])) == pytest.approx(z)
        c = combine([z, z], [1, 1], np.array([[1, 0.6], [0.6, 1]]))
        assert np.sign(c) == np.sign(z) and abs(c) >= abs(z) - 1e-12


def _all(scores):
    return (muscle_group_scores(scores, CATALOG, P), overall_score(scores, CATALOG, P))


def test_more_weight_never_lowers_any_score():
    weights = {"bench": 80, "squat": 100, "deadlift": 130, "ohp": 50, "row": 60, "legpress": 120,
               "pullup": 5}  # fmt: skip
    base = [score_of(CATALOG[k], w) for k, w in weights.items()]
    g0, o0 = _all(base)
    for k in weights:
        heavier = [score_of(CATALOG[j], w + (10 if j == k else 0)) for j, w in weights.items()]
        assert all(h.score >= b.score - 1e-9 for h, b in zip(heavier, base, strict=True))
        g1, o1 = _all(heavier)
        assert all(g1[m].z >= g0[m].z - 1e-12 for m in g0)
        assert o1.z >= o0.z - 1e-12


def test_input_order_does_not_change_results():
    sets = sessions(100, days=(3, 10)) + sessions(95, reps=6, days=(17,))
    a = current_strength(BENCH, sets, MAN, TODAY, P)
    b = current_strength(BENCH, list(reversed(sets)), MAN, TODAY, P)
    assert a == b
    scores = [score_of(BENCH, 80), score_of(SQUAT, 100), score_of(ROW, 60), score_of(OHP, 45)]
    ref = _all(scores)
    for perm in itertools.permutations(scores):
        g, o = _all(list(perm))
        assert o.z == pytest.approx(ref[1].z)
        assert {k: v.z for k, v in g.items()} == pytest.approx({k: v.z for k, v in ref[0].items()})


def test_overall_is_provisional_without_upper_and_lower():
    upper_only = [score_of(BENCH, 80), score_of(OHP, 50), score_of(ROW, 60)]
    assert overall_score(upper_only, CATALOG, P).provisional
    full = upper_only + [score_of(SQUAT, 100)]
    assert not overall_score(full, CATALOG, P).provisional


# --- params ---


def test_params_have_no_missing_sections():
    s = P.scoring
    for key in ("anchor_model", "current_strength", "exercise_score", "aggregate", "levels"):
        assert key in s
    assert P.correlation.shape == (3, 3) and np.allclose(P.correlation, P.correlation.T)


PICKLES = Path(__file__).resolve().parents[1] / "runs/bakeoff/model_A_bench.pkl"


@pytest.mark.skipif(not PICKLES.exists(), reason="P053 model pickle yok (bakeoff all --cand A)")
def test_real_anchor_model_typical_user():
    model = AnchorModel.load(P)
    cs = current_strength(BENCH, sessions(80, reps=1, rir=0), MAN, TODAY, P)
    s = exercise_score(BENCH, cs, MAN, model, P, "gym")
    assert 15 <= s.score <= 40  # P055: 80 kg erkek, bench 80 → salon ≈ 26
