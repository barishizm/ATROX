"""OpenPowerlifting içe aktarma testleri: birim (sentetik CSV) + veri sözleşmesi."""

from __future__ import annotations

import zipfile
from pathlib import Path

import polars as pl
import pytest

from gymml.data import opl
from gymml.utils.config import ML_ROOT

PARQUET = ML_ROOT / "data/interim/opl.parquet"
PD_LICENSE = (
    "-- Public Domain\n\n  OpenPowerlifting data is contributed to the public domain.\n\n"
    "  To the extent possible under law, all CSV data is waived of all\ncopyright and related"
    " or neighboring rights.\n"
)


def _row(**kw: str) -> str:
    base = dict.fromkeys(opl.RAW_COLUMNS, "")
    base.update(kw)
    return ",".join(base[c] for c in opl.RAW_COLUMNS)


def _write_csv(path: Path, rows: list[str]) -> Path:
    path.write_text(",".join(opl.RAW_COLUMNS) + "\n" + "\n".join(rows) + "\n", encoding="utf-8")
    return path


def test_athlete_id_is_stable_and_hides_name():
    a = opl.athlete_id("John Doe #1")
    assert a == opl.athlete_id("  john   DOE #1 ")
    assert a != opl.athlete_id("John Doe #2")
    assert len(a) == 16 and "doe" not in a.lower()


def test_transform_drops_names_and_types(tmp_path: Path):
    csv = _write_csv(
        tmp_path / "x.csv",
        [
            _row(Name="Ada Lovelace", Sex="F", Event="SBD", Equipment="Raw", Age="30",
                 BodyweightKg="60.5", Best3SquatKg="100", Best3BenchKg="50",
                 Best3DeadliftKg="120", TotalKg="270", Place="1", Tested="Yes",
                 Federation="IPF", Date="2020-05-01"),
            _row(Name="Ada Lovelace", Sex="F", Event="B", Equipment="Raw", Place="DQ",
                 Date="2021-05-01"),
        ],
    )  # fmt: skip
    df = opl.transform(csv)
    assert df.columns == opl.OUT_COLUMNS
    assert "Name" not in df.columns and not any("Lovelace" in str(v) for v in df.row(0))
    assert df["athlete_id"].n_unique() == 1
    assert df["tested"].to_list() == [True, False]
    assert df["date"].dtype == pl.Date and df["squat_kg"][0] == 100.0


def test_header_mismatch_stops(tmp_path: Path):
    bad = tmp_path / "bad.csv"
    bad.write_text("Name,Sex\nx,M\n")
    with pytest.raises(ValueError, match="şemayla"):
        opl.transform(bad)


def test_license_gate():
    assert opl.is_public_domain(PD_LICENSE)
    assert not opl.is_public_domain("Copyright (c) 2026 Someone. All rights reserved.")
    assert not opl.is_public_domain("Licensed under CC-BY-NC 4.0")


def test_read_license_and_sources(tmp_path: Path):
    z = tmp_path / "a.zip"
    with zipfile.ZipFile(z, "w") as f:
        f.writestr("d/LICENSE.txt", PD_LICENSE)
        f.writestr("d/README.txt", "readme")
    lic, readme = opl.read_license(z)
    assert lic == PD_LICENSE and readme == "readme"
    out = tmp_path / "SOURCES.md"
    opl.write_sources(out, z, lic)
    text = out.read_text()
    assert opl.sha256_file(z) in text and "> -- Public Domain" in text


# ---- Veri sözleşmesi (gerçek Parquet; `make data` sonrası) ----
needs_data = pytest.mark.skipif(not PARQUET.exists(), reason="önce `make data` çalıştırın")


@pytest.fixture(scope="module")
def df() -> pl.DataFrame:
    return pl.read_parquet(PARQUET)


@needs_data
def test_contract_columns_and_types(df: pl.DataFrame):
    assert df.columns == opl.OUT_COLUMNS
    f32, s = pl.Float32, pl.String
    expected = {
        "athlete_id": s, "sex": s, "event": s, "equipment": s, "age": f32, "age_class": s,
        "bodyweight_kg": f32, "squat_kg": f32, "bench_kg": f32, "deadlift_kg": f32,
        "total_kg": f32, "place": s, "dots": f32, "tested": pl.Boolean, "country": s,
        "federation": s, "parent_federation": s, "date": pl.Date,
    }  # fmt: skip
    assert dict(df.schema) == expected


@needs_data
def test_contract_row_floor_and_no_names(df: pl.DataFrame):
    assert df.height >= 3_000_000
    assert df["athlete_id"].null_count() == 0
    assert df["athlete_id"].str.len_chars().eq(16).all()
    assert df["athlete_id"].n_unique() >= 500_000
    assert "Name" not in df.columns and "name" not in df.columns


@needs_data
def test_contract_value_ranges(df: pl.DataFrame):
    assert set(df["sex"].unique()) <= {"M", "F", "Mx"}
    assert set(df["event"].unique()) <= {"SBD", "BD", "SD", "SB", "S", "B", "D"}
    assert set(df["equipment"].unique()) <= {
        "Raw", "Wraps", "Single-ply", "Multi-ply", "Unlimited", "Straps",
    }  # fmt: skip
    assert df["age"].drop_nulls().is_between(0, 110).all()
    assert df["bodyweight_kg"].drop_nulls().is_between(10, 400).all()
    for lift in ("squat_kg", "bench_kg", "deadlift_kg"):
        # Negatif değer "başarısız deneme" anlamında belgelenmiştir; makul üst sınır:
        assert df[lift].drop_nulls().is_between(-1000, 1000).all()
    assert df["total_kg"].drop_nulls().gt(0).all()
    assert df["date"].min().year >= 1960 and df["date"].null_count() == 0
    # Hem erkek hem kadın, hem Raw hem Tested kayıt bol olmalı (kohort için).
    raw_tested = df.filter((pl.col("equipment") == "Raw") & pl.col("tested"))
    assert raw_tested.height > 500_000
