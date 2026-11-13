"""Yarışmacı (competitor) referans dağılımı arayüzü (P055).

Kalibrasyon (docs/03-ML-MODEL.md §5.1) yarışmacı dağılımının log ölçekteki yerini `m_c(x)` ve
ölçeğini `s_c(x)` ister. Asıl kaynak P053'te seçilecek çapa modelidir; o henüz yokken
OpenPowerlifting'in ampirik koşullu dağılımı (aynı cinsiyet / yaş bandı / vücut ağırlığı hücresinin
çeyrekleri) kullanılır. P057, `CompetitorReference` protokolünü uygulayan P053 kazananını buraya
takar; kalibrasyon kodu değişmez.
"""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
from typing import Protocol

import numpy as np
import polars as pl

LIFTS = ("squat", "bench", "deadlift")
SEXES = ("M", "F")
# Kalibrasyon yaş bantları. "20-39" referans banttır (yaş ofseti 0).
AGE_BANDS = ("20-39", "40-49", "50-59", "60-69", "70+")
REF_BAND = "20-39"
_BAND_EDGES = {"20-39": (20, 40), "40-49": (40, 50), "50-59": (50, 60), "60-69": (60, 70),
               "70+": (70, 86)}
# Normal dağılımda 15,87 ve 84,13. yüzdelikler arası yarım genişlik = 1 σ.
_P_LO, _P_HI = 0.158655, 0.841345


def age_band_of(age: float) -> str:
    for band, (lo, hi) in _BAND_EDGES.items():
        if lo <= age < hi:
            return band
    raise ValueError(f"yaş kalibrasyon bantlarının dışında: {age}")


def _binned(db: pl.DataFrame, bin_kg: float, min_n: int) -> pl.DataFrame:
    return (db.with_columns(((pl.col("bodyweight_kg") / bin_kg).floor() * bin_kg + bin_kg / 2)
                            .alias("bw_bin"))
            .group_by("bw_bin")
            .agg(pl.len().alias("n"),
                 pl.col("ly").quantile(0.5, "linear").alias("q50"),
                 pl.col("ly").quantile(_P_LO, "linear").alias("qlo"),
                 pl.col("ly").quantile(_P_HI, "linear").alias("qhi"))
            .filter(pl.col("n") >= min_n).sort("bw_bin"))


class CompetitorReference(Protocol):
    """Yarışmacı dağılımının log-kg ölçeğinde yer ve ölçeği."""

    name: str

    def location_scale(self, sex: str, lift: str, age_band: str, bodyweight_kg: float
                       ) -> tuple[float, float]:
        """(m_c, s_c): log(1RM kg) medyanı ve sağlam ölçek (log uzayında ~1 σ)."""
        ...


@dataclass(frozen=True)
class _Cell:
    bw_grid: np.ndarray  # bin merkezleri (kg), artan
    m: np.ndarray        # log medyan
    s: np.ndarray        # log ölçek


class EmpiricalOPLReference:
    """OpenPowerlifting hücre çeyrekleri: cinsiyet × yaş bandı × vücut ağırlığı bini.

    Hafif filtre (P048 temizliğine bağımlı değil): Raw ekipman, M/F, yaş 20–85, vücut ağırlığı
    35–200 kg, kaldırış > 0 ve vücut ağırlığının 0,2–5 katı; sporcu × takvim yılı × kaldırış başına
    en iyi değer. Hücre değerleri vücut ağırlığına göre doğrusal enterpole edilir, uçlarda sabit
    tutulur.
    """

    def __init__(self, cells: dict[tuple[str, str, str], _Cell], name: str):
        self._cells = cells
        self.name = name

    @classmethod
    def from_parquet(cls, path: Path, tested_only: bool = True, bin_kg: float = 5.0,
                     min_n: int = 200) -> EmpiricalOPLReference:
        df = pl.read_parquet(path, columns=["athlete_id", "sex", "equipment", "age",
                                            "bodyweight_kg", "squat_kg", "bench_kg",
                                            "deadlift_kg", "tested", "date"])
        return cls.from_frame(df, tested_only=tested_only, bin_kg=bin_kg, min_n=min_n)

    @classmethod
    def from_frame(cls, df: pl.DataFrame, tested_only: bool = True, bin_kg: float = 5.0,
                   min_n: int = 200) -> EmpiricalOPLReference:
        base = df.filter(
            (pl.col("equipment") == "Raw")
            & pl.col("sex").is_in(list(SEXES))
            & pl.col("age").is_between(20, 85)
            & pl.col("bodyweight_kg").is_between(35, 200)
        )
        if tested_only:
            base = base.filter(pl.col("tested"))
        cells: dict[tuple[str, str, str], _Cell] = {}
        for lift in LIFTS:
            col = f"{lift}_kg"
            d = (
                base.filter((pl.col(col) > 0)
                            & (pl.col(col) / pl.col("bodyweight_kg")).is_between(0.2, 5.0))
                .with_columns(pl.col("date").dt.year().alias("year"))
                .sort(col, descending=True)
                .unique(subset=["athlete_id", "year"], keep="first")
                .select("sex", "age", "bodyweight_kg", pl.col(col).log().alias("ly"))
            )
            for sex in SEXES:
                ds = d.filter(pl.col("sex") == sex)
                for band, (lo, hi) in _BAND_EDGES.items():
                    db = ds.filter(pl.col("age").is_between(lo, hi, closed="left"))
                    agg = _binned(db, bin_kg, min_n)
                    if agg.height < 2:  # seyrek hücre (ör. 70+ kadın): geniş bin, düşük n
                        agg = _binned(db, 20.0, 30)
                    if agg.height == 0:
                        raise ValueError(f"boş hücre: {sex} {lift} {band}")
                    cells[(sex, lift, band)] = _Cell(
                        agg["bw_bin"].to_numpy(), agg["q50"].to_numpy(),
                        ((agg["qhi"] - agg["qlo"]) / 2).to_numpy())
        tag = "tested" if tested_only else "all"
        return cls(cells, name=f"opl-empirical-{tag}")

    def location_scale(self, sex: str, lift: str, age_band: str, bodyweight_kg: float
                       ) -> tuple[float, float]:
        c = self._cells[(sex, lift, age_band)]
        return (float(np.interp(bodyweight_kg, c.bw_grid, c.m)),
                float(np.interp(bodyweight_kg, c.bw_grid, c.s)))


class ParametricReference:
    """Testler ve duman denemeleri için kapalı biçimli referans: m = a + b·log(bw) − yaş düşüşü."""

    name = "parametric"

    def __init__(self, a: dict[tuple[str, str], float], b: float = 0.67, s: float = 0.18,
                 age_drop: dict[str, float] | None = None):
        self._a, self._b, self._s = a, b, s
        self._drop = age_drop or {"20-39": 0.0, "40-49": 0.03, "50-59": 0.12, "60-69": 0.25,
                                  "70+": 0.40}

    def location_scale(self, sex: str, lift: str, age_band: str, bodyweight_kg: float
                       ) -> tuple[float, float]:
        m = self._a[(sex, lift)] + self._b * np.log(bodyweight_kg) - self._drop[age_band]
        return float(m), self._s
