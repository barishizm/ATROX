"""Contribution integrity filters, run on the raw export BEFORE the k-anonymity filter (docs/03-ML-MODEL.md §12).

Why: `contribute` rate-limits per account but `contribution_key` is deliberately unlinked from the user, so the server
cannot cap one person's total volume. Anyone with several free accounts can submit physically plausible fake rows
(e1RM ≤ 700 kg) under fresh random keys and drag the gym-population percentile distribution. Three defences here,
a fourth (the shift gate) in `gates.py`:

1. duplicates   keys whose whole payload (demographics + every lift) is identical to another key's: one is kept.
2. outliers     anchor lifts whose z under the base anchor model is beyond `max_abs_z`; every lift whose log e1RM is
                more than `outlier_mads` robust SDs from its (sex × exercise × weight band) median.
3. density      per (sex × age band × weight band × exercise) cell, log e1RM is binned (`density_bin_log`); a bin may
                hold at most `max_bin_share` of the cell's contributors (and never fewer than `min_bin_keys`). Real
                lifters spread out; a bot farm piles onto a handful of values. Excess keys are dropped in a seeded,
                key-hash order, so the result is deterministic.

Dropping rows only ever makes a cell smaller, so the k-anonymity filter afterwards also removes cells that were
only populated enough by fake contributors. `gates.integrity_gate` fails the whole retrain when too much was dropped.
"""

from __future__ import annotations

import hashlib
import math
from collections.abc import Mapping
from dataclasses import dataclass, field

import numpy as np
import polars as pl

from gymml.retrain import calibration
from gymml.scoring import AnchorModel, Exercise, Params

MAD_TO_SD = 1.4826


@dataclass(frozen=True)
class IntegrityReport:
    rows_in: int
    rows_out: int
    contributors_in: int
    contributors_out: int
    duplicate_keys: int = 0
    outlier_rows: int = 0
    density_keys: int = 0
    notes: dict = field(default_factory=dict)

    @property
    def dropped_row_fraction(self) -> float:
        return 0.0 if self.rows_in == 0 else 1 - self.rows_out / self.rows_in

    def as_dict(self) -> dict:
        d = {k: v for k, v in self.__dict__.items() if k != "notes"}
        return {**d, "dropped_row_fraction": self.dropped_row_fraction, **self.notes}


def _hash(seed: int, key: str) -> int:
    return int.from_bytes(hashlib.sha256(f"{seed}:{key}".encode()).digest()[:8], "big")


def drop_duplicate_profiles(df: pl.DataFrame, max_identical: int, seed: int) -> tuple[pl.DataFrame, int]:
    """Keep at most `max_identical` keys per identical payload fingerprint (which key survives is seeded)."""
    if df.is_empty():
        return df, 0
    demo = ["sex", "age_band", "bodyweight_kg", "height_band", "experience_band", "frequency_band"]
    lifts = (df.sort(["month", "exercise_id"])
             .with_columns(pl.format("{}|{}|{}|{}|{}", "month", "exercise_id", "best_e1rm_kg", "best_set_reps",
                                     "sessions_in_month").alias("_lift"))
             .group_by("contribution_key", maintain_order=True)
             .agg(pl.col("_lift").str.join(";").alias("_fp"), *[pl.col(c).first() for c in demo]))
    lifts = lifts.with_columns(pl.concat_str([pl.col(c).cast(pl.Utf8) for c in demo] + ["_fp"], separator="#").alias("_fp"))
    keys = lifts["contribution_key"].to_list()
    fps = lifts["_fp"].to_list()
    groups: dict[str, list[str]] = {}
    for k, f in zip(keys, fps, strict=True):
        groups.setdefault(f, []).append(k)
    drop: set[str] = set()
    for members in groups.values():
        if len(members) > max_identical:
            members.sort(key=lambda k: _hash(seed, k))
            drop.update(members[max_identical:])
    return df.filter(~pl.col("contribution_key").is_in(list(drop))), len(drop)


def drop_outlier_rows(df: pl.DataFrame, catalog: Mapping[str, Exercise], model: AnchorModel, p: Params,
                      max_abs_z: float, outlier_mads: float, mad_floor: float,
                      min_cell: int) -> tuple[pl.DataFrame, int]:
    if df.is_empty():
        return df, 0
    df = df.with_row_index("_row")
    bad: set[int] = set()
    # (a) anchor lifts: |z| under the base anchor model (z_c carries no gym shift; the bound is deliberately wide).
    obs = calibration.anchor_observations(df, catalog, model, p)
    if obs.height:
        z = obs["z_c"].to_numpy()
        bad.update(obs["_row"].filter(pl.Series(np.abs(z) > max_abs_z)).to_list())
    # (b) every lift: robust z of log e1RM inside sex × exercise × 10 kg weight band.
    w = df.with_columns(
        pl.col("best_e1rm_kg").log().alias("_l"),
        (pl.col("bodyweight_kg") // 10 * 10).alias("_wb"),
    )
    cell = ["sex", "exercise_id", "_wb"]
    med = w.group_by(cell).agg(pl.col("_l").median().alias("_med"), pl.len().alias("_n"))
    w = w.join(med, on=cell)
    mad = (w.with_columns((pl.col("_l") - pl.col("_med")).abs().alias("_dev"))
           .group_by(cell).agg(pl.col("_dev").median().alias("_mad")))
    w = w.join(mad, on=cell).with_columns(
        (pl.col("_mad") * MAD_TO_SD).clip(lower_bound=mad_floor * MAD_TO_SD).alias("_sd"))
    flagged = w.filter((pl.col("_n") >= min_cell) & ((pl.col("_l") - pl.col("_med")).abs() > outlier_mads * pl.col("_sd")))
    bad.update(flagged["_row"].to_list())
    kept = df.filter(~pl.col("_row").is_in(list(bad))).drop("_row")
    return kept, len(bad)


def thin_dense_bins(df: pl.DataFrame, bin_log: float, max_share: float, min_bin_keys: int, min_cell_keys: int,
                    weight_band_kg: int, seed: int) -> tuple[pl.DataFrame, int]:
    """Cap how many contributors a single e1RM bin may hold inside a cell; returns the thinned frame and #dropped keys."""
    if df.is_empty():
        return df, 0
    df = df.with_row_index("_row").with_columns(
        (pl.col("bodyweight_kg") // weight_band_kg * weight_band_kg).alias("_wb"),
        (pl.col("best_e1rm_kg").log() / bin_log).floor().cast(pl.Int64).alias("_bin"),
    )
    cell = ["sex", "age_band", "_wb", "exercise_id"]
    sizes = df.group_by(cell).agg(pl.col("contribution_key").n_unique().alias("_cell_keys"))
    df = df.join(sizes, on=cell)
    per_bin = (df.group_by(cell + ["_bin"]).agg(pl.col("contribution_key").unique().alias("_keys"), pl.col("_cell_keys").first()))
    drop_rows: set[int] = set()
    dropped_keys: set[str] = set()
    for row in per_bin.iter_rows(named=True):
        n_cell = row["_cell_keys"]
        if n_cell < min_cell_keys:
            continue
        cap = max(min_bin_keys, math.ceil(max_share * n_cell))
        keys = row["_keys"]
        if len(keys) <= cap:
            continue
        keys = sorted(keys, key=lambda k: _hash(seed, k))
        dropped_keys.update(keys[cap:])
        # Remove just this cell's bin rows of the excess keys.
        drop = df.filter((pl.col("sex") == row["sex"]) & (pl.col("age_band") == row["age_band"])
                         & (pl.col("_wb") == row["_wb"]) & (pl.col("exercise_id") == row["exercise_id"])
                         & (pl.col("_bin") == row["_bin"]) & pl.col("contribution_key").is_in(keys[cap:]))
        drop_rows.update(drop["_row"].to_list())
    kept = df.filter(~pl.col("_row").is_in(list(drop_rows))).drop("_row", "_wb", "_bin", "_cell_keys")
    return kept, len(dropped_keys)


def sanitize(df: pl.DataFrame, catalog: Mapping[str, Exercise], model: AnchorModel, p: Params,
             cfg: Mapping, weight_band_kg: int, seed: int) -> tuple[pl.DataFrame, IntegrityReport]:
    rows_in, keys_in = df.height, df["contribution_key"].n_unique()
    out, dup = drop_duplicate_profiles(df, int(cfg["max_identical_profiles"]), seed)
    out, outliers = drop_outlier_rows(out, catalog, model, p, float(cfg["max_abs_z"]), float(cfg["outlier_mads"]),
                                      float(cfg["mad_floor"]), int(cfg["min_outlier_cell"]))
    out, dense = thin_dense_bins(out, float(cfg["density_bin_log"]), float(cfg["max_bin_share"]),
                                 int(cfg["min_bin_keys"]), int(cfg["min_density_cell"]), weight_band_kg, seed)
    return out, IntegrityReport(rows_in, out.height, keys_in, out["contribution_key"].n_unique(), dup, outliers, dense)
