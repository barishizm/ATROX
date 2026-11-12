import copy
import json
from pathlib import Path

import pytest
import yaml

from catalog import taxonomy, taxonomy_build as tb, taxonomy_cli

ROOT = Path(__file__).resolve().parent.parent
BASE = json.loads((ROOT / "out" / "exercises.base.json").read_text(encoding="utf-8"))
OVERRIDES = tb.load_overrides(ROOT / "taxonomy_overrides.yaml")


def ex(name, equipment="barbell", category="strength", mechanic="compound", muscle="chest"):
    return {"id": name.lower().replace(" ", "-"), "name": name, "equipment": equipment, "category": category,
            "mechanic": mechanic, "primary_muscles": [muscle] if muscle else []}


@pytest.mark.parametrize("name,equipment,muscle,pattern,scoring,load", [
    ("Barbell Bench Press", "barbell", "chest", "horizontal_push", "weighted", "total"),
    ("Seated Dumbbell Press", "dumbbell", "shoulders", "vertical_push", "weighted", "per_hand"),
    ("Barbell Full Squat", "barbell", "quadriceps", "squat", "weighted", "total"),
    ("Romanian Deadlift", "barbell", "hamstrings", "hip_hinge", "weighted", "total"),
    ("Bent Over Barbell Row", "barbell", "middle_back", "horizontal_pull", "weighted", "total"),
    ("Wide-Grip Lat Pulldown", "cable", "lats", "vertical_pull", "weighted", "machine_stack"),
    ("Pullups", "body_only", "lats", "vertical_pull", "bodyweight_loaded", "bodyweight_plus"),
    ("Pushups", "body_only", "chest", "horizontal_push", "reps_only", None),
    ("Crunches", "body_only", "abdominals", "core", "reps_only", None),
    ("Plank", "body_only", "abdominals", "core", "time", None),
    ("Leg Extensions", "machine", "quadriceps", "isolation_quads", "weighted", "machine_stack"),
    ("Hammer Curls", "dumbbell", "biceps", "isolation_biceps", "weighted", "per_hand"),
    ("Upright Barbell Row", "barbell", "shoulders", "vertical_pull", "weighted", "total"),
])
def test_classify_known_lifts(name, equipment, muscle, pattern, scoring, load):
    t = taxonomy.classify(ex(name, equipment, muscle=muscle))
    assert (t["movement_pattern"], t["scoring_type"], t["load_convention"]) == (pattern, scoring, load)


def test_cardio_stretch_plyo_are_unscored():
    for cat, pat in (("cardio", "cardio"), ("stretching", "mobility"), ("plyometrics", "plyometric")):
        t = taxonomy.classify(ex("Whatever Move", "body_only", category=cat))
        assert (t["movement_pattern"], t["scoring_type"], t["load_convention"]) == (pat, "none", None)


def test_clean_grip_front_squat_is_not_olympic():
    assert taxonomy.classify(ex("Front Squat (Clean Grip)", muscle="quadriceps"))["movement_pattern"] == "squat"


def test_unilateral_detection():
    assert taxonomy.classify(ex("Dumbbell Lunges", "dumbbell", muscle="quadriceps"))["is_unilateral"]
    assert taxonomy.classify(ex("One-Arm Dumbbell Row", "dumbbell", muscle="middle_back"))["is_unilateral"]
    assert not taxonomy.classify(ex("Barbell Curl", muscle="biceps"))["is_unilateral"]


def test_unknown_names_fall_back_but_are_flagged():
    t = taxonomy.classify(ex("Zork Machine Thing", "machine", muscle="chest"))
    assert t["rule"].startswith("fallback") and t["needs_review"] and t["review_notes"]


def test_no_guess_is_silent():
    for e in BASE:
        t = taxonomy.classify(e)
        if t["rule"].startswith("fallback") or "guessed" in " ".join(t["review_notes"]):
            assert t["needs_review"], e["id"]


def test_every_catalog_exercise_has_pattern_and_scoring_type():
    doc = tb.build(BASE, OVERRIDES)
    assert len(doc["exercises"]) == len(BASE)
    for e in doc["exercises"]:
        assert e["movement_pattern"] in taxonomy.MOVEMENT_PATTERNS
        assert e["scoring_type"] in taxonomy.SCORING_TYPES


def test_real_taxonomy_is_valid_and_core_is_about_150():
    doc = tb.build(BASE, OVERRIDES)
    assert tb.validate(doc, BASE) == []
    assert 140 <= sum(e["is_core"] for e in doc["exercises"]) <= 170


def test_p056_fields_are_null():
    for e in tb.build(BASE, OVERRIDES)["exercises"]:
        assert all(e[k] is None for k in ("anchor", "ratio", "tau", "ratio_confidence", "bw_fraction"))


def test_committed_yaml_is_up_to_date():
    doc = tb.build(BASE, OVERRIDES, __import__("hashlib").sha256(
        (ROOT / "out" / "exercises.base.json").read_bytes()).hexdigest())
    assert (ROOT / "scoring_taxonomy.yaml").read_text(encoding="utf-8") == tb.render(doc)
    assert yaml.safe_load(tb.render(doc)) == doc


def test_validator_rejects_bad_enum_missing_and_inconsistent_entries():
    doc = tb.build(BASE, OVERRIDES)
    bad = copy.deepcopy(doc)
    bad["exercises"][0]["movement_pattern"] = "nonsense"
    assert any("movement_pattern" in m for m in tb.validate(bad, BASE))
    short = copy.deepcopy(doc)
    short["exercises"].pop()
    assert any("no taxonomy entry" in m for m in tb.validate(short, BASE))
    inc = copy.deepcopy(doc)
    row = next(e for e in inc["exercises"] if e["scoring_type"] == "reps_only")
    row["load_convention"] = "total"
    assert any("load_convention null" in m for m in tb.validate(inc, BASE))
    core_none = copy.deepcopy(doc)
    row = next(e for e in core_none["exercises"] if e["is_core"])
    row["scoring_type"], row["load_convention"] = "none", None
    assert any("core exercise" in m for m in tb.validate(core_none, BASE))
    ratio = copy.deepcopy(doc)
    ratio["exercises"][0]["ratio"] = -1
    assert tb.validate(ratio, BASE)


def test_validator_flags_wrong_core_size():
    doc = tb.build(BASE, {"core": OVERRIDES["core"][:10], "overrides": {}})
    assert any("core set has" in m for m in tb.validate(doc, BASE))


def test_overrides_win_and_reject_unknowns():
    first = BASE[0]["id"]
    doc = tb.build(BASE, {"core": OVERRIDES["core"], "overrides": {first: {"movement_pattern": "other", "note": "x"}}})
    row = next(e for e in doc["exercises"] if e["id"] == first)
    assert row["movement_pattern"] == "other" and row["assignment"] == "manual" and not row["needs_review"]
    with pytest.raises(ValueError, match="unknown ids"):
        tb.build(BASE, {"core": ["no-such-id"], "overrides": {}})
    with pytest.raises(ValueError, match="unknown override fields"):
        tb.build(BASE, {"core": OVERRIDES["core"], "overrides": {first: {"bogus": 1}}})


def test_core_doc_lists_every_core_row():
    doc = tb.build(BASE, OVERRIDES)
    text = taxonomy_cli.render_doc(doc)
    for e in doc["exercises"]:
        if e["is_core"]:
            assert f"| {e['name']} |" in text
