"""P094 · synthetic `ml_contributions` drawn from a known truth, for the end-to-end test and `make retrain-synthetic`.

Each contributor gets a correlated gym z per anchor lift (P057 anchor correlation), turned into an anchor e1RM
through the inverse of §5.1 with the *true* δ, κ (prior + shift); every other lift is anchor e1RM × true ρ ×
exp(N(0, true τ)). Contributors log 5–15 lifts for 1–3 months, like the app's monthly summary.
"""

from __future__ import annotations

import uuid
from collections.abc import Mapping
from dataclasses import dataclass, field

import numpy as np
import polars as pl
from scipy.stats import norm

from gymml.calibration.reference import age_band_of
from gymml.models import boxcox
from gymml.retrain.calibration import contribution_age
from gymml.retrain.contributions import frame
from gymml.scoring import LIFTS, AnchorModel, Exercise, Params, is_machine

COMMON = ("standing-military-press", "bent-over-barbell-row", "pullups", "dumbbell-bench-press", "barbell-curl",
          "leg-press", "dumbbell-shoulder-press", "lying-leg-curls", "incline-dumbbell-press", "romanian-deadlift",
          "lat-pulldown", "seated-cable-rows", "barbell-hip-thrust", "front-barbell-squat", "dips-triceps-version")
EXPERIENCE = ("none", "under_6_months", "six_months_to_2_years", "two_to_5_years", "over_5_years")
FREQUENCY = ("1-2", "3-4", "5-6", "7+")


@dataclass(frozen=True)
class Truth:
    delta_shift: float = 0.0          # added to every gym δ cell
    kappa_factor: float = 1.0         # multiplies gym κ
    ratio_factor: Mapping[str, float] = field(default_factory=dict)   # exercise id → true ρ / prior ρ
    tau: float = 0.12                 # true between-person SD of every log ratio
    e1rm_factor: float = 1.0          # corrupts every e1RM (broken-data test)


def _anchor_value(model: AnchorModel, lift: str, sex: np.ndarray, age: np.ndarray, bw: np.ndarray,
                  z_c: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    x = pl.DataFrame({"sex": sex, "age": age, "bodyweight_kg": bw})
    m = model.models[lift]
    q = np.log(m.quantile(x, model.scale_q))
    s_c = (q[:, 1] - q[:, 0]) / 2
    pr = m.params(x)
    return s_c, pr


def generate(n: int, catalog: Mapping[str, Exercise], model: AnchorModel, p: Params, truth: Truth,
             seed: int = 7) -> pl.DataFrame:
    rng = np.random.default_rng(seed)
    anchors = {e.anchor: e.id for e in catalog.values() if e.is_anchor}
    pool = [i for i in COMMON if i in catalog and catalog[i].scorable and catalog[i].anchor in anchors]
    extra = sorted(e.id for e in catalog.values() if e.scorable and e.scoring_type != "reps_only"
                   and not e.is_anchor and e.anchor in anchors and e.id not in pool and not is_machine(e, p))
    sexes = rng.choice(["male", "female"], n)
    msex = np.where(sexes == "male", "M", "F")
    age_band = (rng.integers(18, 66, n) // 5) * 5
    ages = contribution_age(age_band)
    bw = np.where(msex == "M", rng.lognormal(np.log(82), 0.15, n), rng.lognormal(np.log(65), 0.15, n))
    bw = np.clip(np.round(bw), 40, 200)
    z_g = rng.multivariate_normal(np.zeros(3), p.correlation, n)
    cal = p.calibration
    min_age = float(p.scoring["exercise_score"]["calibration_min_age_band"].split("-")[0])
    bands = [age_band_of(min(max(a, min_age), 85.0)) for a in ages]

    anchor_e1rm = {}
    for j, lift in enumerate(LIFTS):
        s_c, pr = _anchor_value(model, lift, msex, ages, bw, z_g[:, j])
        delta = np.array([cal["delta"]["gym"][s][lift][b] for s, b in zip(msex, bands, strict=True)]) + truth.delta_shift
        kappa = np.array([cal["kappa"]["gym"][s] for s in msex]) * truth.kappa_factor
        z_c = kappa * z_g[:, j] - delta / s_c
        f = np.clip(norm.cdf(z_c), *model.clip)
        anchor_e1rm[lift] = boxcox.ppf(f, pr["mu"], pr["sigma"], pr["nu"], pr["tau"], family=model.models[lift].family)

    rows = []
    for i in range(n):
        key = str(uuid.UUID(int=int(rng.integers(0, 2**63)) << 64 | int(rng.integers(0, 2**63)), version=4))
        lifts = [anchors[lift] for lift in LIFTS if rng.random() < 0.75]
        k = int(rng.integers(5, 16)) - len(lifts)
        common = list(rng.choice(pool, size=min(k, len(pool)), replace=False))
        k -= len(common)
        if k > 0:
            common += list(rng.choice(extra, size=k, replace=False))
        person_dev = {eid: rng.normal(0, truth.tau) for eid in common}
        months = int(rng.integers(1, 4))
        for mi in range(months):
            progress = 1.01**mi
            for eid in lifts + common:
                ex = catalog[eid]
                base = float(anchor_e1rm[ex.anchor][i])
                if ex.is_anchor:
                    value = base
                else:
                    value = base * ex.ratio * truth.ratio_factor.get(eid, 1.0) * float(np.exp(person_dev[eid]))
                value = float(np.clip(round(value * progress * truth.e1rm_factor, 1), 1.0, 700.0))
                rows.append({
                    "contribution_key": key, "sex": str(sexes[i]), "age_band": int(age_band[i]),
                    "bodyweight_kg": int(bw[i]), "height_band": int(rng.choice([160, 165, 170, 175, 180, 185])),
                    "experience_band": str(rng.choice(EXPERIENCE)), "frequency_band": str(rng.choice(FREQUENCY)),
                    "month": f"2026-{mi + 7:02d}", "exercise_id": eid, "best_e1rm_kg": value,
                    "best_set_reps": int(rng.integers(1, 13)), "sessions_in_month": int(rng.integers(1, 13)),
                    "model_version": "1.0.0",
                })
    return frame(rows)
