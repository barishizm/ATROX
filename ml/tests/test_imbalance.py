"""P059: dengesizlik analizi testleri."""

from __future__ import annotations

import copy
import json

import numpy as np
import pytest

from gymml.imbalance import (
    DEFAULT_PARAMS_PATH,
    KIND_LEFT_RIGHT,
    KIND_RATIO,
    KIND_RESIDUAL,
    ImbalanceParams,
    ScoreInput,
    UnilateralInput,
    analyze,
    conditional_moments,
    load_params,
)


@pytest.fixture(scope="module")
def raw_params() -> dict:
    with open(DEFAULT_PARAMS_PATH, encoding="utf-8") as fh:
        return json.load(fh)


@pytest.fixture(scope="module")
def params() -> ImbalanceParams:
    return load_params()


def profile(
    z: float = 0.8, confidence: str = "high", bench: float | None = None
) -> list[ScoreInput]:
    """Her kalıptan bir hareket; hepsi aynı z (dengeli). ``bench`` verilirse bench z'si o olur."""
    def s(eid, pattern, key=None, zz=z, muscles=()):
        return ScoreInput(eid, zz, confidence, pattern, corr_key=key, muscles=muscles)

    return [
        s("back_squat", "squat", "squat", muscles=("quads", "glutes")),
        s("bench_press", "horizontal_push", "bench", zz=z if bench is None else bench,
          muscles=("chest", "triceps")),
        s("deadlift", "hinge", "deadlift", muscles=("hamstrings", "glutes", "lower_back")),
        s("overhead_press", "vertical_push", muscles=("shoulders",)),
        s("barbell_row", "horizontal_pull", muscles=("upper_back", "lats")),
        s("weighted_pull_up", "vertical_pull", muscles=("lats", "biceps")),
    ]


# --- Kabul testleri (prompt P059) ------------------------------------------------------------


def test_balanced_profile_has_no_findings(params):
    assert analyze(profile(), params) == []
    assert analyze(profile(z=-1.2), params) == []


def test_weakened_bench_produces_finding(params):
    findings = analyze(profile(z=1.0, bench=-1.0), params)
    residual = [f for f in findings if f.kind == KIND_RESIDUAL]
    assert len(residual) == 1, "soyma: tek zayıf kaldırış tek artık bulgusu üretmeli"
    f = residual[0]
    assert f.rule_id == "bench"
    assert f.weak_group == "bench"
    assert f.weak_exercise_ids == ("bench_press",)
    assert f.recommendation_key == "conditional_residual.bench.below_expected"
    assert f.severity == "severe"
    assert f.metrics["standardized_residual"] < -2.0
    assert f.muscles == ("chest", "triceps")


def test_low_confidence_is_silent(params):
    assert analyze(profile(z=1.0, bench=-1.0, confidence="low"), params) == []


def test_machine_scores_are_ignored(params):
    scores = [s if s.exercise_id != "bench_press" else ScoreInput(
        "chest_press_machine", -2.0, "high", "horizontal_push", is_machine=True,
        corr_key="bench") for s in profile(z=1.0)]
    assert analyze(scores, params) == []


# --- Koşullu beklenti matematiği ------------------------------------------------------------


def test_conditional_moments_match_closed_form():
    r = 0.6
    corr = np.array([[1.0, r], [r, 1.0]])
    mean, sd = conditional_moments(corr, 0, [1], [2.0])
    assert mean == pytest.approx(r * 2.0)
    assert sd == pytest.approx(np.sqrt(1 - r * r))


def test_conditional_moments_three_variables(params):
    # Simetrik matriste z_S = z_D = 1 için beklenen bench, matris tersiyle elle hesaplanır.
    c = params.correlation
    g = [0, 2]
    beta = np.linalg.inv(c[np.ix_(g, g)]) @ c[1, g]
    mean, sd = conditional_moments(c, 1, g, [1.0, 1.0])
    assert mean == pytest.approx(beta.sum())
    assert sd == pytest.approx(np.sqrt(1 - c[1, g] @ beta))


def test_residual_needs_min_variables(params):
    two = [s for s in profile(z=1.0, bench=-1.0) if s.corr_key != "deadlift"]
    assert not [f for f in analyze(two, params) if f.kind == KIND_RESIDUAL]


def test_strong_lift_above_expected(params):
    scores = profile(z=0.0, bench=2.5)
    residual = [f for f in analyze(scores, params) if f.kind == KIND_RESIDUAL]
    assert residual[0].recommendation_key == "conditional_residual.bench.above_expected"
    assert residual[0].strong_exercise_ids == ("bench_press",)
    assert residual[0].weak_group == "others"


def test_with_correlation_overrides_matrix(params):
    ident = params.with_correlation(params.variables, np.eye(3))
    # Bağımsız değişkenlerde beklenen 0, SD 1 → artık = z.
    findings = [f for f in analyze(profile(z=0.0, bench=-1.2), ident) if f.kind == KIND_RESIDUAL]
    assert findings[0].metrics["expected_z"] == pytest.approx(0.0)
    assert findings[0].metrics["residual_sd"] == pytest.approx(1.0)
    assert findings[0].severity == "mild"


# --- Kural tabanlı oranlar -----------------------------------------------------------------


def test_pull_behind_push(params):
    scores = [
        ScoreInput("bench_press", 1.5, "high", "horizontal_push"),
        ScoreInput("overhead_press", 1.5, "high", "vertical_push"),
        ScoreInput("barbell_row", -0.5, "medium", "horizontal_pull"),
    ]
    (f,) = [f for f in analyze(scores, params) if f.rule_id == "push_pull"]
    assert f.kind == KIND_RATIO
    assert f.weak_group == "pull" and f.strong_group == "push"
    assert f.recommendation_key == "ratio_rule.push_pull.pull_behind"
    assert f.weak_exercise_ids == ("barbell_row",)
    assert f.metrics["z_gap"] == pytest.approx(f.magnitude)
    assert f.magnitude >= 1.0


def test_squat_deadlift_and_upper_lower(params):
    scores = [
        ScoreInput("back_squat", -0.8, "high", "squat"),
        ScoreInput("deadlift", 1.0, "high", "hinge"),
        ScoreInput("bench_press", 2.5, "high", "horizontal_push"),
        ScoreInput("barbell_row", 2.5, "high", "horizontal_pull"),
    ]
    rules = {f.rule_id: f for f in analyze(scores, params)}
    assert rules["squat_deadlift"].weak_group == "squat"
    assert rules["upper_lower"].weak_group == "lower"
    assert "push_pull" not in rules


def test_ratio_rule_requires_both_groups(params):
    scores = [ScoreInput("bench_press", 2.5, "high", "horizontal_push")]
    assert analyze(scores, params) == []


# --- Sol / sağ -----------------------------------------------------------------------------


def test_left_right_asymmetry(params):
    pairs = [
        UnilateralInput("db_curl", 20.0, 16.0, "high", muscles=("biceps",)),  # %20
        UnilateralInput("split_squat", 60.0, 58.0, "high"),  # %3.3 → sessiz
        UnilateralInput("leg_ext", 50.0, 30.0, "high", is_machine=True),  # makine → sessiz
        UnilateralInput("lunge", 40.0, 30.0, "low"),  # düşük güven → sessiz
    ]
    findings = analyze([], params, unilateral=pairs)
    assert len(findings) == 1
    f = findings[0]
    assert f.kind == KIND_LEFT_RIGHT
    assert f.weak_group == "right"
    assert f.severity == "severe"
    assert f.magnitude == pytest.approx(0.2)
    assert f.recommendation_key == "left_right.right_behind"


# --- Çıktı ve deterministiklik -------------------------------------------------------------


def test_finding_dict_is_machine_readable_and_ordered(params):
    scores = profile(z=1.0, bench=-1.0)
    pairs = [UnilateralInput("db_curl", 20.0, 18.5, "medium")]
    a = [f.to_dict() for f in analyze(scores, params, pairs)]
    b = [f.to_dict() for f in analyze(list(reversed(scores)), params, pairs)]
    assert a == b
    json.dumps(a)  # yalnızca JSON uyumlu tipler
    keys = {
        "schema_version", "kind", "rule_id", "severity", "magnitude", "weak_group",
        "strong_group", "weak_exercise_ids", "strong_exercise_ids", "muscles",
        "recommendation_key", "metrics",
    }
    assert all(set(d) == keys for d in a)
    sev = ["severe", "moderate", "mild"]
    assert [sev.index(d["severity"]) for d in a] == sorted(sev.index(d["severity"]) for d in a)


def test_duplicate_corr_key_rejected(params):
    scores = profile() + [ScoreInput("paused_bench", 0.8, "high", "horizontal_push",
                                     corr_key="bench")]
    with pytest.raises(ValueError, match="duplicate"):
        analyze(scores, params)


# --- Parametre doğrulama -------------------------------------------------------------------


def test_every_param_block_documents_its_source(raw_params):
    assert "source" in raw_params["correlation"]
    assert "severity_sd_source" in raw_params["residual"]
    assert "min_variables_source" in raw_params["residual"]
    assert "confidence_weights_source" in raw_params["aggregation"]
    assert "unknown_pair_correlation_source" in raw_params["aggregation"]
    assert "source" in raw_params["gate"]
    assert "source" in raw_params["left_right"]
    assert all("source" in r for r in raw_params["ratio_rules"])
    ids = {r["id"] for r in raw_params["ratio_rules"]}
    assert ids == {"push_pull", "upper_lower", "squat_deadlift"}


@pytest.mark.parametrize(
    "mutate",
    [
        lambda d: d["correlation"]["matrix"].__setitem__(0, [1.0, 0.99, -0.99]),  # asimetrik
        lambda d: d["correlation"].__setitem__("matrix", [[1, 0.99, 0.99], [0.99, 1, -0.99],
                                                          [0.99, -0.99, 1]]),  # PD değil
        lambda d: d["residual"].__setitem__("severity_sd", {"mild": 2, "moderate": 1,
                                                            "severe": 3}),
        lambda d: d["gate"].__setitem__("allowed_confidence", ["medium", "high", "low"]),
        lambda d: d.__setitem__("schema_version", 2),
    ],
)
def test_invalid_params_rejected(raw_params, mutate):
    d = copy.deepcopy(raw_params)
    mutate(d)
    with pytest.raises(ValueError):
        ImbalanceParams.from_dict(d)
