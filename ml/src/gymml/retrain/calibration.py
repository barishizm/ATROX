"""P094 · Bayesian update of the gym-population calibration (δ, κ) from app contributions (§5.1, §12.2).

§5.1: a gym user's z is z_g = (z_c + δ/s_c) / κ with z_c the competitor z of the anchor lift and s_c the anchor
model's log-scale spread. For gym users z_g ~ N(0, 1), so u = z_c · s_c ~ N(−δ, (κ s_c)²):

    δ̂_cell = −median(u)                             per sex × lift × age band
    κ̂_sex  = IQR((u + δ̂_cell) / s_c) / 1.349        pooled over the sex's lifts and bands

Median and IQR, not mean and SD: the anchor CDF is clipped (`cdf_clip`), so weak gym users pile up at the lower
clip (≈ 5 % of a realistic gym sample), which biases moments but not quartiles; quartiles also shrug off the odd
mistyped set that passed the app's checks.

The current values are the prior and the contributions the likelihood, as n0 pseudo-contributors. The prior share
w = n0 / (n0 + n) shrinks as data grows but is floored (`prior_weight_floor`): app users are not a random gym
sample (people who log every set are more serious, survivors keep logging, e1RM is self-reported), so the
P055 anchors keep a stake however large the app data gets.
"""

from __future__ import annotations

import copy
import math
from collections.abc import Mapping

import numpy as np
import polars as pl
from scipy.stats import norm

from gymml.calibration.reference import age_band_of
from gymml.retrain.contributions import SEX_TO_MODEL
from gymml.scoring import AnchorModel, Exercise, Params

IQR_NORMAL = 1.3489795003921634  # IQR of N(0, 1)
AGE_IN_BAND = 2.0  # contributions carry the 5-year band's lower bound; score at its middle


def contribution_age(age_band: np.ndarray) -> np.ndarray:
    return np.asarray(age_band, float) + AGE_IN_BAND


def anchor_z_scale(
    model: AnchorModel, lift: str, sex: np.ndarray, age: np.ndarray, bw: np.ndarray, value: np.ndarray
) -> tuple[np.ndarray, np.ndarray]:
    """Vectorised `AnchorModel.z_and_scale`."""
    x = pl.DataFrame({"sex": sex, "age": np.asarray(age, float), "bodyweight_kg": np.asarray(bw, float)})
    m = model.models[lift]
    f = np.clip(m.cdf(x, np.asarray(value, float)), *model.clip)
    q = np.log(m.quantile(x, model.scale_q))
    return norm.ppf(f), (q[:, 1] - q[:, 0]) / 2


def anchor_observations(df: pl.DataFrame, catalog: Mapping[str, Exercise], model: AnchorModel,
                        p: Params) -> pl.DataFrame:
    """Rows of anchor lifts with z_c, s_c, model sex, lift and calibration age band."""
    anchors = {e.id: e.anchor for e in catalog.values() if e.is_anchor}
    rows = df.filter(pl.col("exercise_id").is_in(list(anchors)))
    if rows.is_empty():
        return rows.with_columns(pl.lit(None).alias(c) for c in ("lift", "msex", "band", "z_c", "s_c"))
    rows = rows.with_columns(
        pl.col("exercise_id").replace_strict(anchors).alias("lift"),
        pl.col("sex").replace_strict(SEX_TO_MODEL).alias("msex"),
    )
    min_age = float(p.scoring["exercise_score"]["calibration_min_age_band"].split("-")[0])
    ages = contribution_age(rows["age_band"].to_numpy())
    rows = rows.with_columns(pl.Series("band", [age_band_of(min(max(a, min_age), 85.0)) for a in ages]))
    zc = np.empty(rows.height)
    sc = np.empty(rows.height)
    lifts = rows["lift"].to_numpy()
    for lift in np.unique(lifts):
        m = lifts == lift
        z, s = anchor_z_scale(model, str(lift), rows["msex"].to_numpy()[m], ages[m],
                              rows["bodyweight_kg"].to_numpy()[m], rows["best_e1rm_kg"].to_numpy()[m])
        zc[m], sc[m] = z, s
    return rows.with_columns(pl.Series("z_c", zc), pl.Series("s_c", sc))


def prior_weight(n: int, cfg: Mapping) -> float:
    n0 = float(cfg["prior_pseudo_n"])
    return max(float(cfg["prior_weight_floor"]), n0 / (n0 + n))


def update(obs: pl.DataFrame, p: Params, cfg: Mapping) -> tuple[dict, dict]:
    """New `calibration` block (deep copy, only `pop` changed) and a per-cell report."""
    pop = cfg["population"]
    cal = copy.deepcopy(p.calibration)
    report: dict = {"population": pop, "cells": [], "kappa": {}}
    lo_k, hi_k = cfg["kappa_bounds"]
    for sex in ("M", "F"):
        sx = obs.filter(pl.col("msex") == sex)
        resid, n_sex = [], 0
        for lift, bands in cal["delta"][pop][sex].items():
            for band, prior in bands.items():
                c = sx.filter((pl.col("lift") == lift) & (pl.col("band") == band))
                n = c.height
                entry = {"sex": sex, "lift": lift, "band": band, "n": n, "prior": prior}
                if n < cfg["min_cell_contributors"]:
                    report["cells"].append({**entry, "estimate": None, "posterior": prior, "w_prior": 1.0})
                    continue
                u = c["z_c"].to_numpy() * c["s_c"].to_numpy()
                est = float(-np.median(u))
                w = prior_weight(n, cfg)
                post = w * prior + (1 - w) * est
                bands[band] = round(post, 4)
                resid.append((u + est) / c["s_c"].to_numpy())
                n_sex += n
                report["cells"].append({**entry, "estimate": est, "posterior": bands[band], "w_prior": w})
        prior_k = cal["kappa"][pop][sex]
        if n_sex == 0:
            report["kappa"][sex] = {"n": 0, "prior": prior_k, "estimate": None, "posterior": prior_k}
            continue
        q25, q75 = np.quantile(np.concatenate(resid), [0.25, 0.75])
        est_k = float((q75 - q25) / IQR_NORMAL)
        w = prior_weight(n_sex, cfg)
        post_k = float(np.clip(math.exp(w * math.log(prior_k) + (1 - w) * math.log(est_k)), lo_k, hi_k))
        cal["kappa"][pop][sex] = round(post_k, 4)
        report["kappa"][sex] = {"n": n_sex, "prior": prior_k, "estimate": est_k,
                                "posterior": cal["kappa"][pop][sex], "w_prior": w}
    return cal, report
