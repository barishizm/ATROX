"""P048 kohort süzgeçleri: sentetik birim testleri + üretilmiş tablolar için sözleşme testleri."""

from __future__ import annotations

import dataclasses
from datetime import date
from pathlib import Path

import polars as pl
import pytest

from gymml.data.cohort import (
    AGE_BAND_EDGES,
    BW_BAND_EDGES,
    CohortConfig,
    age_class_midpoint,
    band,
    build,
)

ML_ROOT = Path(__file__).resolve().parents[1]
CFG = CohortConfig()


def row(**kw):
    base = {
        "athlete_id": "a1", "sex": "M", "event": "SBD", "equipment": "Raw", "age": 30.0,
        "age_class": "24-34", "bodyweight_kg": 90.0, "squat_kg": 200.0, "bench_kg": 140.0,
        "deadlift_kg": 240.0, "total_kg": 580.0, "place": "1", "dots": 400.0, "tested": True,
        "country": None, "federation": "X", "parent_federation": None, "date": date(2020, 5, 1),
    }  # fmt: skip
    base.update(kw)
    return base


def frame(*rows) -> pl.DataFrame:
    return pl.DataFrame(
        list(rows), schema_overrides={"age": pl.Float32, "bodyweight_kg": pl.Float32}
    )


def long_of(*rows, cfg: CohortConfig = CFG) -> pl.DataFrame:
    return build(frame(*rows), cfg).long


def test_basic_row_becomes_three_lifts_with_weight_one():
    long = long_of(row())
    assert sorted(long["lift"].to_list()) == ["bench", "deadlift", "squat"]
    assert long["weight"].to_list() == [1.0, 1.0, 1.0]


@pytest.mark.parametrize(
    "change",
    [
        {"sex": "Mx"},
        {"equipment": "Single-ply"},
        {"place": "DQ"},
        {"place": "DD"},
        {"place": "G"},
        {"place": "NS"},
        {"age": 13.0},
        {"age": 86.0},
        {"age": None},
        {"bodyweight_kg": None},
        {"bodyweight_kg": 20.0},
    ],
)
def test_record_level_filters_drop_row(change):
    assert long_of(row(**change)).height == 0


def test_failed_and_missing_lifts_dropped():
    long = long_of(row(squat_kg=-200.0, bench_kg=None))
    assert long["lift"].to_list() == ["deadlift"]


def test_single_lift_event_only_contributes_that_lift():
    long = long_of(row(event="B", squat_kg=None, deadlift_kg=None))
    assert long["lift"].to_list() == ["bench"]


def test_wraps_flag_only_for_squat():
    long = long_of(row(equipment="Wraps"))
    flags = dict(zip(long["lift"], long["wraps"], strict=True))
    assert flags == {"squat": True, "bench": False, "deadlift": False}


def test_impossible_values_removed():
    # 6× vücut ağırlığı bench ve rekor üstü deadlift
    long = long_of(row(bodyweight_kg=60.0, bench_kg=360.0, deadlift_kg=500.0, squat_kg=10.0))
    assert long.height == 0


def test_best_per_athlete_year_and_inverse_frequency_weight():
    rows = [
        row(date=date(2020, 1, 1), bench_kg=130.0),
        row(date=date(2020, 9, 1), bench_kg=145.0, bodyweight_kg=92.0),
        row(date=date(2021, 3, 1), bench_kg=150.0),
        row(athlete_id="b2", date=date(2021, 3, 1), bench_kg=100.0),
    ]
    bench = long_of(*rows).filter(pl.col("lift") == "bench").sort("athlete_id", "year")
    a1 = bench.filter(pl.col("athlete_id") == "a1")
    assert a1["value_kg"].to_list() == [145.0, 150.0]
    assert a1["bodyweight_kg"].to_list()[0] == pytest.approx(92.0)  # en iyi kaydın kilosu
    assert a1["weight"].to_list() == [0.5, 0.5]
    assert bench.filter(pl.col("athlete_id") == "b2")["weight"].to_list() == [1.0]
    # Her sporcunun ağırlık toplamı 1
    sums = bench.group_by("athlete_id").agg(pl.col("weight").sum())["weight"].to_list()
    assert sums == pytest.approx([1.0, 1.0])


def test_age_imputation_is_opt_in():
    r = row(age=None, age_class="40-44")
    assert long_of(r).height == 0
    long = long_of(r, cfg=dataclasses.replace(CFG, impute_age_from_class=True))
    assert long["age"].unique().to_list() == [42.0]
    assert long["age_imputed"].all()


def test_age_class_midpoint():
    s = pl.DataFrame({"c": ["40-44", "24-34", "90-999", None]}).select(
        age_class_midpoint(pl.col("c"))
    )
    assert s.to_series().to_list() == [42.0, 29.0, 544.5, None]


def test_bands_are_left_closed():
    d = pl.DataFrame({"age": [14.0, 18.9, 19.0, 85.0, 13.0]}).select(band("age", AGE_BAND_EDGES))
    assert d.to_series().to_list() == ["14-18", "14-18", "19-23", "70-85", None]
    d = pl.DataFrame({"bodyweight_kg": [49.9, 50.0, 249.0]}).select(
        band("bodyweight_kg", BW_BAND_EDGES)
    )
    assert d.to_series().to_list() == ["30-49", "50-59", "140-249"]


def test_sbd_joint_requires_all_three_and_consistent_ratios():
    rows = [
        row(),  # tam
        row(athlete_id="b", bench_kg=-100.0),  # bench başarısız → ortak tabloda yok
        row(athlete_id="c", bench_kg=290.0, squat_kg=150.0),  # bench/squat 1.93 → tutarsız
        row(athlete_id="d", event="BD", squat_kg=None),
    ]
    c = build(frame(*rows), CFG)
    assert c.sbd["athlete_id"].to_list() == ["a1"]
    assert c.sbd_inconsistent_dropped == 1


def test_flow_is_monotone_until_long_format():
    c = build(frame(row(), row(athlete_id="x", sex="Mx"), row(athlete_id="y", place="DQ")), CFG)
    rows = [s["rows"] for s in c.flow]
    wide = rows[: rows.index(next(s["rows"] for s in c.flow if s["step"].startswith("uzun")))]
    assert wide == sorted(wide, reverse=True)
    assert c.flow[0]["rows"] == 3


# --- Üretilmiş tablolar için sözleşme testleri (make eda sonrası; dosya yoksa atlanır) ---

LONG = ML_ROOT / "data/processed/cohort_long.parquet"
SBD = ML_ROOT / "data/processed/cohort_sbd.parquet"


@pytest.mark.skipif(not LONG.exists(), reason="cohort_long.parquet yok (make eda)")
def test_cohort_long_contract():
    d = pl.read_parquet(LONG)
    assert d.height > 1_000_000
    assert set(d["sex"].unique()) == {"M", "F"}
    assert set(d["lift"].unique()) == {"squat", "bench", "deadlift"}
    assert d["age"].min() >= CFG.age_min and d["age"].max() <= CFG.age_max
    assert d["value_kg"].min() >= CFG.min_lift_kg
    assert d.filter(pl.col("lift") != "squat")["wraps"].sum() == 0
    assert d.select(pl.struct("athlete_id", "year", "lift", "wraps").is_unique().all()).item()
    sums = d.group_by("athlete_id", "lift", "wraps").agg(pl.col("weight").sum())["weight"]
    assert (sums - 1).abs().max() < 1e-9


@pytest.mark.skipif(not SBD.exists(), reason="cohort_sbd.parquet yok (make eda)")
def test_cohort_sbd_contract():
    d = pl.read_parquet(SBD)
    assert d.height > 100_000
    for lift in ("squat", "bench", "deadlift"):
        assert d[f"{lift}_kg"].min() > 0
    assert d.select(pl.struct("athlete_id", "year", "wraps").is_unique().all()).item()
