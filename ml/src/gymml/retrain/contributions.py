"""P094 · contribution export: fetch `ml_contributions`, k-anonymity filter, Parquet, holdout split.

The raw rows only live in memory; what is written to disk (`data/processed/retrain/`) is the filtered table.
A cell is sex × age band × weight band × exercise; cells with fewer than `k_anonymity` distinct contribution keys
are dropped before anything else sees the data (docs/02-MIMARI.md §3.3, P093 note 3).
"""

from __future__ import annotations

import hashlib
import json
import urllib.request
from collections.abc import Callable, Mapping
from dataclasses import dataclass
from pathlib import Path

import polars as pl

COLUMNS = (
    "contribution_key", "sex", "age_band", "bodyweight_kg", "height_band", "experience_band",
    "frequency_band", "month", "exercise_id", "best_e1rm_kg", "best_set_reps", "sessions_in_month",
    "model_version",
)
SCHEMA = {
    "contribution_key": pl.Utf8, "sex": pl.Utf8, "age_band": pl.Int64, "bodyweight_kg": pl.Int64,
    "height_band": pl.Int64, "experience_band": pl.Utf8, "frequency_band": pl.Utf8, "month": pl.Utf8,
    "exercise_id": pl.Utf8, "best_e1rm_kg": pl.Float64, "best_set_reps": pl.Int64,
    "sessions_in_month": pl.Int64, "model_version": pl.Utf8,
}
SEX_TO_MODEL = {"male": "M", "female": "F"}
Fetch = Callable[[str, Mapping[str, str]], bytes]


class InsufficientData(RuntimeError):
    """Not enough contributions to retrain; the message says which threshold failed."""


@dataclass(frozen=True)
class FilterReport:
    rows_in: int
    rows_out: int
    contributors_in: int
    contributors_out: int
    cells_in: int
    cells_dropped: int

    def as_dict(self) -> dict:
        return dict(self.__dict__)


def frame(rows: list[Mapping]) -> pl.DataFrame:
    if not rows:
        return pl.DataFrame(schema=SCHEMA)
    return pl.DataFrame([{c: r[c] for c in COLUMNS} for r in rows], schema=SCHEMA)


def _urllib_fetch(url: str, headers: Mapping[str, str]) -> bytes:
    req = urllib.request.Request(url, headers=dict(headers))
    with urllib.request.urlopen(req, timeout=60) as resp:  # noqa: S310 - configured Supabase project
        return resp.read()


def fetch(base_url: str, service_key: str, page: int = 1000, get: Fetch = _urllib_fetch) -> pl.DataFrame:
    """All rows via PostgREST with the service role (the table has no client grants)."""
    headers = {"Authorization": f"Bearer {service_key}", "apikey": service_key}
    rows: list[dict] = []
    offset = 0
    while True:
        url = (f"{base_url.rstrip('/')}/rest/v1/ml_contributions?select={','.join(COLUMNS)}"
               f"&order=id&limit={page}&offset={offset}")
        chunk = json.loads(get(url, headers))
        rows.extend(chunk)
        if len(chunk) < page:
            return frame(rows)
        offset += page


def read(path: Path) -> pl.DataFrame:
    if path.suffix == ".parquet":
        return pl.read_parquet(path)
    if path.suffix == ".csv":
        return pl.read_csv(path, schema_overrides=SCHEMA)
    return frame(json.loads(path.read_text(encoding="utf-8")))


def k_anonymize(df: pl.DataFrame, k: int, weight_band_kg: int) -> tuple[pl.DataFrame, FilterReport]:
    cell = ["sex", "age_band", "weight_band", "exercise_id"]
    banded = df.with_columns((pl.col("bodyweight_kg") // weight_band_kg * weight_band_kg).alias("weight_band"))
    counts = banded.group_by(cell).agg(pl.col("contribution_key").n_unique().alias("n_keys"))
    keep = counts.filter(pl.col("n_keys") >= k).select(cell)
    out = banded.join(keep, on=cell, how="inner").drop("weight_band")
    report = FilterReport(
        rows_in=df.height, rows_out=out.height,
        contributors_in=df["contribution_key"].n_unique(), contributors_out=out["contribution_key"].n_unique(),
        cells_in=counts.height, cells_dropped=counts.height - keep.height,
    )
    return out, report


def check_sufficient(df: pl.DataFrame, anchor_ids: set[str], cfg: Mapping) -> dict:
    n = df["contribution_key"].n_unique()
    if n < cfg["min_contributors"]:
        raise InsufficientData(
            f"{n} contributors after the k-anonymity filter; at least {cfg['min_contributors']} are needed "
            "(configs/retrain.yaml export.min_contributors). Keep the current bundle."
        )
    per_sex = {}
    for sex in ("male", "female"):
        per_sex[sex] = (df.filter((pl.col("sex") == sex) & pl.col("exercise_id").is_in(list(anchor_ids)))
                        ["contribution_key"].n_unique())  # fmt: skip
        if per_sex[sex] < cfg["min_anchor_contributors_per_sex"]:
            raise InsufficientData(
                f"{per_sex[sex]} {sex} contributors with an anchor lift; at least "
                f"{cfg['min_anchor_contributors_per_sex']} are needed "
                "(export.min_anchor_contributors_per_sex). Keep the current bundle."
            )
    return {"contributors": n, "anchor_contributors": per_sex}


def holdout_mask(df: pl.DataFrame, fraction: float, seed: int) -> pl.Series:
    """Stable split by contribution key (a contributor is entirely in or out)."""
    def bucket(key: str) -> float:
        h = hashlib.sha256(f"{seed}:{key}".encode()).digest()
        return int.from_bytes(h[:8], "big") / 2**64

    keys = df["contribution_key"].unique().to_list()
    held = {k for k in keys if bucket(k) < fraction}
    return df["contribution_key"].is_in(list(held))


def latest_per_lift(df: pl.DataFrame) -> pl.DataFrame:
    """One row per contributor and exercise (the most recent month): no pseudo-replication across months."""
    return df.sort("month").group_by(["contribution_key", "exercise_id"], maintain_order=True).last()
