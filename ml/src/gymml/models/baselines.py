"""P049 temel çizgileri: (1) hücre bazlı ampirik yüzdelikler, (2) DOTS puanının ampirik dağılımı.

Adaylar (P050–P052) bunları geçmek zorunda.
"""

from __future__ import annotations

from typing import Any

import numpy as np
import polars as pl

from gymml.data.cohort import AGE_BAND_EDGES, BW_BAND_EDGES, band
from gymml.eval.interface import QuantileGridMixin
from gymml.eval.metrics import ROUNDING_STEP_KG

# DOTS (OpenPowerlifting'in kullandığı formül): 500 / (a·bw⁴ + b·bw³ + c·bw² + d·bw + e).
DOTS = {
    "M": ((-0.0000010930, 0.0007391293, -0.1918759221, 24.0900756, -307.75076), (40.0, 210.0)),
    "F": ((-0.0000010706, 0.0005158568, -0.1126655495, 13.6175032, -57.96288), (40.0, 150.0)),
}


def dots_coefficient(sex: np.ndarray, bw: np.ndarray) -> np.ndarray:
    out = np.empty(len(bw))
    for s, (poly, (lo, hi)) in DOTS.items():
        m = sex == s
        out[m] = 500.0 / np.polyval(poly, np.clip(bw[m], lo, hi))
    return out


def dequantize(y: np.ndarray, seed: int = 0) -> np.ndarray:
    """Kayıtlar 2.5 kg adımlı; ampirik çeyrekler atomlara düşmesin diye ±yarım adım titreştirilir
    (değerlendirmedeki rastgeleleştirilmiş PIT ile aynı varsayım)."""
    rng = np.random.default_rng(seed)
    return y + rng.uniform(-ROUNDING_STEP_KG / 2, ROUNDING_STEP_KG / 2, size=len(y))


def weighted_quantiles(values: np.ndarray, weights: np.ndarray, p: np.ndarray) -> np.ndarray:
    order = np.argsort(values)
    v, w = values[order], weights[order]
    cw = (np.cumsum(w) - 0.5 * w) / w.sum()
    return np.interp(p, cw, v)


class CellEmpirical(QuantileGridMixin):
    """Cinsiyet × yaş bandı × kilo bandı hücresinde ağırlıklı ampirik yüzdelikler.

    Hücrede `min_n`'den az örnek varsa (veya x bant dışındaysa) cinsiyet geneli dağılım kullanılır.
    """

    name = "cell_empirical"

    def __init__(self, min_n: int = 200):
        self.min_n = min_n
        self.cells: dict[tuple[str, str, str], np.ndarray] = {}
        self.fallback: dict[str, np.ndarray] = {}

    @staticmethod
    def _keys(x: pl.DataFrame) -> pl.DataFrame:
        return x.select("sex", band("age", AGE_BAND_EDGES), band("bodyweight_kg", BW_BAND_EDGES))

    def fit(self, df: pl.DataFrame) -> CellEmpirical:
        d = pl.concat([self._keys(df), df.select("value_kg", "weight")], how="horizontal")
        d = d.with_columns(value_kg=pl.Series(dequantize(d["value_kg"].to_numpy())))
        for sex, g in d.group_by("sex"):
            self.fallback[sex[0]] = weighted_quantiles(
                g["value_kg"].to_numpy(), g["weight"].to_numpy(), self.grid_p
            )
        for key, g in d.drop_nulls(["age_band", "bodyweight_kg_band"]).group_by(
            "sex", "age_band", "bodyweight_kg_band"
        ):
            if g.height >= self.min_n:
                self.cells[key] = weighted_quantiles(
                    g["value_kg"].to_numpy(), g["weight"].to_numpy(), self.grid_p
                )
        return self

    def _grid(self, x: pl.DataFrame) -> np.ndarray:
        rows = []
        for sex, a, b in self._keys(x).iter_rows():
            rows.append(self.cells.get((sex, a, b), self.fallback[sex]))
        return np.vstack(rows)

    def params(self, x: pl.DataFrame) -> dict[str, Any]:
        keys = self._keys(x).iter_rows()
        return {"cell_found": [k in self.cells for k in keys]}


class DotsEmpirical(QuantileGridMixin):
    """DOTS puanının cinsiyet başına ampirik dağılımı; yaş kullanılmaz.

    Q_y(p | x) = Q_dots(p | cinsiyet) / dots_katsayısı(cinsiyet, kilo).
    """

    name = "dots_empirical"

    def __init__(self) -> None:
        self.dots_grid: dict[str, np.ndarray] = {}

    def fit(self, df: pl.DataFrame) -> DotsEmpirical:
        sex = df["sex"].to_numpy()
        score = dequantize(df["value_kg"].to_numpy()) * dots_coefficient(
            sex, df["bodyweight_kg"].to_numpy()
        )
        w = df["weight"].to_numpy()
        for s in ("M", "F"):
            m = sex == s
            self.dots_grid[s] = weighted_quantiles(score[m], w[m], self.grid_p)
        return self

    def _grid(self, x: pl.DataFrame) -> np.ndarray:
        sex = x["sex"].to_numpy()
        coef = dots_coefficient(sex, x["bodyweight_kg"].to_numpy())
        base = np.vstack([self.dots_grid[s] for s in sex])
        return base / coef[:, None]

    def params(self, x: pl.DataFrame) -> dict[str, Any]:
        return {
            "dots_coefficient": dots_coefficient(
                x["sex"].to_numpy(), x["bodyweight_kg"].to_numpy()
            ).tolist()
        }
