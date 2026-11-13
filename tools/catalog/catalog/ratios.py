"""Sanity checks for the anchor ratios in ratios.yaml / scoring_taxonomy.yaml (P056, docs/03-ML-MODEL.md §6).

Two checks the score engine relies on:
- implied loads: for an illustrative "average" gym-goer, every ratio implies a load in the exercise's own unit
  (load_convention). Obvious nonsense (a curl heavier than the bench press) is caught by ordering rules.
- shrinkage: z_e = z_anchor · s / sqrt(s² + τ²). A grade C ratio must never produce an extreme score, i.e. even
  |z_anchor| = z_extreme stays inside score_bounds for the largest anchor spread s_max we expect.
"""
from __future__ import annotations

import math
from dataclasses import dataclass
from typing import Any


@dataclass(frozen=True)
class Profile:
    """Illustrative average gym-goer (anchor 1RMs in kg). Not a norm: only used to eyeball implied loads."""
    label: str
    bodyweight: float
    squat: float
    bench: float
    deadlift: float

    def anchor(self, name: str) -> float:
        return {"squat": self.squat, "bench": self.bench, "deadlift": self.deadlift}[name]


# Ratios between the anchors follow the OpenPowerlifting medians (ratios.yaml `opl`): bench/squat ≈ 0.67 M / 0.56 F,
# deadlift/squat ≈ 1.18 M / 1.23 F. Absolute numbers are a plausible "a year or two of training" level.
PROFILES = (
    Profile("erkek, 80 kg", 80.0, 125.0, 90.0, 150.0),
    Profile("kadın, 62 kg", 62.0, 80.0, 45.0, 100.0),
)

# (lighter, heavier): the implied total-equivalent load of the first must be below the second for every profile.
ORDER_RULES: tuple[tuple[str, str], ...] = (
    ("barbell-curl", "barbell-bench-press-medium-grip"),
    ("barbell-curl", "close-grip-barbell-bench-press"),
    ("ez-bar-curl", "standing-military-press"),
    ("dumbbell-bicep-curl", "barbell-curl"),
    ("hammer-curls", "dumbbell-bench-press"),
    ("side-lateral-raise", "dumbbell-shoulder-press"),
    ("front-two-dumbbell-raise", "dumbbell-shoulder-press"),
    ("standing-military-press", "barbell-incline-bench-press-medium-grip"),
    ("barbell-incline-bench-press-medium-grip", "barbell-bench-press-medium-grip"),
    ("incline-dumbbell-press", "dumbbell-bench-press"),
    ("dumbbell-bench-press", "barbell-bench-press-medium-grip"),
    ("standing-military-press", "push-press"),
    ("triceps-pushdown", "close-grip-barbell-bench-press"),
    ("standing-overhead-barbell-triceps-extension", "close-grip-barbell-bench-press"),
    ("front-barbell-squat", "barbell-full-squat"),
    ("goblet-squat", "front-barbell-squat"),
    ("barbell-lunge", "barbell-full-squat"),
    ("leg-extensions", "barbell-full-squat"),
    ("lying-leg-curls", "leg-extensions"),
    ("romanian-deadlift", "barbell-deadlift"),
    ("stiff-legged-barbell-deadlift", "romanian-deadlift"),
    ("good-morning", "romanian-deadlift"),
    ("barbell-deadlift", "trap-bar-deadlift"),
    ("barbell-deadlift", "rack-pulls"),
    ("barbell-full-squat", "barbell-deadlift"),
    ("bent-over-two-dumbbell-row", "bent-over-barbell-row"),
    ("bent-over-barbell-row", "barbell-deadlift"),
    ("upright-barbell-row", "bent-over-barbell-row"),
    ("snatch", "power-clean"),
    ("hang-clean", "power-clean"),
    ("power-clean", "front-barbell-squat"),
    ("clean-and-jerk", "front-barbell-squat"),
    ("farmers-walk", "barbell-deadlift"),
    ("dumbbell-shrug", "barbell-shrug"),
)

# Upper-body isolation patterns: total-equivalent load at most this share of the bench press.
ISOLATION_UPPER = ("isolation_biceps", "isolation_triceps", "isolation_shoulders", "isolation_chest",
                   "isolation_forearms")
ISOLATION_UPPER_MAX = 0.75
# Bodyweight-loaded rows: implied added load (negative = assistance) within these multiples of body weight.
ADDED_LOAD_RANGE = (-0.5, 1.0)


def scored_rows(doc: dict[str, Any]) -> list[dict[str, Any]]:
    return [e for e in doc["exercises"] if e["is_core"] and e["anchor"] is not None]


def implied(e: dict[str, Any], p: Profile) -> dict[str, float]:
    """Implied 1RM for profile p: `logged` in the unit the user types, `total` as a both-sides load
    (per_hand / per_side doubled, bodyweight_plus = effective load) for cross-exercise ordering."""
    one_rm = e["ratio"] * p.anchor(e["anchor"])
    lc = e["load_convention"]
    if lc == "bodyweight_plus":
        return {"logged": one_rm - e["bw_fraction"] * p.bodyweight, "total": one_rm}
    if lc in ("per_hand", "per_side"):
        return {"logged": one_rm, "total": 2 * one_rm}
    return {"logged": one_rm, "total": one_rm}


def implied_table(doc: dict[str, Any], profiles: tuple[Profile, ...] = PROFILES) -> dict[str, list[dict[str, float]]]:
    return {e["id"]: [implied(e, p) for p in profiles] for e in scored_rows(doc)}


def consistency_violations(doc: dict[str, Any], profiles: tuple[Profile, ...] = PROFILES) -> list[str]:
    rows = {e["id"]: e for e in scored_rows(doc)}
    out: list[str] = []
    for p in profiles:
        load = {i: implied(e, p) for i, e in rows.items()}
        for light, heavy in ORDER_RULES:
            missing = [i for i in (light, heavy) if i not in load]
            if missing:
                out.append(f"order rule refers to unscored exercise(s) {missing}")
                continue
            if not load[light]["total"] < load[heavy]["total"]:
                out.append(f"{p.label}: {light} ({load[light]['total']:.1f} kg) should be lighter than "
                           f"{heavy} ({load[heavy]['total']:.1f} kg)")
        for i, e in rows.items():
            if load[i]["total"] <= 0:
                out.append(f"{p.label}: {i} implies a non-positive load")
            if e["movement_pattern"] in ISOLATION_UPPER and load[i]["total"] > ISOLATION_UPPER_MAX * p.bench:
                out.append(f"{p.label}: isolation {i} implies {load[i]['total']:.1f} kg, "
                           f"more than {ISOLATION_UPPER_MAX:.0%} of the bench press")
            if e["load_convention"] == "bodyweight_plus":
                lo, hi = (k * p.bodyweight for k in ADDED_LOAD_RANGE)
                if not lo <= load[i]["logged"] <= hi:
                    out.append(f"{p.label}: {i} implies added load {load[i]['logged']:.1f} kg outside "
                               f"[{lo:.0f}, {hi:.0f}]")
    return out


def shrink(s: float, tau: float) -> float:
    """Factor multiplying the anchor z-score (§6)."""
    return s / math.sqrt(s * s + tau * tau)


def score(z: float) -> float:
    """Percentile score of a standard-normal z (0–100, unclipped)."""
    return 50.0 * (1.0 + math.erf(z / math.sqrt(2.0)))


def score_range(tau: float, s: float, z: float) -> tuple[float, float]:
    zz = z * shrink(s, tau)
    return score(-zz), score(zz)


def min_tau_for_bounds(s: float, z: float, upper: float) -> float:
    """Smallest tau that keeps score(z · shrink) ≤ upper."""
    z_cap = _inverse_score(upper)
    if z_cap >= z:
        return 0.0
    return s * math.sqrt((z / z_cap) ** 2 - 1.0)


def _inverse_score(pct: float) -> float:
    lo, hi = -10.0, 10.0
    for _ in range(200):
        mid = (lo + hi) / 2
        if score(mid) < pct:
            lo = mid
        else:
            hi = mid
    return (lo + hi) / 2


def extreme_score_violations(doc: dict[str, Any], consistency: dict[str, Any]) -> list[str]:
    s, z = float(consistency["s_max"]), float(consistency["z_extreme"])
    lo_b, hi_b = consistency["score_bounds"]
    out = []
    for e in scored_rows(doc):
        if e["ratio_confidence"] != "C":
            continue
        lo, hi = score_range(e["tau"], s, z)
        if lo < lo_b or hi > hi_b:
            out.append(f"{e['id']}: grade C with tau {e['tau']} reaches scores {lo:.1f}–{hi:.1f} "
                       f"(allowed {lo_b}–{hi_b})")
    return out
