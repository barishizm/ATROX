"""Tüm adayların (P050–P052) ve temel çizgilerin uyduğu ortak arabirim.

Bir model tek bir kaldırış için eğitilir. Girdi `x` en az `sex` (M/F), `age` ve `bodyweight_kg`
sütunlarını içeren bir polars DataFrame'dir. Hedef `value_kg`, örnek ağırlığı `weight` sütunudur.
"""

from __future__ import annotations

from typing import Any, Protocol, runtime_checkable

import numpy as np
import polars as pl

X_COLUMNS: tuple[str, ...] = ("sex", "age", "bodyweight_kg")

# Değerlendirme çeyrekleri: 0.05, 0.10, …, 0.95 (19 adet), docs/03-ML-MODEL.md §4.3.
QUANTILES: np.ndarray = np.round(np.arange(1, 20) / 20, 2)


@runtime_checkable
class DistributionModel(Protocol):
    name: str

    def fit(self, df: pl.DataFrame) -> DistributionModel:
        """`df`: X_COLUMNS + `value_kg` + `weight`. Kendini döndürür."""
        ...

    def quantile(self, x: pl.DataFrame, q: np.ndarray) -> np.ndarray:
        """(len(x), len(q)) boyutunda, her satırda q'da azalmayan kg değerleri."""
        ...

    def cdf(self, x: pl.DataFrame, y: np.ndarray) -> np.ndarray:
        """P(Y ≤ y | x), (len(x),) boyutunda, [0, 1] içinde."""
        ...

    def params(self, x: pl.DataFrame) -> dict[str, Any]:
        """Satır başına dağılım parametreleri (modele özgü; rapor ve dışa aktarım için)."""
        ...


class QuantileGridMixin:
    """Bir ince çeyrek ızgarasından (`_grid(x)`) `quantile` ve `cdf` türeten yardımcı.

    Izgara dışındaki olasılıklar uç noktalara kırpılır; CDF ızgara arasında doğrusal.
    """

    grid_p: np.ndarray = np.round(np.arange(1, 200) / 200, 3)  # 0.005 … 0.995

    def _grid(self, x: pl.DataFrame) -> np.ndarray:  # (n, len(grid_p))
        raise NotImplementedError

    def quantile(self, x: pl.DataFrame, q: np.ndarray) -> np.ndarray:
        return grid_quantile(self._grid(x), self.grid_p, q)

    def cdf(self, x: pl.DataFrame, y: np.ndarray) -> np.ndarray:
        return grid_cdf(self._grid(x), self.grid_p, y)


def grid_quantile(g: np.ndarray, grid_p: np.ndarray, q: np.ndarray) -> np.ndarray:
    """Izgara (n, G) üzerinde doğrusal enterpolasyonla (n, len(q)) çeyrekler."""
    g = np.maximum.accumulate(g, axis=1)
    q = np.clip(np.asarray(q, dtype=float), grid_p[0], grid_p[-1])
    j = np.clip(np.searchsorted(grid_p, q, side="right") - 1, 0, len(grid_p) - 2)
    t = (q - grid_p[j]) / (grid_p[j + 1] - grid_p[j])
    return g[:, j] + t * (g[:, j + 1] - g[:, j])


def grid_cdf(g: np.ndarray, grid_p: np.ndarray, y: np.ndarray) -> np.ndarray:
    """Izgara (n, G) üzerinde P(Y ≤ y); ızgara dışı 0/1, arası doğrusal."""
    g = np.maximum.accumulate(g, axis=1)
    y = np.asarray(y, dtype=float)[:, None]
    k = (g <= y).sum(axis=1)  # y'den küçük-eşit ızgara noktası sayısı
    n, G = g.shape
    out = np.where(k == 0, 0.0, 1.0)
    mid = (k > 0) & (k < G)
    i = np.arange(n)[mid]
    lo, hi = k[mid] - 1, k[mid]
    span = g[i, hi] - g[i, lo]
    t = np.where(span > 0, (y[mid, 0] - g[i, lo]) / np.where(span > 0, span, 1.0), 0.0)
    out[mid] = grid_p[lo] + t * (grid_p[hi] - grid_p[lo])
    return out
