"""P060: golden vectors (`ml/golden/*.json`) for the Swift port (StrengthKit, tolerance 1e-4).

Every layer is computed by the Python reference (`gymml.scoring`, `gymml.progress`, `gymml.imbalance`)
with the anchor model read back from the exported `anchor_tables.json`, i.e. exactly what ships.
Days are integers (day numbers); Swift works on the same day numbers.
"""
# ruff: noqa: E501

from __future__ import annotations

import json
import math
from collections.abc import Mapping
from datetime import date, timedelta
from pathlib import Path
from typing import Any

import numpy as np

from gymml import imbalance, progress
from gymml.scoring import (
    AnchorModel,
    CurrentStrength,
    Exercise,
    LoggedSet,
    Params,
    User,
    calibrate_z,
    current_strength,
    exercise_score,
    muscle_group_scores,
    overall_score,
    score_set,
)

ML_ROOT = Path(__file__).resolve().parents[3]
GOLDEN_DIR = ML_ROOT / "golden"
DAY0 = date(2026, 1, 1)  # day number 0
SEED = 20260601
LIFTS = ("squat", "bench", "deadlift")
POPS = ("competitor", "gym", "general")


def _day(n: int) -> date:
    return DAY0 + timedelta(days=int(n))


def _f(x: float | None) -> float | None:
    return None if x is None else float(x)


def _user(u: User) -> dict:
    return {"sex": u.sex, "age": u.age, "bodyweightKg": u.bodyweight_kg}


ANCHOR_BASE_KG = {"squat": 110.0, "bench": 80.0, "deadlift": 140.0}  # rough gym medians, test inputs only


def _typical_e1rm(ex: Exercise, user: User, rng: np.random.Generator) -> float:
    """Spread e1RM around a plausible value so golden scores are not all clipped at 1 or 99."""
    if ex.anchor is None or ex.ratio is None:
        return float(rng.uniform(5, 60))
    return float(ex.ratio * ANCHOR_BASE_KG[ex.anchor] * math.exp(rng.normal(0, 0.5)))


def _rand_user(rng: np.random.Generator) -> User:
    sex = rng.choice(["M", "F", None], p=[0.45, 0.45, 0.10])
    return User(None if sex is None else str(sex), float(round(rng.uniform(14, 90), 1)),
                float(round(rng.uniform(40, 160), 1)))


# ------------------------------------------------------------------------------------------- e1rm


def e1rm_cases(p: Params, rng: np.random.Generator) -> list[dict]:
    patterns = [None, "squat", "hip_hinge", "horizontal_push", "vertical_pull", "isolation_biceps",
                "core", "lunge"]
    cases = []
    for i in range(160):
        pat = patterns[i % len(patterns)]
        reps = int(rng.integers(0, 36)) if i % 10 else int(rng.choice([1, 30, 31]))
        rir = None if rng.random() < 0.4 else float(rng.integers(0, 5))
        warm = bool(rng.random() < 0.1)
        w = float(round(rng.uniform(-5, 250), 1)) if i % 17 else 0.0
        ex = Exercise("x", pat, "weighted")
        s = score_set(ex, LoggedSet(DAY0, w, reps, rir, warm), User("M", 30, 80), p)
        cases.append({
            "input": {"pattern": pat, "weightKg": w, "reps": reps, "rir": rir, "isWarmup": warm},
            "expected": {"e1rmKg": s.e1rm_kg, "confidence": s.confidence},
        })
    return cases


# ------------------------------------------------------------------------------------------ anchor


def anchor_cases(model: AnchorModel, rng: np.random.Generator) -> list[dict]:
    edges = [(10.0, 25.0), (14.0, 30.0), (85.0, 250.0), (95.0, 300.0), (40.0, 80.0)]
    cases = []
    for i in range(300):
        lift = LIFTS[i % 3]
        sex = "M" if i % 2 else "F"
        if i < len(edges) * 3:
            age, bw = edges[i // 3]
        else:
            age, bw = float(rng.uniform(10, 95)), float(rng.uniform(25, 270))
        value = float(rng.uniform(5, 400)) if i % 23 else float(rng.choice([0.5, 1200.0]))
        z, s = model.z_and_scale(lift, sex, age, bw, value)
        cases.append({
            "input": {"lift": lift, "sex": sex, "age": age, "bodyweightKg": bw, "valueKg": value},
            "expected": {"z": z, "scale": s},
        })
    return cases


# ------------------------------------------------------------------------------------- calibration


def calibration_cases(p: Params, rng: np.random.Generator) -> list[dict]:
    cases = []
    for i in range(120):
        pop, sex, lift = POPS[i % 3], ("M", "F")[i % 2], LIFTS[(i // 2) % 3]
        age = float(rng.choice([14.0, 19.9, 20.0, 39.99, 40.0, 69.9, 70.0, 85.9, 95.0])) if i % 3 == 1 \
            else float(rng.uniform(14, 95))
        z_c, s_c = float(rng.normal()), float(rng.uniform(0.1, 0.3))
        z_g, s_g = calibrate_z(z_c, s_c, pop, sex, lift, age, p)
        cases.append({
            "input": {"zC": z_c, "sC": s_c, "population": pop, "sex": sex, "lift": lift, "age": age},
            "expected": {"zG": z_g, "sG": s_g},
        })
    return cases


# -------------------------------------------------------------------------------- current strength


def _rand_sets(rng: np.random.Generator, n: int, start: int, span: int, base: float) -> list[LoggedSet]:
    sets = []
    for _ in range(n):
        d = start + int(rng.integers(0, span + 1))
        w = float(round(base * rng.uniform(0.75, 1.3) / 2.5) * 2.5)
        sets.append(LoggedSet(_day(d), w, int(rng.integers(1, 16)),
                              None if rng.random() < 0.5 else float(rng.integers(0, 4)),
                              bool(rng.random() < 0.1), bool(rng.random() < 0.15)))
    return sets


def _set_json(s: LoggedSet) -> dict:
    return {"day": (s.day - DAY0).days, "weightKg": s.weight_kg, "reps": s.reps, "rir": s.rir,
            "isWarmup": s.is_warmup, "confirmed": s.confirmed}


def _strength_json(c: CurrentStrength) -> dict:
    return {"e1rmKg": _f(c.e1rm_kg), "confidence": c.confidence, "stale": c.stale,
            "sessionsInWindow": c.sessions_in_window,
            "flaggedDays": [(f.day - DAY0).days for f in c.flagged]}


def current_strength_cases(cat: Mapping[str, Exercise], p: Params, rng) -> list[dict]:
    ids = ["barbell-bench-press-medium-grip", "barbell-full-squat", "pullups", "dumbbell-bench-press",
           "barbell-curl", "leg-press"]
    cases = []
    for i in range(80):
        ex = cat[ids[i % len(ids)]]
        user = _rand_user(rng)
        as_of = 200
        n = int(rng.integers(0, 14))
        span = int(rng.choice([20, 60, 150]))
        sets = _rand_sets(rng, n, as_of - span - int(rng.integers(0, 120)), span, rng.uniform(20, 160))
        cs = current_strength(ex, sets, user, _day(as_of), p)
        cases.append({
            "input": {"exerciseId": ex.id, "user": _user(user), "asOfDay": as_of,
                      "sets": [_set_json(s) for s in sets]},
            "expected": _strength_json(cs),
        })
    return cases


# ---------------------------------------------------------------------------------- exercise score


def _score_json(s) -> dict | None:
    if s is None:
        return None
    return {"score": s.score, "z": s.z, "bandLow": s.band[0], "bandHigh": s.band[1],
            "confidence": s.confidence, "level": s.level, "isMachine": s.is_machine,
            "anchor": s.anchor, "stale": s.stale}


def exercise_score_cases(cat, model: AnchorModel, p: Params, rng) -> list[dict]:
    weighted = sorted(i for i, e in cat.items() if e.scorable and e.scoring_type != "reps_only")
    reps_only = ["pushups", "crunches", "3-4-sit-up"]
    cases = []
    for i in range(300):
        rid = None
        if i % 10 == 9:
            ex = cat[reps_only[i % len(reps_only)]]
            rid = float(rng.integers(0, 70))
        else:
            ex = cat[weighted[int(rng.integers(0, len(weighted)))]]
        user = _rand_user(rng)
        e1rm = _typical_e1rm(ex, user, rng)
        st = CurrentStrength(e1rm, str(rng.choice(["low", "medium", "high"])), bool(rng.random() < 0.1), 3)
        pop = str(rng.choice(POPS))
        sc = exercise_score(ex, st, user, model, p, population=pop, reps=rid)
        cases.append({
            "input": {"exerciseId": ex.id, "user": _user(user),
                      "strength": {"e1rmKg": e1rm, "confidence": st.confidence, "stale": st.stale},
                      "population": pop, "reps": rid},
            "expected": _score_json(sc),
        })
    return cases


# --------------------------------------------------------------------------------------- aggregate


def _group_json(g) -> dict | None:
    if g is None:
        return None
    return {"score": g.score, "z": g.z, "n": g.n, "confidence": g.confidence,
            "provisional": g.provisional, "level": g.level, "patterns": list(g.patterns)}


def aggregate_cases(cat, p: Params, rng) -> list[dict]:
    from gymml.scoring import ExerciseScore

    ids = sorted(i for i, e in cat.items() if e.scorable)
    cases = []
    for _ in range(60):
        k = int(rng.integers(1, 12))
        chosen = list(rng.choice(ids, size=k, replace=False))
        items = []
        for eid in chosen:
            ex = cat[str(eid)]
            z = float(rng.normal(0, 1.2))
            items.append(ExerciseScore(
                ex.id, 0.0, z, (0.0, 0.0), str(rng.choice(["low", "medium", "high"])), "", "gym",
                bool(rng.random() < 0.2), ex.anchor, bool(rng.random() < 0.15)))
        groups = muscle_group_scores(items, cat, p)
        overall = overall_score(items, cat, p)
        cases.append({
            "input": {"scores": [{"exerciseId": s.exercise_id, "z": s.z, "confidence": s.confidence,
                                  "isMachine": s.is_machine, "anchor": s.anchor, "stale": s.stale}
                                 for s in items]},
            "expected": {"muscles": {k: _group_json(v) for k, v in groups.items()},
                         "overall": _group_json(overall)},
        })
    return cases


# ---------------------------------------------------------------------------------------- progress


def _dc(obj: Any) -> Any:
    """Dataclass/enum -> camelCase JSON."""
    from dataclasses import fields, is_dataclass
    from enum import Enum

    from gymml.export.params import camel

    if is_dataclass(obj):
        return {camel(f.name): _dc(getattr(obj, f.name)) for f in fields(obj)}
    if isinstance(obj, Enum):
        return obj.value
    if isinstance(obj, tuple | list):
        return [_dc(x) for x in obj]
    if isinstance(obj, float) and not math.isfinite(obj):
        raise ValueError("non-finite value in golden vector")
    return obj


def progress_cases(pp: progress.ProgressParams, rng) -> list[dict]:
    cases = []
    for i in range(80):
        n = int(rng.integers(0, 40))
        monthly = float(rng.choice([0.0, 0.01, 0.03, -0.01]))
        noise = float(rng.choice([0.005, 0.02]))
        t = 0.0
        sessions = []
        for _ in range(n):
            t += float(rng.choice([2, 3, 4, 7]))
            w = 100 * math.exp(monthly / 30.4375 * t + rng.normal(0, noise))
            sessions.append((t, w if rng.random() > 0.03 else -1.0))
        pct = float(rng.uniform(0, 100))
        years = None if i % 3 == 0 else float(rng.uniform(0, 8))
        rep = progress.analyze(sessions, pct, pp, years)
        cases.append({"input": {"sessions": [list(s) for s in sessions], "percentile": pct,
                                "trainingYears": years},
                      "expected": _dc(rep)})
    return cases


# --------------------------------------------------------------------------------------- imbalance


def imbalance_cases(ip: imbalance.ImbalanceParams, rng) -> list[dict]:
    pats = list(imbalance.PATTERNS)
    cases = []
    for _ in range(80):
        scores = []
        for key in ("squat", "bench", "deadlift"):
            if rng.random() < 0.8:
                pat = {"squat": "squat", "bench": "horizontal_push", "deadlift": "hinge"}[key]
                scores.append(imbalance.ScoreInput(f"anchor-{key}", float(rng.normal(0, 1.3)),
                                                   str(rng.choice(["low", "medium", "high"])), pat,
                                                   False, key, (f"m-{key}",)))
        for j in range(int(rng.integers(0, 6))):
            scores.append(imbalance.ScoreInput(
                f"ex-{j}", float(rng.normal(0, 1.3)), str(rng.choice(["low", "medium", "high"])),
                str(rng.choice(pats)), bool(rng.random() < 0.2), None, (f"m{j}", "shared")))
        uni = [imbalance.UnilateralInput(f"uni-{j}", float(rng.uniform(20, 60)), float(rng.uniform(20, 60)),
                                         str(rng.choice(["low", "medium", "high"])), bool(rng.random() < 0.2),
                                         (f"u{j}",))
               for j in range(int(rng.integers(0, 3)))]
        found = imbalance.analyze(scores, ip, uni)

        def si(s: imbalance.ScoreInput) -> dict:
            return {"exerciseId": s.exercise_id, "z": s.z, "confidence": s.confidence, "pattern": s.pattern,
                    "isMachine": s.is_machine, "corrKey": s.corr_key, "muscles": list(s.muscles)}

        def ui(u: imbalance.UnilateralInput) -> dict:
            return {"exerciseId": u.exercise_id, "leftKg": u.left_kg, "rightKg": u.right_kg,
                    "confidence": u.confidence, "isMachine": u.is_machine, "muscles": list(u.muscles)}

        cases.append({
            "input": {"scores": [si(s) for s in scores], "unilateral": [ui(u) for u in uni]},
            "expected": [_finding(f) for f in found],
        })
    return cases


def _finding(f: imbalance.Finding) -> dict:
    d = f.to_dict()
    d.pop("schema_version")
    from gymml.export.params import camel

    return {camel(k): v for k, v in d.items()}


# -------------------------------------------------------------------------------------- end to end


def end_to_end_cases(cat, model: AnchorModel, p: Params, rng) -> list[dict]:
    ids = ["barbell-full-squat", "barbell-bench-press-medium-grip", "barbell-deadlift",
           "standing-military-press", "bent-over-barbell-row", "pullups", "dumbbell-bench-press",
           "barbell-curl", "leg-press", "pushups", "dumbbell-shoulder-press", "lying-leg-curls"]
    ids = [i for i in ids if i in cat]
    cases = []
    for _ in range(40):
        user = _rand_user(rng)
        as_of = 300
        pop = str(rng.choice(POPS))
        chosen = list(rng.choice(ids, size=int(rng.integers(1, len(ids) + 1)), replace=False))
        exercises, scores = [], []
        for eid in chosen:
            ex = cat[str(eid)]
            base = _typical_e1rm(ex, user, rng) * 0.8
            if ex.scoring_type == "bodyweight_loaded" and ex.bw_fraction is not None:
                base = max(2.5, base - ex.bw_fraction * user.bodyweight_kg)
            sets = _rand_sets(rng, int(rng.integers(1, 10)), as_of - int(rng.choice([30, 90])), 28, base)
            if ex.scoring_type == "reps_only":
                reps = float(max(s.reps for s in sets))
                st = CurrentStrength(None, "low", False, 0)
            else:
                reps = None
                st = current_strength(ex, sets, user, _day(as_of), p)
            sc = exercise_score(ex, st, user, model, p, population=pop, reps=reps)
            exercises.append({"exerciseId": ex.id, "sets": [_set_json(s) for s in sets],
                              "expected": _score_json(sc)})
            if sc is not None:
                scores.append(sc)
        groups = muscle_group_scores(scores, cat, p)
        cases.append({
            "input": {"user": _user(user), "asOfDay": as_of, "population": pop,
                      "exercises": [{k: v for k, v in e.items() if k != "expected"} for e in exercises]},
            "expected": {"exercises": {e["exerciseId"]: e["expected"] for e in exercises},
                         "muscles": {k: _group_json(v) for k, v in groups.items()},
                         "overall": _group_json(overall_score(scores, cat, p))},
        })
    return cases


# ------------------------------------------------------------------------------------------- write


def write_all(cat, model: AnchorModel, p: Params, pp, ip, out: Path = GOLDEN_DIR) -> dict[str, int]:
    rng = np.random.default_rng(SEED)
    layers = {
        "e1rm": e1rm_cases(p, rng),
        "anchor": anchor_cases(model, rng),
        "calibration": calibration_cases(p, rng),
        "current_strength": current_strength_cases(cat, p, rng),
        "exercise_score": exercise_score_cases(cat, model, p, rng),
        "aggregate": aggregate_cases(cat, p, rng),
        "progress": progress_cases(pp, rng),
        "imbalance": imbalance_cases(ip, rng),
        "end_to_end": end_to_end_cases(cat, model, p, rng),
    }
    out.mkdir(parents=True, exist_ok=True)
    for name, cases in layers.items():
        doc = {"layer": name, "tolerance": 1e-4, "dayZero": DAY0.isoformat(), "cases": cases}
        (out / f"{name}.json").write_text(json.dumps(doc, allow_nan=False, separators=(",", ":")) + "\n")
    return {k: len(v) for k, v in layers.items()}
