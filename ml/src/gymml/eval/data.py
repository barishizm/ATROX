"""Bölme (sporcu bazında gruplu %70/15/15) ve model girdilerinin yüklenmesi."""

from __future__ import annotations

import hashlib
from dataclasses import dataclass
from pathlib import Path

import numpy as np
import polars as pl

from gymml.data.cohort import ML_ROOT

PROCESSED = ML_ROOT / "data/processed"
COHORT_LONG = PROCESSED / "cohort_long.parquet"
SPLITS = PROCESSED / "splits.parquet"
SPLIT_SEED = 20260101
SPLIT_FRACTIONS = {"train": 0.70, "val": 0.15, "test": 0.15}


def make_splits(athlete_ids: pl.Series, seed: int = SPLIT_SEED) -> pl.DataFrame:
    """Sıralı benzersiz kimliklerin sabit tohumla karıştırılması → (athlete_id, split).

    Aynı sporcu hiçbir zaman iki bölmede olmaz; aynı girdi + tohum her zaman aynı bölmeyi verir.
    """
    ids = np.array(sorted(athlete_ids.unique().to_list()))
    perm = np.random.default_rng(seed).permutation(len(ids))
    n_train = int(round(len(ids) * SPLIT_FRACTIONS["train"]))
    n_val = int(round(len(ids) * SPLIT_FRACTIONS["val"]))
    labels = np.empty(len(ids), dtype=object)
    labels[perm[:n_train]] = "train"
    labels[perm[n_train : n_train + n_val]] = "val"
    labels[perm[n_train + n_val :]] = "test"
    return pl.DataFrame({"athlete_id": ids, "split": labels.astype(str)})


def splits_digest(splits: pl.DataFrame) -> str:
    h = hashlib.sha256()
    for aid, s in splits.sort("athlete_id").iter_rows():
        h.update(f"{aid}:{s}\n".encode())
    return h.hexdigest()[:16]


def ensure_splits(path: Path = SPLITS, cohort: Path = COHORT_LONG) -> pl.DataFrame:
    """Bölme dosyası yoksa kohorttan üret ve diske yaz; varsa olduğu gibi oku."""
    if path.exists():
        return pl.read_parquet(path)
    ids = pl.read_parquet(cohort, columns=["athlete_id"])["athlete_id"]
    splits = make_splits(ids)
    path.parent.mkdir(parents=True, exist_ok=True)
    splits.write_parquet(path)
    return splits


@dataclass(frozen=True)
class DataSpec:
    """Referans veri tanımı: varsayılan Tested=Yes ve wraps'sız (docs/03-ML-MODEL.md §4.1)."""

    tested_only: bool = True
    include_wraps: bool = False


def load_lift(lift: str, split: str, spec: DataSpec = DataSpec()) -> pl.DataFrame:
    splits = ensure_splits()
    df = pl.read_parquet(COHORT_LONG).filter(pl.col("lift") == lift)
    if spec.tested_only:
        df = df.filter(pl.col("tested"))
    if not spec.include_wraps:
        df = df.filter(~pl.col("wraps"))
    return df.join(splits, on="athlete_id").filter(pl.col("split") == split)
