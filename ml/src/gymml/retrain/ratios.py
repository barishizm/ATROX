"""P094 · shrinkage estimate of ρ_e and τ_e from contributors who log both e and its anchor (§6, §12.3).

For a contributor with both lifts in the same month, d = log e1RM_e − log e1RM_anchor (e1RM in the written unit,
exactly what scoring divides by ρ). Per exercise, over contributors (latest shared month each):

    m_e, s_e = mean and SD of d,  n_e contributors
    log ρ:  prior N(log ρ_prior, σ_grade²), likelihood N(m_e, s_e²/n_e)  → normal posterior (mean, sd)
    τ²:     scaled inverse chi-square, ν0 pseudo-df at τ_prior²         → (ν0 τ_prior² + n s_e²) / (ν0 + n)

Grades go up from data (C → B → A) when n, the posterior SD and the between-person SD pass `upgrade`; machines
and cables stay C (pulleys and brands differ between gyms). Grades never go down here: a prior-data conflict is
reported instead. τ never drops below the floor of the (new) grade, so a C exercise still cannot produce an
extreme score (P056 rule).
"""

from __future__ import annotations

import dataclasses
import math
from collections.abc import Mapping

import numpy as np
import polars as pl

from gymml.retrain.contributions import latest_per_lift
from gymml.scoring import Exercise, Params, is_machine

GRADES = ("C", "B", "A")


def paired_log_ratios(df: pl.DataFrame, catalog: Mapping[str, Exercise]) -> pl.DataFrame:
    anchor_ids = {e.anchor: e.id for e in catalog.values() if e.is_anchor}
    target = {e.id: anchor_ids[e.anchor] for e in catalog.values()
              if e.scorable and e.scoring_type != "reps_only" and not e.is_anchor and e.anchor in anchor_ids}
    if not target:
        return pl.DataFrame(schema={"exercise_id": pl.Utf8, "contribution_key": pl.Utf8, "d": pl.Float64})
    lifts = df.filter(pl.col("exercise_id").is_in(list(target))).with_columns(
        pl.col("exercise_id").replace_strict(target).alias("anchor_id"))
    anchors = df.filter(pl.col("exercise_id").is_in(list(anchor_ids.values()))).select(
        "contribution_key", "month", pl.col("exercise_id").alias("anchor_id"),
        pl.col("best_e1rm_kg").alias("anchor_e1rm"))
    pairs = lifts.join(anchors, on=["contribution_key", "month", "anchor_id"], how="inner").with_columns(
        (pl.col("best_e1rm_kg").log() - pl.col("anchor_e1rm").log()).alias("d"))
    return latest_per_lift(pairs).select("exercise_id", "contribution_key", "d")


def _grade_from_data(n: int, post_sd: float, s: float, cfg: Mapping) -> str:
    up = cfg["upgrade"]
    for g in ("A", "B"):
        r = up[g]
        if n >= r["min_contributors"] and post_sd <= r["max_posterior_sd"] and s <= r["max_between_sd"]:
            return g
    return "C"


def update(pairs: pl.DataFrame, catalog: Mapping[str, Exercise], p: Params, cfg: Mapping
           ) -> tuple[dict[str, Exercise], list[dict]]:
    """New catalog (changed rows replaced) and one report row per exercise with paired data."""
    out = dict(catalog)
    rows = []
    stats = pairs.group_by("exercise_id").agg(
        pl.len().alias("n"), pl.col("d").mean().alias("m"), pl.col("d").std().alias("s"))
    for r in stats.sort("exercise_id").iter_rows(named=True):
        ex = catalog[r["exercise_id"]]
        n, m, s = int(r["n"]), float(r["m"]), float(r["s"] or 0.0)
        prior_grade = ex.ratio_confidence or "C"
        entry = {"exercise_id": ex.id, "anchor": ex.anchor, "n": n, "prior_ratio": ex.ratio,
                 "prior_tau": ex.tau, "prior_grade": prior_grade, "mean_log_ratio": m, "between_sd": s}
        if n < cfg["min_pair_contributors"] or n < 2:
            rows.append({**entry, "ratio": ex.ratio, "tau": ex.tau, "grade": prior_grade, "changed": False,
                         "note": "too few contributors"})
            continue
        sd0 = float(cfg["prior_sd"][prior_grade])
        mu0 = math.log(ex.ratio)
        se2 = max(s, 1e-3) ** 2 / n
        post_var = 1.0 / (1.0 / sd0**2 + 1.0 / se2)
        post_mean = post_var * (mu0 / sd0**2 + m / se2)
        post_sd = math.sqrt(post_var)
        machine = is_machine(ex, p)
        data_grade = "C" if machine else _grade_from_data(n, post_sd, s, cfg)
        grade = max(prior_grade, data_grade, key=GRADES.index)
        nu0 = float(cfg["tau_pseudo_df"])
        tau_post = math.sqrt((nu0 * ex.tau**2 + n * s**2) / (nu0 + n))
        floor = cfg["tau_floor"]["machine" if machine else grade]
        tau = round(max(tau_post, floor), 4)
        ratio = round(math.exp(post_mean), 4)
        conflict = abs(m - mu0) > 3 * math.sqrt(sd0**2 + se2)
        rows.append({**entry, "ratio": ratio, "tau": tau, "grade": grade, "posterior_sd": post_sd,
                     "changed": True, "note": "prior-data conflict" if conflict else ""})
        out[ex.id] = dataclasses.replace(ex, ratio=ratio, tau=tau, ratio_confidence=grade)
    return out, rows


def implausible(rows: list[dict], max_change: float) -> list[str]:
    bad = []
    for r in rows:
        if r["changed"] and not (1 / max_change <= r["ratio"] / r["prior_ratio"] <= max_change):
            bad.append(f"{r['exercise_id']}: ratio {r['prior_ratio']} -> {r['ratio']}")
    return bad


def summary(rows: list[dict]) -> dict:
    changed = [r for r in rows if r["changed"]]
    return {
        "exercises_with_pairs": len(rows),
        "updated": len(changed),
        "upgraded": sum(1 for r in changed if r["grade"] != r["prior_grade"]),
        "conflicts": sum(1 for r in changed if r["note"] == "prior-data conflict"),
        "median_abs_log_change": float(np.median([abs(math.log(r["ratio"] / r["prior_ratio"]))
                                                  for r in changed])) if changed else 0.0,
    }
