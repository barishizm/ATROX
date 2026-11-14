"""P094 · can the contribution schema drive P054's self-supervised 1RM-curve loss? (§2, §12.4)

The loss needs the same person and lift at *different rep counts close in time*: the curve is whatever makes
e1RM(load, reps) agree across those sets. A contribution row holds one number per lift and month: the best
e1RM (already computed with the shipped curve) and the reps of that set. So:

* within a month there is exactly one set per lift → no within-period contrast at all;
* across months the reps differ, but the change is confounded with training progress (one row a month, the
  best set), and `best_e1rm_kg` is the old curve's output, so a fit would partly learn the old curve back.

`identifiability` measures how much cross-month rep variation exists; the report uses it to explain why the
curve is *not* refitted and which minimal schema addition would make it possible (user decision, P094).
"""

from __future__ import annotations

import polars as pl


def identifiability(df: pl.DataFrame) -> dict:
    per = df.group_by(["contribution_key", "exercise_id"]).agg(
        pl.col("month").n_unique().alias("months"), pl.col("best_set_reps").n_unique().alias("rep_counts"))
    multi = per.filter(pl.col("months") >= 2)
    return {
        "contributor_lifts": per.height,
        "with_two_or_more_months": multi.height,
        "with_two_or_more_rep_counts": multi.filter(pl.col("rep_counts") >= 2).height,
        "within_month_contrasts": 0,  # by construction: one row per lift and month
        "refit": False,
    }


PROPOSAL = {
    "field": "rep_profile",
    "shape": "up to 4 pairs {rep_band: '1-3' | '4-6' | '7-10' | '11-15', load_kg: number, reps: int}",
    "meaning": "per lift and month, the heaviest working set in each rep band (raw load and reps, not e1RM)",
    "why": "gives within-month sets at different reps for the same person: what the self-supervised loss needs, "
           "and raw loads so the old curve is not learned back",
    "privacy": "adds at most 4 numbers per lift-month to data that already holds the best e1RM; no dates, no "
               "set counts. Slightly more distinctive rows, so the k-anonymity cell stays the same and the "
               "profile is dropped for lifts with fewer than 2 bands",
}
