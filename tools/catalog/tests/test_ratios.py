"""P056: anchor ratios, load rules, consistency of implied loads and shrinkage of uncertain ratios."""
import copy
import json
import re
from pathlib import Path

import pytest

from catalog import ratios as rt
from catalog import taxonomy_build as tb

ROOT = Path(__file__).resolve().parent.parent
REPO = ROOT.parent.parent
BASE = json.loads((ROOT / "out" / "exercises.base.json").read_text(encoding="utf-8"))
EQUIPMENT = {e["id"]: e["equipment"] for e in BASE}
RATIOS = tb.load_ratios()
DOC = tb.build(BASE, tb.load_overrides(ROOT / "taxonomy_overrides.yaml"), None, RATIOS)
ROWS = {e["id"]: e for e in DOC["exercises"]}
CORE = [e for e in DOC["exercises"] if e["is_core"]]


def row(i):
    return ROWS[i]


def test_every_scored_core_exercise_has_a_sourced_ratio():
    scored = [e for e in CORE if e["scoring_type"] in ("weighted", "bodyweight_loaded")]
    assert len(scored) >= 130
    for e in scored:
        assert e["anchor"] in ("squat", "bench", "deadlift"), e["id"]
        assert e["ratio"] > 0 and e["tau"] > 0, e["id"]
        assert e["ratio_confidence"] in ("A", "B", "C"), e["id"]
        assert e["ratio_source"], e["id"]
        for key in e["ratio_source"].split("; "):
            assert key in RATIOS["sources"], (e["id"], key)
        if e["scoring_type"] == "bodyweight_loaded":
            assert 0 < e["bw_fraction"] <= 1.0, e["id"]


def test_every_source_has_a_citation_and_primary_sources_a_link():
    for key, src in RATIOS["sources"].items():
        assert src.get("cite"), key
        if key not in ("anchor", "expert"):
            assert src.get("url", "").startswith("https://"), key
            assert re.fullmatch(r"\d{4}-\d{2}-\d{2}", str(src.get("accessed"))), key


def test_non_core_exercises_do_not_score():
    for e in DOC["exercises"]:
        if not e["is_core"]:
            assert all(e[k] is None for k in ("anchor", "ratio", "tau")), e["id"]


def test_anchor_lifts_are_identity():
    for i, a in (("barbell-full-squat", "squat"), ("barbell-bench-press-medium-grip", "bench"),
                 ("barbell-deadlift", "deadlift")):
        assert (row(i)["anchor"], row(i)["ratio"], row(i)["ratio_confidence"]) == (a, 1.0, "A")
        assert row(i)["tau"] < RATIOS["tau"]["A"]


def test_tau_grows_with_uncertainty():
    t = RATIOS["tau"]
    assert t["anchor"] < t["A"] < t["B"] < t["C"] <= t["machine"]
    for e in CORE:
        if e["anchor"] is None or "anchor" in e["ratio_source"]:
            continue
        assert e["tau"] >= t[e["ratio_confidence"]] - 0.05, e["id"]


def test_machines_and_cables_are_capped_at_low_confidence():
    for e in CORE:
        if e["anchor"] is not None and tb.is_machine(EQUIPMENT[e["id"]], e["load_convention"]):
            assert e["ratio_confidence"] == "C", e["id"]
            assert e["tau"] >= RATIOS["tau"]["machine"], e["id"]


def test_validator_rejects_machine_with_high_confidence():
    bad = copy.deepcopy(DOC)
    r = next(e for e in bad["exercises"] if e["id"] == "leg-press")
    r["ratio_confidence"] = "A"
    assert any("capped at ratio_confidence C" in m for m in tb.validate(bad, BASE))


@pytest.mark.parametrize("eid,convention", [
    ("dumbbell-bench-press", "per_hand"),         # one dumbbell's weight
    ("hammer-curls", "per_hand"),
    ("one-arm-dumbbell-row", "per_hand"),
    ("leg-press", "per_side"),                    # plates on one side
    ("hack-squat", "per_side"),
    ("smith-machine-bench-press", "total"),       # Smith bar included
    ("smith-machine-squat", "total"),
    ("goblet-squat", "total"),                    # single implement
    ("bent-arm-dumbbell-pullover", "total"),      # one dumbbell, two hands
    ("standing-dumbbell-triceps-extension", "total"),
    ("wide-grip-lat-pulldown", "machine_stack"),
    ("pullups", "bodyweight_plus"),
    ("glute-ham-raise", "bodyweight_plus"),
])
def test_load_conventions(eid, convention):
    assert row(eid)["load_convention"] == convention


def test_dumbbell_ratio_is_per_hand():
    # A pair of dumbbells is ~0.83 × the barbell (Saeterbakken 2011): the logged single dumbbell is half of that.
    assert row("dumbbell-bench-press")["ratio"] == pytest.approx(0.83 / 2, abs=0.01)


def test_smith_note_mentions_bar_weight():
    assert "Smith bar" in row("smith-machine-bench-press")["ratio_note"]
    assert "Smith bar" in row("smith-machine-squat")["ratio_note"]


def test_bodyweight_fractions_follow_sources():
    assert row("pushups")["bw_fraction"] == pytest.approx(0.70, abs=0.06)      # Suprak/Ebben 0.64–0.75
    assert row("push-ups-with-feet-elevated")["bw_fraction"] > row("pushups")["bw_fraction"]
    assert row("pullups")["bw_fraction"] == 1.0
    assert row("dips-chest-version")["bw_fraction"] < 1.0                      # forearms and hands stay put


# ---------------------------------------------------------------- consistency (implied loads)

def test_implied_loads_are_consistent():
    assert rt.consistency_violations(DOC) == []


def test_curl_heavier_than_bench_is_caught():
    bad = copy.deepcopy(DOC)
    next(e for e in bad["exercises"] if e["id"] == "barbell-curl")["ratio"] = 1.2
    msgs = rt.consistency_violations(bad)
    assert any("barbell-curl" in m and "lighter than barbell-bench-press-medium-grip" in m for m in msgs)
    assert any("isolation barbell-curl" in m for m in msgs)


def test_absurd_bodyweight_ratio_is_caught():
    bad = copy.deepcopy(DOC)
    next(e for e in bad["exercises"] if e["id"] == "pullups")["ratio"] = 3.0
    assert any("pullups implies added load" in m for m in rt.consistency_violations(bad))


def test_order_rules_only_name_scored_exercises():
    scored = {e["id"] for e in rt.scored_rows(DOC)}
    for light, heavy in rt.ORDER_RULES:
        assert light in scored and heavy in scored


def test_implied_units_follow_load_convention():
    male = rt.PROFILES[0]
    db = rt.implied(row("dumbbell-bench-press"), male)
    assert db["total"] == pytest.approx(2 * db["logged"])
    pu = rt.implied(row("pullups"), male)
    assert pu["logged"] == pytest.approx(pu["total"] - male.bodyweight)


# ---------------------------------------------------------------- shrinkage: C cannot give extreme scores

def test_shrink_and_score_basics():
    assert rt.shrink(0.2, 0.0) == 1.0
    assert rt.score(0.0) == pytest.approx(50.0)
    assert rt.score(1.6448536) == pytest.approx(95.0, abs=1e-4)
    lo, hi = rt.score_range(0.4, 0.25, 3.0)
    assert lo == pytest.approx(100 - hi)


def test_grade_c_never_gives_extreme_scores():
    c = RATIOS["consistency"]
    assert rt.extreme_score_violations(DOC, c) == []
    lo_b, hi_b = c["score_bounds"]
    for e in rt.scored_rows(DOC):
        if e["ratio_confidence"] == "C":
            lo, hi = rt.score_range(e["tau"], c["s_max"], c["z_extreme"])
            assert lo_b <= lo and hi <= hi_b, e["id"]


def test_c_tau_floor_matches_bounds():
    c = RATIOS["consistency"]
    floor = rt.min_tau_for_bounds(c["s_max"], c["z_extreme"], c["score_bounds"][1])
    assert RATIOS["tau"]["C"] >= floor
    assert rt.score_range(floor, c["s_max"], c["z_extreme"])[1] == pytest.approx(c["score_bounds"][1], abs=1e-6)


def test_small_tau_on_grade_c_is_caught():
    bad = copy.deepcopy(DOC)
    next(e for e in bad["exercises"] if e["id"] == "barbell-curl")["tau"] = 0.15
    assert any(m.startswith("barbell-curl") for m in rt.extreme_score_violations(bad, RATIOS["consistency"]))


def test_s_max_covers_opl_spread():
    # Largest within-cell SD of log 1RM measured in OPL (ratios.yaml `opl` source) is 0.258.
    assert RATIOS["consistency"]["s_max"] >= 0.25


# ---------------------------------------------------------------- vocabulary alignment with the database

def _sql_enum(sql: str, constraint: str) -> set[str]:
    block = sql.split(f"add constraint {constraint}", 1)[1].split(";", 1)[0]
    block = block.split("check (", 1)[1].split("in (", 1)[1].split(")", 1)[0]
    return set(re.findall(r"'([a-z_]+)'", block))


def test_movement_patterns_match_the_database_constraint():
    """P025 deferred item: taxonomy pattern values must equal the movement_pattern CHECK (schema_4)."""
    sql = (REPO / "supabase/migrations/20261112140000_schema_4_catalog_vocabulary.sql").read_text(encoding="utf-8")
    schema = json.loads((ROOT / "scoring_taxonomy.schema.json").read_text(encoding="utf-8"))
    taxonomy_enum = set(schema["$defs"]["entry"]["properties"]["movement_pattern"]["enum"])
    assert _sql_enum(sql, "exercises_movement_pattern_check") == taxonomy_enum
    assert _sql_enum(sql, "custom_exercises_movement_pattern_check") == taxonomy_enum
