"""P051 · Aday B — LightGBM çeyreklik regresyon (docs/03-ML-MODEL.md §4.2).

Kaldırış başına 19 pinball-kayıplı LightGBM (q = 0.05…0.95); girdiler: cinsiyet, yaş, kilo,
log-kilo.
- Hedef: standartlaştırılmış log-yük z = (log y − μ) / σ. Çeyrekler monoton dönüşümle korunur;
  log ölçek çarpımsal kilo/yaş etkilerine uyar ve ağaç adımlarını ölçeksiz kılar.
- LightGBM yerleşik `quantile` hedefinde `monotone_constraints`'ı reddeder (yaprak değerlerini
  ağaç kurulduktan sonra yeniden hesapladığı için). Bu yüzden pinball kaybı özel hedef olarak
  yazıldı (gradyan w·(1{z<f} − q), Hessian w); başlangıç skoru ağırlıklı ampirik çeyrek. Kısıtlı
  ve kısıtsız sürümler aynı hedefi kullanır, yalnızca kısıt farklıdır.
- `monotone=True`: kilo ve log-kilo üzerinde artan monotonluk kısıtı (beklenen kaldırış kiloyla
  azalmaz).
- Çeyrek kesişmesi satır bazında yeniden sıralama ile düzeltilir (izotonik yeniden sıralama; aynı
  kümeyi verir, Chernozhukov ve ark. 2010). Düzeltmeden önceki kesişme oranı `crossing_rate`.
- Kuyruk (q < 0.05, q > 0.95): log ölçekte doğrusal ekstrapolasyon — log Q(p), lojit(p)'ye karşı
  en dıştaki 4 çeyreğin en küçük kareler eğimiyle uzatılır (eğim genel 5–95 eğiminin 0.25–2
  katına kırpılır). ZAYIFLIK: kuyruk biçimi
  veriden öğrenilmez; yalnızca dış çeyreklerin eğimini taşır, bu yüzden aşırı skorlar (P1–P4,
  P96–P99) kaba ve gürültülüdür; eğim kiloyla değiştiği için kuyrukta kiloda monotonluk garanti
  değildir.
- Çeyreklerden sürekli CDF: lojit(p) ölçeğinde 19 çeyrek arasında doğrusal enterpolasyonla ince
  ızgara (0.005…0.995), ardından `QuantileGridMixin` ile ızgara üzerinde doğrusal CDF.
"""

from __future__ import annotations

import os
import sys
import time
from typing import Any

if sys.platform == "darwin":
    # macOS'ta LightGBM Homebrew libomp'u, torch kendi libomp kopyasını yükler; ikisi aynı süreçte
    # (ör. pytest, P053 yarışması) OpenMP'yi "zaten başlatılmış" hatasıyla durdurur. Linux'ta ikisi
    # de libgomp kullandığından gerekmez. Bilinen geçici çözüm; P053'te ayrı süreçler düşünülebilir.
    os.environ.setdefault("KMP_DUPLICATE_LIB_OK", "TRUE")

import lightgbm as lgb  # noqa: E402
import numpy as np  # noqa: E402
import polars as pl  # noqa: E402

from gymml.eval.interface import QUANTILES, QuantileGridMixin  # noqa: E402
from gymml.models.baselines import dequantize, weighted_quantiles  # noqa: E402

FEATURES = ("sex_m", "age", "bodyweight_kg", "log_bodyweight")
MONOTONE = (0, 0, 1, 1)
NUM_ROUNDS = 400
DEFAULT_PARAMS: dict[str, Any] = {
    "learning_rate": 0.1,
    "num_leaves": 15,
    "min_data_in_leaf": 200,
    "bagging_fraction": 0.8,
    "bagging_freq": 1,
    "num_threads": 0,
    "verbose": -1,
}


def features(x: pl.DataFrame) -> np.ndarray:
    bw = x["bodyweight_kg"].to_numpy().astype(float)
    sex_m = (x["sex"].to_numpy() == "M").astype(float)
    return np.column_stack([sex_m, x["age"].to_numpy().astype(float), bw, np.log(bw)])


def pinball_objective(q: float):
    """Özel pinball hedefi: dL/df = w·(1{z < f} − q); sabit Hessian w.

    Yaprak değeri böylece ağırlıklı işaret ortalaması olur (adım ≤ öğrenme oranı × max(q, 1 − q)).
    """

    def fobj(preds: np.ndarray, data: lgb.Dataset) -> tuple[np.ndarray, np.ndarray]:
        z, w = data.get_label(), data.get_weight()
        if w is None:  # LightGBM tümü 1 olan ağırlıkları saklamaz
            w = np.ones_like(z)
        return w * ((z < preds).astype(float) - q), w

    return fobj


TAIL_POINTS = 4  # kuyruk eğimi için her uçta kullanılan çeyrek sayısı (0.05–0.20 / 0.80–0.95)
TAIL_SLOPE_BOUNDS = (0.25, 2.0)  # genel 5–95 eğimine göre kırpma


def tail_slopes(lq: np.ndarray, lp: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    """log Q – lojit(p) doğrusunun alt/üst kuyruk eğimleri, satır başına.

    Her uçta en dıştaki `TAIL_POINTS` çeyreğin en küçük kareler eğimi; ağaç gürültüsü tek bir
    komşu farkını patlatabildiği için genel eğimin (5–95) `TAIL_SLOPE_BOUNDS` katına kırpılır.
    """
    k = TAIL_POINTS
    overall = np.maximum((lq[:, -1] - lq[:, 0]) / (lp[-1] - lp[0]), 1e-4)

    def ls(cols: slice) -> np.ndarray:
        xp = lp[cols] - lp[cols].mean()
        yp = lq[:, cols] - lq[:, cols].mean(axis=1, keepdims=True)
        return (yp @ xp) / (xp @ xp)

    lo, hi = TAIL_SLOPE_BOUNDS
    lower = np.clip(ls(slice(0, k)), lo * overall, hi * overall)
    upper = np.clip(ls(slice(-k, None)), lo * overall, hi * overall)
    return lower, upper


def _logit(p: np.ndarray) -> np.ndarray:
    return np.log(p / (1 - p))


class LGBMQuantile(QuantileGridMixin):
    def __init__(
        self, monotone: bool = True, seed: int = 0, num_rounds: int = NUM_ROUNDS, **params: Any
    ):
        self.monotone = monotone
        self.seed = seed
        self.num_rounds = num_rounds
        self.lgb_params = {**DEFAULT_PARAMS, **params}
        self.name = "lgbm_mono" if monotone else "lgbm_free"
        self.models: list[lgb.Booster] = []
        self.init: np.ndarray = np.zeros(len(QUANTILES))
        self.mu, self.sd = 0.0, 1.0
        self.crossing_rate: float = float("nan")

    def fit(self, df: pl.DataFrame) -> LGBMQuantile:
        X = features(df)
        ly = np.log(dequantize(df["value_kg"].to_numpy().astype(float), self.seed))
        w = df["weight"].to_numpy().astype(float)
        self.mu = float(np.average(ly, weights=w))
        self.sd = float(np.sqrt(np.average((ly - self.mu) ** 2, weights=w)))
        z = (ly - self.mu) / self.sd
        self.init = weighted_quantiles(z, w, QUANTILES)
        extra = {"monotone_constraints": list(MONOTONE)} if self.monotone else {}
        self.models = []
        for q, f0 in zip(QUANTILES, self.init, strict=True):
            ds = lgb.Dataset(
                X, z, weight=w, init_score=np.full(len(z), f0), feature_name=list(FEATURES)
            )
            prm = {"objective": pinball_objective(float(q)), "seed": self.seed}
            self.models.append(lgb.train({**prm, **self.lgb_params, **extra}, ds, self.num_rounds))
        self.crossing_rate = self.measure_crossing(df)
        return self

    def raw_quantiles(self, x: pl.DataFrame) -> np.ndarray:
        """Düzeltilmemiş 19 çeyrek (kg), (len(x), 19)."""
        X = features(x)
        pairs = zip(self.models, self.init, strict=True)
        z = np.column_stack([m.predict(X) + f0 for m, f0 in pairs])
        return np.exp(self.mu + self.sd * z)

    def measure_crossing(self, x: pl.DataFrame) -> float:
        """Herhangi bir komşu çeyrek çiftinde kesişen satır oranı (düzeltmeden önce)."""
        return float(np.mean(np.any(np.diff(self.raw_quantiles(x), axis=1) < 0, axis=1)))

    def _grid(self, x: pl.DataFrame) -> np.ndarray:
        qk = np.sort(self.raw_quantiles(x), axis=1)  # yeniden sıralama
        qk = np.maximum(qk, 1.0)  # pozitif kalsın (log kuyruk için)
        lq, lp = np.log(qk), _logit(QUANTILES)
        lo_slope, hi_slope = tail_slopes(lq, lp)
        gp = self.grid_p
        lgp = _logit(gp)
        inner = np.vstack([np.interp(lgp, lp, row) for row in lq])
        lower = lq[:, [0]] + lo_slope[:, None] * (lgp - lp[0])
        upper = lq[:, [-1]] + hi_slope[:, None] * (lgp - lp[-1])
        out = np.where(gp < QUANTILES[0], lower, np.where(gp > QUANTILES[-1], upper, inner))
        return np.exp(out)

    def params(self, x: pl.DataFrame) -> dict[str, Any]:  # type: ignore[override]
        return {"quantiles_kg": np.sort(self.raw_quantiles(x), axis=1).tolist()}

    def size_bytes(self) -> int:
        """19 ağacın metin dökümünün toplam boyutu (bayt; sıkıştırmasız)."""
        return sum(len(m.model_to_string().encode()) for m in self.models)

    def single_inference_ms(self, x: pl.DataFrame, repeats: int = 50) -> float:
        row = x.head(1)
        t0 = time.perf_counter()
        for _ in range(repeats):
            self.quantile(row, QUANTILES)
        return (time.perf_counter() - t0) / repeats * 1000
