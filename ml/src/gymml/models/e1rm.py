"""Katman 1 — tekrardan 1RM'e (docs/03-ML-MODEL.md §2, P054).

Bir setin gösterdiği maksimum güç: ``e1RM = w / f(r_eff)``; ``f(r)`` r tekrarın yapılabildiği en
büyük yükün 1RM'e oranıdır ve her ailede ``f(1) = 1`` sağlanır.

- Aday eğri aileleri tek arabirimde (:class:`Curve`): Epley, Brzycki, Lombardi, Mayhew, Wathan ve
  iki parametreli genel biçim ``f(r) = 1 / (1 + ((r − 1)/k)^p)``.
- Kategori parametreleri literatürdeki tekrar–%1RM tablolarına uydurulur
  (``data/e1rm_rep_tables.csv``, kaynaklar ``reports/e1rm_literature.md``) ve
  ``params_draft/e1rm.json``'a yazılır.
- Güven ağırlığı ``c(r_eff)`` ve RIR işleme.
- Kendi kendini denetleyen kayıp (kullanıcı-hareket-pencere içi log e1RM varyansı) ve eğitimi;
  P094'te gerçek veriyle çalışacak, burada yalnızca sentetik veriyle test edilir.

Çalıştırma: ``uv run python -m gymml.models.e1rm`` -> karşılaştırma tablosu + params taslağı.
"""

from __future__ import annotations

import argparse
import json
from collections.abc import Callable, Mapping, Sequence
from dataclasses import dataclass, field
from pathlib import Path

import numpy as np
import polars as pl
from scipy.optimize import minimize

from gymml.utils.config import ML_ROOT

REP_TABLES = ML_ROOT / "data/e1rm_rep_tables.csv"
PARAMS_DRAFT = ML_ROOT / "params_draft/e1rm.json"

# Bu tekrar sayısının üstünde güven 0'dır; eğri değeri de burada kırpılır
# (Brzycki r = a + 1'de sıfırlanır).
R_MAX = 30.0

CATEGORIES = ("lower_compound", "upper_push", "upper_pull", "isolation", "general")
DEFAULT_CATEGORY = "general"

# Katalog `movement_pattern` (schema_4) -> eğri kategorisi. Listede olmayan desenler `general` alır.
PATTERN_CATEGORY: dict[str, str] = {
    "squat": "lower_compound",
    "hip_hinge": "lower_compound",
    "horizontal_push": "upper_push",
    "vertical_push": "upper_push",
    "horizontal_pull": "upper_pull",
    "vertical_pull": "upper_pull",
}


def category_for_pattern(movement_pattern: str | None) -> str:
    """Katalog hareket desenini eğri kategorisine eşler (``isolation_*`` -> ``isolation``)."""
    if movement_pattern is None:
        return DEFAULT_CATEGORY
    if movement_pattern.startswith("isolation_"):
        return "isolation"
    return PATTERN_CATEGORY.get(movement_pattern, DEFAULT_CATEGORY)


# --------------------------------------------------------------------------------------------------
# Eğri aileleri
# --------------------------------------------------------------------------------------------------

ArrayLike = float | np.ndarray | Sequence[float]


def _general(r: np.ndarray, k: float, p: float) -> np.ndarray:
    return 1.0 / (1.0 + (np.maximum(r - 1.0, 0.0) / k) ** p)


def _epley(r: np.ndarray, k: float) -> np.ndarray:
    # Standart Epley (w·(1 + r/k)) f(1) = 1/(1 + 1/k) ≠ 1 verir;
    # (r − 1) ile düzeltilmiş hali = genel biçim, p = 1.
    return 1.0 / (1.0 + (r - 1.0) / k)


def _brzycki(r: np.ndarray, a: float) -> np.ndarray:
    # f(r) = (a + 1 − r)/a; f(1) = 1 zaten sağlanır. r ≤ R_MAX < a + 1 aralığında pozitif.
    return (a + 1.0 - r) / a


def _lombardi(r: np.ndarray, b: float) -> np.ndarray:
    # e1RM = w·r^b  ->  f(r) = r^(−b); f(1) = 1 zaten sağlanır.
    return r ** (-b)


def _exponential(asymptote: float, amplitude: float) -> Callable[[np.ndarray, float], np.ndarray]:
    # Mayhew/Wathan: %1RM = A + B·e^(−c·r). Ham haliyle f(1) ≠ 1; f(1)'e bölünerek normalleştirilir.
    def f(r: np.ndarray, c: float) -> np.ndarray:
        g = asymptote + amplitude * np.exp(-c * r)
        return g / (asymptote + amplitude * np.exp(-c))

    return f


@dataclass(frozen=True)
class Family:
    name: str
    fn: Callable[..., np.ndarray]
    param_names: tuple[str, ...]
    # Yaygın (ikincil kaynaklarda aktarılan) sabitler; yalnızca başlangıç değeri, birincil kaynakla
    # doğrulanmadı (bkz. reports/e1rm_literature.md §1). Skorlamada uydurulmuş değerler kullanılır.
    defaults: tuple[float, ...]
    bounds: tuple[tuple[float, float], ...]


FAMILIES: dict[str, Family] = {
    "general": Family("general", _general, ("k", "p"), (30.0, 1.0), ((1.0, 500.0), (0.3, 3.0))),
    "epley": Family("epley", _epley, ("k",), (30.0,), ((1.0, 500.0),)),
    "brzycki": Family("brzycki", _brzycki, ("a",), (36.0,), ((R_MAX + 0.5, 500.0),)),
    "lombardi": Family("lombardi", _lombardi, ("b",), (0.10,), ((0.001, 1.0),)),
    "mayhew": Family("mayhew", _exponential(52.2, 41.9), ("c",), (0.055,), ((0.001, 1.0),)),
    "wathan": Family("wathan", _exponential(48.8, 53.8), ("c",), (0.075,), ((0.001, 1.0),)),
}


@dataclass(frozen=True)
class Curve:
    """Tek arabirim: ``fraction(r)`` = r tekrarlık maksimum yükün 1RM'e oranı; ``f(1) = 1``."""

    family: str
    params: Mapping[str, float] = field(default_factory=dict)

    def __post_init__(self) -> None:
        fam = FAMILIES[self.family]
        missing = set(fam.param_names) - set(self.params)
        if missing:
            raise ValueError(f"{self.family}: eksik parametre {sorted(missing)}")

    @classmethod
    def default(cls, family: str) -> Curve:
        fam = FAMILIES[family]
        return cls(family, dict(zip(fam.param_names, fam.defaults, strict=True)))

    @property
    def theta(self) -> tuple[float, ...]:
        return tuple(float(self.params[n]) for n in FAMILIES[self.family].param_names)

    def fraction(self, r: ArrayLike) -> np.ndarray:
        r = np.clip(np.asarray(r, dtype=float), 1.0, R_MAX)
        return FAMILIES[self.family].fn(r, *self.theta)

    def e1rm(self, weight: ArrayLike, r_eff: ArrayLike) -> np.ndarray:
        return np.asarray(weight, dtype=float) / self.fraction(r_eff)

    def reps_at(self, pct: ArrayLike, r_grid: np.ndarray | None = None) -> np.ndarray:
        """Ters eğri: verilen %1RM'de yapılabilecek tekrar (sayısal, 1..R_MAX aralığında)."""
        grid = np.linspace(1.0, R_MAX, 2901) if r_grid is None else r_grid
        f = self.fraction(grid)
        # f azalan; np.interp artan x ister.
        return np.interp(np.asarray(pct, dtype=float), f[::-1], grid[::-1])


# --------------------------------------------------------------------------------------------------
# Güven ağırlığı ve set tahmini
# --------------------------------------------------------------------------------------------------

DEFAULT_CONFIDENCE: dict[str, list[float] | float] = {
    # §2: 1–5 tekrar 1.0; 12'de 0.6; 20'de 0.25; 30'da ve üstünde 0 (aralarda doğrusal).
    "knots_reps": [5.0, 12.0, 20.0, R_MAX],
    "knots_conf": [1.0, 0.6, 0.25, 0.0],
    "no_rir_factor": 0.85,
}


def confidence(
    r_eff: ArrayLike,
    rir_known: bool | np.ndarray = True,
    is_warmup: bool | np.ndarray = False,
    cfg: Mapping[str, object] = DEFAULT_CONFIDENCE,
) -> np.ndarray:
    """``c(r_eff)``: parçalı doğrusal; RIR yoksa ×``no_rir_factor``; ısınma setleri 0."""
    xs = np.asarray(cfg["knots_reps"], dtype=float)
    ys = np.asarray(cfg["knots_conf"], dtype=float)
    r = np.asarray(r_eff, dtype=float)
    c = np.interp(r, xs, ys, left=ys[0], right=0.0)
    c = np.where(r >= xs[-1], 0.0, c)
    c = c * np.where(np.asarray(rir_known), 1.0, float(cfg["no_rir_factor"]))  # type: ignore[arg-type]
    return np.where(np.asarray(is_warmup), 0.0, c)


@dataclass(frozen=True)
class SetEstimate:
    e1rm_kg: float
    confidence: float
    r_eff: float


def effective_reps(reps: int, rir: float | None) -> float:
    """``r_eff = tekrar + RIR``.

    RIR yoksa 0 varsayılmaz: e1RM alt sınır kabul edilir, güven düşer.
    """
    if reps < 1:
        raise ValueError("tekrar >= 1 olmalı")
    if rir is not None and rir < 0:
        raise ValueError("RIR >= 0 olmalı")
    return float(reps) + (0.0 if rir is None else float(rir))


def estimate_set(
    weight_kg: float,
    reps: int,
    curve: Curve,
    rir: float | None = None,
    is_warmup: bool = False,
    cfg: Mapping[str, object] = DEFAULT_CONFIDENCE,
) -> SetEstimate:
    if weight_kg <= 0:
        raise ValueError("ağırlık > 0 olmalı")
    r_eff = effective_reps(reps, rir)
    e = float(curve.e1rm(weight_kg, r_eff))
    c = float(confidence(r_eff, rir is not None, is_warmup, cfg))
    return SetEstimate(e, c, r_eff)


# --------------------------------------------------------------------------------------------------
# Literatür tablolarına uydurma
# --------------------------------------------------------------------------------------------------


@dataclass(frozen=True)
class FitResult:
    curve: Curve
    rmse_log: float  # kök ortalama kare log(f(r_obs)) − log(%1RM) ≈ göreli e1RM hatası
    max_abs_log: float
    n_points: int


def _optimize(
    family: str, loss: Callable[[np.ndarray], float], init: Sequence[float] | None = None
) -> np.ndarray:
    fam = FAMILIES[family]
    lo = np.log([b[0] for b in fam.bounds])
    hi = np.log([b[1] for b in fam.bounds])
    x0 = np.clip(np.log(np.asarray(init if init is not None else fam.defaults, float)), lo, hi)

    def obj(u: np.ndarray) -> float:
        return loss(np.exp(u))

    best = minimize(obj, x0, method="L-BFGS-B", bounds=list(zip(lo, hi, strict=True)))
    # Yerel minimuma karşı birkaç başlangıç noktası daha dene.
    for start in (lo + 0.25 * (hi - lo), lo + 0.5 * (hi - lo), lo + 0.75 * (hi - lo)):
        res = minimize(obj, start, method="L-BFGS-B", bounds=list(zip(lo, hi, strict=True)))
        if res.fun < best.fun:
            best = res
    return np.exp(best.x)


def fit_rep_table(
    family: str,
    reps: ArrayLike,
    pct: ArrayLike,
    weights: ArrayLike | None = None,
) -> FitResult:
    """Tekrar–%1RM noktalarına aileyi uydurur: Σ w·(log f(r) − log %1RM)² en küçüklenir."""
    r = np.asarray(reps, float)
    y = np.log(np.asarray(pct, float))
    w = np.ones_like(r) if weights is None else np.asarray(weights, float)
    fam = FAMILIES[family]

    def resid(theta: np.ndarray) -> np.ndarray:
        return np.log(fam.fn(np.clip(r, 1.0, R_MAX), *theta)) - y

    def loss(theta: np.ndarray) -> float:
        e = resid(theta)
        return float(np.sum(w * e * e) / np.sum(w)) if np.all(np.isfinite(e)) else 1e6

    theta = _optimize(family, loss)
    e = resid(theta)
    curve = Curve(family, dict(zip(fam.param_names, map(float, theta), strict=True)))
    return FitResult(curve, float(np.sqrt(loss(theta))), float(np.max(np.abs(e))), len(r))


def load_rep_tables(path: Path = REP_TABLES) -> pl.DataFrame:
    """Ham literatür satırları (kaynaklar reports/e1rm_literature.md)."""
    return pl.read_csv(path)


def se_log_reps(df: pl.DataFrame) -> np.ndarray:
    """Ortalama tekrarın log ölçekteki standart hatası: %95 GA'dan ya da SD/√n'den."""
    from_ci = (np.log(df["ci_high"].to_numpy()) - np.log(df["ci_low"].to_numpy())) / (2 * 1.96)
    from_sd = df["sd"].to_numpy() / np.sqrt(df["n"].to_numpy()) / df["mean_reps"].to_numpy()
    se = np.where(np.isfinite(from_ci), from_ci, from_sd)
    if not np.all(np.isfinite(se)):
        raise ValueError("her satırda ci_low/ci_high ya da sd/n olmalı")
    return se


def point_weights(df: pl.DataFrame) -> np.ndarray:
    """Kaynak içinde ters varyans (1/se²), her kaynağa kategori içinde eşit toplam ağırlık."""
    df = df.with_columns(pl.Series("_w", 1.0 / df["se_log"].to_numpy() ** 2))
    total = df.group_by("source").agg(pl.col("_w").sum().alias("_tot"))
    return (
        df.join(total, on="source", how="left")
        .select(pl.col("_w") / pl.col("_tot"))["_w"]
        .to_numpy()
    )


# Uydurma kuralı (reports/e1rm_literature.md §3):
# - Nuzzo 2024 meta-regresyonu, hareketini içerdiği kategoride tek referanstır (bench -> upper_push,
#   leg press -> lower_compound, tüm hareketler -> general).
# - Tek çalışmalar farklı tempo/protokol kullanır (Ferrari 2017: 2 s/2 s metronom, aynı %1RM'de
#   Nuzzo bench'ten ~%20 az tekrar). Bu yüzden yalnızca ÇALIŞMA İÇİ KARŞITLIK olarak girerler:
#   hareketin tekrarı, aynı çalışmadaki referans hareketin (bench) tekrarına oranlanır ve Nuzzo
#   bench ile ölçeklenir.
# - Diğer tek çalışma satırları (Hatfield 2006) uydurmaya girmez; çapraz denetim olarak raporlanır.
REFERENCE_SOURCE = "nuzzo2024"
CONTRAST_SOURCES = {"ferrari2017": "bench_press"}


def fit_table(df: pl.DataFrame) -> pl.DataFrame:
    """Ham literatür satırlarından uydurmaya girecek noktaları kurar (kolonlar: category, source,
    exercise, pct_1rm, mean_reps, se_log)."""
    df = df.with_columns(pl.Series("se_log", se_log_reps(df)))
    ref = df.filter((pl.col("source") == REFERENCE_SOURCE) & (pl.col("category") != "general"))
    out = [df.filter(pl.col("source") == REFERENCE_SOURCE)]
    for src, ref_ex in CONTRAST_SOURCES.items():
        study = df.filter(pl.col("source") == src)
        base = study.filter(pl.col("exercise") == ref_ex).select(
            "group", "pct_1rm", pl.col("mean_reps").alias("_b"), pl.col("se_log").alias("_bse")
        )
        nz = ref.filter(pl.col("exercise") == ref_ex).select(
            "pct_1rm", pl.col("mean_reps").alias("_n"), pl.col("se_log").alias("_nse")
        )
        derived = (
            study.filter(pl.col("exercise") != ref_ex)
            .join(base, on=["group", "pct_1rm"], how="inner")
            .join(nz, on="pct_1rm", how="inner")
            .with_columns(
                (pl.col("mean_reps") * pl.col("_n") / pl.col("_b")).alias("mean_reps"),
                (pl.col("se_log") ** 2 + pl.col("_bse") ** 2 + pl.col("_nse") ** 2)
                .sqrt()
                .alias("se_log"),
            )
        )
        if derived.height != study.filter(pl.col("exercise") != ref_ex).height:
            raise ValueError(f"{src}: karşıtlık satırları referansla eşleşmedi")
        out.append(derived.select(df.columns))
    cols = ["category", "source", "exercise", "group", "pct_1rm", "mean_reps", "se_log"]
    return pl.concat([d.select(cols) for d in out]).filter(pl.col("mean_reps") <= R_MAX)


def cross_check(df: pl.DataFrame, curves: Mapping[str, Curve]) -> pl.DataFrame:
    """Uydurmaya girmeyen tek çalışma satırlarında log(f(r_gözlenen)) − log(%1RM).

    Pozitif değer: eğri o hareketin e1RM'ini düşük tahmin eder (≈ göreli hata).
    """
    rows = df.filter(
        (pl.col("source") != REFERENCE_SOURCE) & ~pl.col("source").is_in(list(CONTRAST_SOURCES))
    )
    resid = [
        float(np.log(curves[c].fraction(r)) - np.log(p))
        for c, r, p in rows.select("category", "mean_reps", "pct_1rm").iter_rows()
    ]
    return rows.select("category", "source", "exercise", "pct_1rm", "mean_reps").with_columns(
        pl.Series("resid_log", resid)
    )


def fit_categories(df: pl.DataFrame, family: str = "general") -> dict[str, FitResult]:
    """``df``: :func:`fit_table` çıktısı."""
    out: dict[str, FitResult] = {}
    for cat in CATEGORIES:
        sub = df.filter(pl.col("category") == cat)
        if sub.height == 0:
            continue
        out[cat] = fit_rep_table(
            family, sub["mean_reps"].to_numpy(), sub["pct_1rm"].to_numpy(), point_weights(sub)
        )
    return out


def compare_families(df: pl.DataFrame) -> dict[str, dict[str, dict[str, float]]]:
    """Her aile × kategori: uydurulmuş parametre, ağırlıklı log-RMSE; bir de yaygın sabitlerle hata.

    ``df``: :func:`fit_table` çıktısı."""
    table: dict[str, dict[str, dict[str, float]]] = {}
    for fam in FAMILIES:
        table[fam] = {}
        fits = fit_categories(df, fam)
        for cat, fit in fits.items():
            sub = df.filter(pl.col("category") == cat)
            w = point_weights(sub)
            e0 = np.log(Curve.default(fam).fraction(sub["mean_reps"].to_numpy())) - np.log(
                sub["pct_1rm"].to_numpy()
            )
            table[fam][cat] = {
                **{k: round(v, 4) for k, v in fit.curve.params.items()},
                "rmse_log_fitted": round(fit.rmse_log, 4),
                "rmse_log_default": round(float(np.sqrt(np.sum(w * e0 * e0) / np.sum(w))), 4),
            }
    return table


# --------------------------------------------------------------------------------------------------
# Kendi kendini denetleyen kayıp (§2) — gerçek veriyle P094'te
# --------------------------------------------------------------------------------------------------


def within_window_loss(
    family: str,
    theta: Sequence[float],
    group: np.ndarray,
    weight: np.ndarray,
    r_eff: np.ndarray,
    conf: np.ndarray | None = None,
) -> float:
    """Kullanıcı-hareket-pencere grubu içinde güven ağırlıklı log e1RM varyansının ortalaması.

    Doğru eğri aynı gruptaki farklı tekrar sayılı setlerin hepsinden aynı e1RM'i üretir. Gruplar
    önceden (ör. 14 günlük pencerelerle) atanır; tek setli gruplar katkı vermez.
    """
    c = np.ones_like(weight, dtype=float) if conf is None else np.asarray(conf, float)
    f = FAMILIES[family].fn(np.clip(r_eff, 1.0, R_MAX), *theta)
    if not np.all(np.isfinite(f)) or np.any(f <= 0):
        return 1e6
    y = np.log(weight) - np.log(f)
    _, inv = np.unique(group, return_inverse=True)
    sw = np.bincount(inv, weights=c)
    mean = np.bincount(inv, weights=c * y) / np.where(sw > 0, sw, 1.0)
    dev = c * (y - mean[inv]) ** 2
    return float(np.sum(dev) / np.sum(c))


def fit_self_supervised(
    family: str,
    group: np.ndarray,
    weight: np.ndarray,
    r_eff: np.ndarray,
    conf: np.ndarray | None = None,
    init: Sequence[float] | None = None,
) -> Curve:
    group = np.asarray(group)
    weight = np.asarray(weight, float)
    r_eff = np.asarray(r_eff, float)
    _, inv, counts = np.unique(group, return_inverse=True, return_counts=True)
    keep = counts[inv] >= 2
    if not np.any(keep):
        raise ValueError("en az iki setli grup gerekli")
    args = (
        group[keep],
        weight[keep],
        r_eff[keep],
        None if conf is None else np.asarray(conf)[keep],
    )
    theta = _optimize(family, lambda t: within_window_loss(family, t, *args), init)
    fam = FAMILIES[family]
    return Curve(family, dict(zip(fam.param_names, map(float, theta), strict=True)))


# --------------------------------------------------------------------------------------------------
# Params taslağı
# --------------------------------------------------------------------------------------------------


def build_params(raw: pl.DataFrame) -> dict[str, object]:
    df = fit_table(raw)
    fits = fit_categories(df, "general")
    checks = cross_check(raw, {c: f.curve for c, f in fits.items()})
    cats: dict[str, object] = {}
    for cat, fit in fits.items():
        sub = df.filter(pl.col("category") == cat)
        cats[cat] = {
            "k": round(fit.curve.params["k"], 4),
            "p": round(fit.curve.params["p"], 4),
            "fit_rmse_log": round(fit.rmse_log, 4),
            "fit_max_abs_log": round(fit.max_abs_log, 4),
            "n_points": fit.n_points,
            "sources": sorted(set(sub["source"].to_list())),
            "exercises": sorted(set(sub["exercise"].to_list())),
        }
    return {
        "module": "e1rm",
        "step": "P054",
        "family": "general",
        "formula": "e1rm = w / f(r_eff); f(r) = 1 / (1 + ((r - 1) / k)^p); r_eff = reps + RIR",
        "r_max": R_MAX,
        "default_category": DEFAULT_CATEGORY,
        "pattern_category": {**PATTERN_CATEGORY, "isolation_*": "isolation"},
        "categories": cats,
        "cross_check": [
            {**r, "resid_log": round(r["resid_log"], 4)} for r in checks.iter_rows(named=True)
        ],
        "confidence": DEFAULT_CONFIDENCE,
        "warmup_sets": "excluded",
        "source_table": "ml/data/e1rm_rep_tables.csv",
        "report": "ml/reports/e1rm_literature.md",
    }


def main(argv: list[str] | None = None) -> None:
    ap = argparse.ArgumentParser(description="P054: 1RM eğrilerini literatür tablolarına uydur")
    ap.add_argument("--out", type=Path, default=PARAMS_DRAFT)
    args = ap.parse_args(argv)
    raw = load_rep_tables()
    print(json.dumps(compare_families(fit_table(raw)), indent=2))
    params = build_params(raw)
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(params, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(f"yazıldı: {args.out}")


if __name__ == "__main__":
    main()
