"""P094 · quality gates. A candidate that fails any gate is not written as a bundle (§12.5).

1. golden      the Python reference with the *base* params reproduces `ml/golden/*.json` (tolerance 1e-4):
               the code that produces the new bundle is the code the Swift port was checked against.
2. calibration held-out anchor-lift scores in the gym population are PIT values; KS vs uniform must stay under
               `calibration_ks_max` and may not be worse than the base by more than `calibration_ks_margin`.
3. drift       median |new − old| score over held-out contributions ≤ `drift_median_max` points.
4. sanity      every candidate score finite and inside the clip, score monotone in load for every anchor
               and sex, κ inside its bounds, ratios inside `max_ratio_change` of the prior.
"""

from __future__ import annotations

import json
import math
import tempfile
from collections.abc import Callable, Mapping
from dataclasses import dataclass, field
from pathlib import Path

import numpy as np
import polars as pl

from gymml.export import golden
from gymml.retrain.calibration import contribution_age
from gymml.retrain.contributions import SEX_TO_MODEL
from gymml.scoring import AnchorModel, CurrentStrength, Exercise, Params, User, exercise_score


@dataclass
class Gate:
    name: str
    passed: bool
    detail: dict = field(default_factory=dict)


@dataclass(frozen=True)
class Candidate:
    params: Params
    catalog: Mapping[str, Exercise]
    model: AnchorModel


def _numbers_close(a, b, tol: float, path: str = "") -> str | None:
    """First mismatch path, or None."""
    if isinstance(a, dict) and isinstance(b, dict):
        if a.keys() != b.keys():
            return f"{path}: keys differ"
        for k in a:
            if (m := _numbers_close(a[k], b[k], tol, f"{path}.{k}")) is not None:
                return m
        return None
    if isinstance(a, list) and isinstance(b, list):
        if len(a) != len(b):
            return f"{path}: length {len(a)} != {len(b)}"
        for i, (x, y) in enumerate(zip(a, b, strict=True)):
            if (m := _numbers_close(x, y, tol, f"{path}[{i}]")) is not None:
                return m
        return None
    if isinstance(a, bool) or isinstance(b, bool) or not isinstance(a, int | float) or not isinstance(b, int | float):
        return None if a == b else f"{path}: {a!r} != {b!r}"
    return None if abs(float(a) - float(b)) <= tol else f"{path}: {a} != {b}"


def golden_gate(write: Callable[[Path], object], tol: float, ref_dir: Path = golden.GOLDEN_DIR) -> Gate:
    with tempfile.TemporaryDirectory() as tmp:
        out = Path(tmp)
        write(out)
        mismatches = {}
        for ref in sorted(ref_dir.glob("*.json")):
            got = out / ref.name
            if not got.exists():
                mismatches[ref.name] = "missing"
                continue
            m = _numbers_close(json.loads(got.read_text()), json.loads(ref.read_text()), tol)
            if m is not None:
                mismatches[ref.name] = m
    return Gate("golden", not mismatches, {"files": len(list(ref_dir.glob("*.json"))), "mismatches": mismatches})


def score_rows(rows: pl.DataFrame, c: Candidate, population: str = "gym") -> np.ndarray:
    """Reference `exercise_score` for each contribution row (NaN when the exercise is not scored)."""
    out = np.full(rows.height, np.nan)
    ages = contribution_age(rows["age_band"].to_numpy())
    for i, r in enumerate(rows.iter_rows(named=True)):
        ex = c.catalog.get(r["exercise_id"])
        if ex is None or not ex.scorable or ex.scoring_type == "reps_only":
            continue
        user = User(SEX_TO_MODEL[r["sex"]], float(ages[i]), float(r["bodyweight_kg"]))
        st = CurrentStrength(float(r["best_e1rm_kg"]), "high", False, int(r["sessions_in_month"]))
        s = exercise_score(ex, st, user, c.model, c.params, population=population)
        if s is not None:
            out[i] = s.score
    return out


def _ks_uniform(u: np.ndarray) -> float:
    u = np.sort(u[np.isfinite(u)])
    n = len(u)
    if n == 0:
        return float("nan")
    i = np.arange(1, n + 1)
    return float(max(np.max(i / n - u), np.max(u - (i - 1) / n)))


def calibration_gate(holdout: pl.DataFrame, base: Candidate, cand: Candidate, cfg: Mapping) -> Gate:
    anchors = [e.id for e in cand.catalog.values() if e.is_anchor]
    rows = holdout.filter(pl.col("exercise_id").is_in(anchors))
    ks_base = _ks_uniform(score_rows(rows, base) / 100)
    ks_new = _ks_uniform(score_rows(rows, cand) / 100)
    ok = (rows.height > 0 and math.isfinite(ks_new) and ks_new <= cfg["calibration_ks_max"]
          and ks_new <= ks_base + cfg["calibration_ks_margin"])
    return Gate("calibration", ok, {"rows": rows.height, "ks_base": ks_base, "ks_candidate": ks_new,
                                    "ks_max": cfg["calibration_ks_max"]})


def drift_gate(old: np.ndarray, new: np.ndarray, cfg: Mapping) -> Gate:
    m = np.isfinite(old) & np.isfinite(new)
    diff = np.abs(new[m] - old[m])
    med = float(np.median(diff)) if diff.size else float("nan")
    ok = diff.size > 0 and med <= cfg["drift_median_max"]
    return Gate("drift", ok, {"rows": int(diff.size), "median_abs_change": med,
                              "p90_abs_change": float(np.quantile(diff, 0.9)) if diff.size else None,
                              "max": cfg["drift_median_max"]})


def sanity_gate(new_scores: np.ndarray, cand: Candidate, kappa_bounds, ratio_problems: list[str],
                grid: int) -> Gate:
    problems: list[str] = list(ratio_problems)
    lo, hi = cand.params.scoring["exercise_score"]["score_clip"]
    finite = new_scores[~np.isnan(new_scores)]
    if not np.all(np.isfinite(finite)) or np.any(finite < lo) or np.any(finite > hi):
        problems.append("candidate scores outside the clip or not finite")
    for pop, sexes in cand.params.calibration["kappa"].items():
        for sex, k in sexes.items():
            if not kappa_bounds[0] <= k <= kappa_bounds[1]:
                problems.append(f"kappa {pop}/{sex} = {k}")
    for ex in (e for e in cand.catalog.values() if e.is_anchor):
        for sex in ("M", "F"):
            user = User(sex, 30.0, 80.0)
            loads = np.geomspace(10, 400, grid)
            s = []
            for w in loads:
                sc = exercise_score(ex, CurrentStrength(float(w), "high", False, 1), user, cand.model, cand.params,
                                    population="gym")
                s.append(sc.score if sc else np.nan)
            if np.any(np.diff(np.asarray(s)) < -1e-9):
                problems.append(f"{ex.id}/{sex}: score not monotone in load")
    return Gate("sanity", not problems, {"problems": problems})
