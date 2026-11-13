"""Age/sex repetition norms for `reps_only` exercises (P056, docs/03-ML-MODEL.md §6).

`ml/data/rep_norms.csv` holds a few (percentile, reps) points per test × sex × age band;
see `data/REP_NORMS.md` for sources and protocols. `percentile()` interpolates linearly
between the points and clamps outside them.
"""
from __future__ import annotations

import csv
from dataclasses import dataclass
from pathlib import Path

ML_ROOT = Path(__file__).resolve().parents[3]
NORMS_PATH = ML_ROOT / "data" / "rep_norms.csv"
COLUMNS = [
    "test", "exercise_ids", "sex", "age_min", "age_max", "percentile", "reps", "protocol", "source",
]
SOURCES = {"csep_path_2019", "ymca_2000"}


@dataclass(frozen=True)
class NormPoint:
    test: str
    exercise_ids: tuple[str, ...]
    sex: str
    age_min: int
    age_max: int
    percentile: float
    reps: float
    protocol: str
    source: str


def _point(r: dict[str, str]) -> NormPoint:
    return NormPoint(
        r["test"], tuple(r["exercise_ids"].split(";")), r["sex"], int(r["age_min"]),
        int(r["age_max"]), float(r["percentile"]), float(r["reps"]), r["protocol"], r["source"],
    )


def load(path: Path = NORMS_PATH) -> list[NormPoint]:
    with path.open(newline="", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        if reader.fieldnames != COLUMNS:
            raise ValueError(f"rep_norms.csv columns {reader.fieldnames} != {COLUMNS}")
        return [_point(r) for r in reader]


def curve(
    points: list[NormPoint], exercise_id: str, sex: str, age: int
) -> list[tuple[float, float]]:
    """(reps, percentile) pairs for one exercise/sex/age by percentile; empty if no norm."""
    sel = [
        p for p in points
        if exercise_id in p.exercise_ids and p.sex == sex and p.age_min <= age <= p.age_max
    ]
    return sorted(((p.reps, p.percentile) for p in sel), key=lambda t: t[1])


def percentile(
    points: list[NormPoint], exercise_id: str, sex: str, age: int, reps: float
) -> float | None:
    c = curve(points, exercise_id, sex, age)
    if not c:
        return None
    if reps <= c[0][0]:
        return c[0][1]
    if reps >= c[-1][0]:
        return c[-1][1]
    for (r0, p0), (r1, p1) in zip(c, c[1:], strict=False):
        if r0 <= reps <= r1:
            return p0 if r1 == r0 else p0 + (p1 - p0) * (reps - r0) / (r1 - r0)
    return None  # pragma: no cover - curve is monotone (tested)
