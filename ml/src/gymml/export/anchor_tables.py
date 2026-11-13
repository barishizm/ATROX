"""P060: Spline-LMS (P053 winner A) -> `anchor_tables.json` and a table-only evaluator.

The tables hold the knots and coefficients of `gymml.models.spline_lms.SplineLMS` plus the link clamps.
`TableAnchor` evaluates them with plain numpy + `boxcox` (no torch, no pickle), exactly the way Swift
`TableAnchorDistribution` does: clip age / log bodyweight to the knot range, tensor-product cubic
B-spline basis, link functions with clamps, BCPE (or BCCG) CDF / quantile.
"""
# ruff: noqa: E501

from __future__ import annotations

import math
from collections.abc import Mapping
from typing import Any

import numpy as np
import polars as pl
from scipy.interpolate import BSpline

from gymml.models import boxcox

LIFTS = ("squat", "bench", "deadlift")
FORMAT = "atrox-anchor-tables/1"
# SplineLMS._links / params clamps (log sigma, nu, log tau).
LINKS = {
    "log_sigma": [-6.0, 2.0],
    "nu": [-5.0, 5.0],
    "log_tau": [math.log(0.5), math.log(20.0)],
}


def tables_from_models(models: Mapping[str, Any]) -> dict:
    """`{lift: SplineLMS}` -> JSON-ready tables."""
    lifts = {}
    for lift in LIFTS:
        d = models[lift].to_dict()
        lifts[lift] = {
            "family": d["family"],
            "degree": d["degree"],
            "knotsAge": d["knots_age"],
            "knotsLogBw": d["knots_log_bw"],
            "coef": d["coef"],  # sex -> param -> [ka][kw]
        }
    return {"format": FORMAT, "links": LINKS, "lifts": lifts}


def _design(x: np.ndarray, t: np.ndarray, degree: int) -> np.ndarray:
    lo, hi = t[degree], t[-degree - 1]
    return BSpline.design_matrix(np.clip(x, lo, hi), t, degree).toarray()


class TableLift:
    """One lift: same `params / cdf / quantile` surface as `SplineLMS`."""

    def __init__(self, table: Mapping[str, Any], links: Mapping[str, list[float]]):
        self.family = table["family"]
        self.degree = int(table["degree"])
        self.t_age = np.asarray(table["knotsAge"], dtype=float)
        self.t_bw = np.asarray(table["knotsLogBw"], dtype=float)
        self.coef = {s: {k: np.asarray(v, float) for k, v in c.items()} for s, c in table["coef"].items()}
        self.links = links

    def _params_one(self, sex: str, age: np.ndarray, bw: np.ndarray) -> dict[str, np.ndarray]:
        ba = _design(np.asarray(age, float), self.t_age, self.degree)
        bb = _design(np.log(np.asarray(bw, float)), self.t_bw, self.degree)
        c = self.coef[sex]
        eta = {k: np.einsum("ni,ij,nj->n", ba, v, bb) for k, v in c.items()}
        lo_s, hi_s = self.links["log_sigma"]
        lo_n, hi_n = self.links["nu"]
        lo_t, hi_t = self.links["log_tau"]
        return {
            "mu": np.exp(eta["mu"]),
            "sigma": np.exp(np.clip(eta["sigma"], lo_s, hi_s)),
            "nu": np.clip(eta["nu"], lo_n, hi_n),
            "tau": np.exp(np.clip(eta["tau"], lo_t, hi_t)) if "tau" in eta else np.full(len(ba), 2.0),
        }

    def params(self, x: pl.DataFrame) -> dict[str, np.ndarray]:
        n = x.height
        out = {k: np.empty(n) for k in ("mu", "sigma", "nu", "tau")}
        sex = x["sex"].to_numpy()
        for s in self.coef:
            m = sex == s
            if m.any():
                p = self._params_one(s, x["age"].to_numpy()[m], x["bodyweight_kg"].to_numpy()[m])
                for k in out:
                    out[k][m] = p[k]
        if not np.isin(sex, list(self.coef)).all():
            raise ValueError("unknown sex in input")
        return out

    def cdf(self, x: pl.DataFrame, y: np.ndarray) -> np.ndarray:
        p = self.params(x)
        return boxcox.cdf(np.asarray(y, float), p["mu"], p["sigma"], p["nu"], p["tau"], self.family)

    def quantile(self, x: pl.DataFrame, q: np.ndarray) -> np.ndarray:
        p = self.params(x)
        q = np.asarray(q, float)[None, :]
        cols = (p[k][:, None] for k in ("mu", "sigma", "nu", "tau"))
        return boxcox.ppf(q, *cols, family=self.family)


def table_models(tables: Mapping[str, Any]) -> dict[str, TableLift]:
    if tables.get("format") != FORMAT:
        raise ValueError(f"unsupported anchor tables format {tables.get('format')!r}")
    return {lift: TableLift(tables["lifts"][lift], tables["links"]) for lift in LIFTS}


def random_inputs(n: int, seed: int) -> pl.DataFrame:
    """Ages 10-95 and bodyweights 25-270 kg (beyond the clip range on purpose), both sexes."""
    rng = np.random.default_rng(seed)
    return pl.DataFrame({
        "sex": rng.choice(["M", "F"], n),
        "age": rng.uniform(10, 95, n),
        "bodyweight_kg": rng.uniform(25, 270, n),
    })


def parity(models: Mapping[str, Any], tables: Mapping[str, Any], n: int = 2000, seed: int = 60) -> dict:
    """Max |difference| between the trained model and the exported tables on `n` random inputs:
    CDF at random loads and log quantiles at P1..P99."""
    tm = table_models(tables)
    x = random_inputs(n, seed)
    rng = np.random.default_rng(seed + 1)
    q = np.array([0.01, 0.158655, 0.5, 0.841345, 0.99])
    out = {}
    for lift in LIFTS:
        ref_q = models[lift].quantile(x, q)
        y = ref_q[:, 2] * rng.uniform(0.4, 1.8, n)
        out[lift] = {
            "max_abs_cdf": float(np.max(np.abs(models[lift].cdf(x, y) - tm[lift].cdf(x, y)))),
            "max_abs_log_quantile": float(np.max(np.abs(np.log(ref_q) - np.log(tm[lift].quantile(x, q))))),
        }
    out["n"] = n
    return out
