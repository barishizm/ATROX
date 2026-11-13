"""Ortak değerlendirme koşumu: bir model fabrikasını üç kaldırışta eğitir, doğrulamada ölçer.

Test kümesi burada KULLANILMAZ; yalnızca P053'te nihai yapılandırmalarla bir kez bakılır.
"""

from __future__ import annotations

import time
from collections.abc import Callable
from dataclasses import dataclass

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402
import numpy as np  # noqa: E402
import polars as pl  # noqa: E402

from gymml.data.cohort import LIFTS  # noqa: E402
from gymml.eval import external, metrics, sanity  # noqa: E402
from gymml.eval.data import DataSpec, ensure_splits, load_lift, splits_digest  # noqa: E402
from gymml.eval.interface import DistributionModel  # noqa: E402


@dataclass
class LiftResult:
    lift: str
    model: DistributionModel
    metrics: dict
    sanity: list[sanity.SanityResult]
    external: pl.DataFrame
    fit_seconds: float


def evaluate_factory(
    factory: Callable[[], DistributionModel],
    spec: DataSpec | None = None,
    split: str = "val",
    lifts: tuple[str, ...] = LIFTS,
) -> list[LiftResult]:
    if split == "test":
        raise ValueError("test kümesi yalnızca P053 nihai değerlendirmesinde kullanılır")
    spec = spec or DataSpec()
    out = []
    for lift in lifts:
        train = load_lift(lift, "train", spec)
        ev = load_lift(lift, split, spec)
        t0 = time.perf_counter()
        model = factory().fit(train)
        fit_s = time.perf_counter() - t0
        out.append(
            LiftResult(
                lift=lift,
                model=model,
                metrics=metrics.evaluate(model, ev),
                sanity=sanity.run_all(model, lift),
                external=external.compare(model, lift, ev),
                fit_seconds=fit_s,
            )
        )
    return out


def split_info() -> dict:
    s = ensure_splits()
    counts = dict(s.group_by("split").len().iter_rows())
    return {"digest": splits_digest(s), "athletes": counts}


def summary_table(results: dict[str, list[LiftResult]]) -> pl.DataFrame:
    rows = []
    for name, rs in results.items():
        for r in rs:
            m = r.metrics
            rows.append(
                {
                    "model": name,
                    "lift": r.lift,
                    "n_val": m["n"],
                    "pinball_kg": m["pinball"],
                    "crps_kg": m["crps"],
                    "pit_ks": m["pit_ks"],
                    "katman": m["strata"],
                    "katman_max_pp": m["strata_max_dev_pp"],
                    "2pp_üstü_katman": m["strata_failing"],
                    "bant_dışı_katman": m["strata_failing_noise_aware"],
                    "kalibrasyon_kapısı": "✅" if m["coverage_gate_pass"] else "❌",
                    "akıl_sağlığı": f"{sum(s.passed for s in r.sanity)}/{len(r.sanity)}",
                }
            )
    return pl.DataFrame(rows)


def plot_pit(results: dict[str, list[LiftResult]], path) -> None:
    names = list(results)
    fig, axes = plt.subplots(len(names), len(LIFTS), figsize=(12, 3 * len(names)), squeeze=False)
    for i, name in enumerate(names):
        for j, r in enumerate(results[name]):
            h = np.array(r.metrics["pit_hist"])
            axes[i, j].bar(np.arange(len(h)) / len(h), h, width=1 / len(h), align="edge")
            axes[i, j].axhline(1 / len(h), color="k", lw=0.8)
            axes[i, j].set_title(f"{name} · {r.lift} (KS {r.metrics['pit_ks']:.3f})")
            axes[i, j].set_ylim(0, 0.2)
    fig.tight_layout()
    fig.savefig(path, dpi=110)
    plt.close(fig)


def plot_percentile_curves(
    results: dict[str, list[LiftResult]], path, sex: str = "M", age: float = 30.0
) -> None:
    """5/25/50/75/95 yüzdelik eğrileri, kiloya karşı (adaylar arası görsel karşılaştırma)."""
    qs = np.array([0.05, 0.25, 0.5, 0.75, 0.95])
    bws = np.arange(45.0, 160.0, 1.0)
    x = pl.DataFrame({"sex": [sex] * len(bws), "age": [age] * len(bws), "bodyweight_kg": bws})
    names = list(results)
    fig, axes = plt.subplots(1, len(LIFTS), figsize=(15, 4.5))
    styles = ["-", "--", ":", "-."]
    for j, lift in enumerate(LIFTS):
        for i, name in enumerate(names):
            r = next(r for r in results[name] if r.lift == lift)
            q = r.model.quantile(x, qs)
            for k in range(len(qs)):
                axes[j].plot(
                    bws,
                    q[:, k],
                    styles[i % 4],
                    color=f"C{k}",
                    label=f"{name} P{int(qs[k] * 100)}" if j == 0 else None,
                )
        axes[j].set_title(f"{lift} · {sex}, {age:g} yaş")
        axes[j].set_xlabel("vücut ağırlığı (kg)")
    axes[0].legend(fontsize=6, ncol=2)
    fig.tight_layout()
    fig.savefig(path, dpi=110)
    plt.close(fig)
