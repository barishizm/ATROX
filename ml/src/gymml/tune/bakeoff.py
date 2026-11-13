"""P053 model yarışması: Optuna araması, tohum tekrarı, tek test bakışı, duyarlılık, rapor.

Protokol `reports/bakeoff.md` §1–2'de deneylerden önce yazıldı. Komutlar:

    python -m gymml.tune.bakeoff search --cand A      # 10 deneme, doğrulama kümesi
    python -m gymml.tune.bakeoff final --cand A       # 3 tohum (doğrulama) + tek test bakışı
    python -m gymml.tune.bakeoff sens --cand A        # duyarlılık (doğrulama, tohum 1)
    python -m gymml.tune.bakeoff report               # reports/bakeoff.md §3+

Ara sonuçlar `reports/bakeoff/*.json` (commit edilir, küçük); test kilidi `runs/bakeoff/`.
"""

from __future__ import annotations

import argparse
import dataclasses
import json
import os
import pickle
import sys
import time
from collections.abc import Callable
from dataclasses import dataclass
from typing import Any

if sys.platform == "darwin":  # LightGBM ve torch'un libomp kopyaları (bkz. tests/conftest.py)
    os.environ.setdefault("KMP_DUPLICATE_LIB_OK", "TRUE")

import numpy as np  # noqa: E402
import optuna  # noqa: E402
import polars as pl  # noqa: E402

from gymml.data.cohort import LIFTS, ML_ROOT  # noqa: E402
from gymml.eval import metrics  # noqa: E402
from gymml.eval.data import DataSpec, load_lift  # noqa: E402
from gymml.eval.interface import QUANTILES, DistributionModel  # noqa: E402
from gymml.eval.runner import LiftResult, evaluate_factory  # noqa: E402

OUT = ML_ROOT / "reports/bakeoff"
LOCKS = ML_ROOT / "runs/bakeoff"
N_TRIALS = 10
SAMPLER_SEED = 20260101
SEEDS = (1, 2, 3)
SIZE_LIMIT_BYTES = 1_000_000
LATENCY_LIMIT_MS = 1.0
SIMPLICITY = {"A": 0, "C": 1, "B": 2}  # §4.3 madde 5: A > C > B
NAMES = {"A": "Spline-LMS", "B": "LightGBM", "C": "Sinirsel"}


# ----------------------------------------------------------------------------------------------
# Aday tanımları: arama uzayı ve fabrika
# ----------------------------------------------------------------------------------------------


@dataclass
class Candidate:
    key: str
    suggest: Callable[[optuna.Trial], dict[str, Any]]
    # (yapılandırma, tohum, veri tanımı) -> kaldırış başına model fabrikası
    factory: Callable[[dict[str, Any], int, DataSpec], Callable[[], DistributionModel]]
    size_bytes: Callable[[list[DistributionModel]], int]


def _suggest_a(t: optuna.Trial) -> dict[str, Any]:
    return {
        "family": t.suggest_categorical("family", ["BCCG", "BCPE"]),
        "age_segments": t.suggest_int("age_segments", 6, 16),
        "bw_segments": t.suggest_int("bw_segments", 5, 12),
        "pen_mu": t.suggest_float("pen_mu", 1e-4, 1e-1, log=True),
        "pen_sigma": t.suggest_float("pen_sigma", 1e-3, 1.0, log=True),
        "pen_shape": t.suggest_float("pen_shape", 1e-2, 10.0, log=True),
    }


def _factory_a(cfg: dict[str, Any], seed: int, spec: DataSpec):
    from gymml.models.spline_lms import Penalties, Penalty, SplineLMS, SplineLMSConfig

    def pen(v: float) -> Penalty:
        return Penalty(v, v)

    c = SplineLMSConfig(
        family=cfg["family"],
        age_segments=cfg["age_segments"],
        bw_segments=cfg["bw_segments"],
        penalties=Penalties(
            mu=pen(cfg["pen_mu"]),
            sigma=pen(cfg["pen_sigma"]),
            nu=pen(cfg["pen_shape"]),
            tau=pen(cfg["pen_shape"]),
        ),
        seed=seed,
    )
    return lambda: SplineLMS(c)


def _suggest_b(t: optuna.Trial) -> dict[str, Any]:
    return {
        "num_rounds": t.suggest_int("num_rounds", 50, 400),
        "num_leaves": t.suggest_int("num_leaves", 4, 31),
        "learning_rate": t.suggest_float("learning_rate", 0.03, 0.3, log=True),
        "min_data_in_leaf": t.suggest_int("min_data_in_leaf", 100, 2000, log=True),
        "monotone": t.suggest_categorical("monotone", [True, False]),
    }


def _factory_b(cfg: dict[str, Any], seed: int, spec: DataSpec):
    from gymml.models.lgbm_quantile import LGBMQuantile

    return lambda: LGBMQuantile(
        monotone=cfg["monotone"],
        seed=seed,
        num_rounds=cfg["num_rounds"],
        num_leaves=cfg["num_leaves"],
        learning_rate=cfg["learning_rate"],
        min_data_in_leaf=cfg["min_data_in_leaf"],
    )


def _suggest_c(t: optuna.Trial) -> dict[str, Any]:
    return {
        "width": t.suggest_categorical("width", [32, 48, 64, 96]),
        "depth": t.suggest_int("depth", 2, 3),
        "activation": t.suggest_categorical("activation", ["silu", "tanh"]),
        "weight_decay": t.suggest_float("weight_decay", 1e-6, 1e-2, log=True),
        "lr": t.suggest_float("lr", 1e-3, 1e-2, log=True),
        "head": t.suggest_categorical("head", ["bcpe", "shash"]),
    }


def _factory_c(cfg: dict[str, Any], seed: int, spec: DataSpec):
    from gymml.models.neural import NeuralConfig, NeuralDistributional, load_sbd, shared_factory

    joint = NeuralDistributional(
        NeuralConfig(
            head=cfg["head"],
            hidden=(cfg["width"],) * cfg["depth"],
            activation=cfg["activation"],
            lr=cfg["lr"],
            weight_decay=cfg["weight_decay"],
            seed=seed,
            spec=spec,
        )
    )
    return shared_factory(joint, load_sbd("train", spec))


def _size_pickle(models: list[DistributionModel]) -> int:
    return sum(len(pickle.dumps(m)) for m in models)


def _size_b(models: list[DistributionModel]) -> int:
    return sum(m.size_bytes() for m in models)  # type: ignore[attr-defined]


def _size_c(models: list[DistributionModel]) -> int:
    return models[0].joint.n_params() * 4  # type: ignore[attr-defined]  # ortak gövde, float32


CANDIDATES = {
    "A": Candidate("A", _suggest_a, _factory_a, _size_pickle),
    "B": Candidate("B", _suggest_b, _factory_b, _size_b),
    "C": Candidate("C", _suggest_c, _factory_c, _size_c),
}


# ----------------------------------------------------------------------------------------------
# Ölçüm
# ----------------------------------------------------------------------------------------------


def quick_eval(
    factory: Callable[[], DistributionModel], spec: DataSpec, split: str = "val"
) -> tuple[list[DistributionModel], dict[str, dict]]:
    """Arama için hafif değerlendirme: yalnızca olasılıksal metrikler (akıl sağlığı yok)."""
    models, out = [], {}
    for lift in LIFTS:
        model = factory().fit(load_lift(lift, "train", spec))
        out[lift] = metrics.evaluate(model, load_lift(lift, split, spec))
        models.append(model)
    return models, out


def latency_ms(model: DistributionModel, repeats: int = 50) -> float:
    x = pl.DataFrame({"sex": ["M"], "age": [30.0], "bodyweight_kg": [85.0]})
    model.quantile(x, QUANTILES)
    t0 = time.perf_counter()
    for _ in range(repeats):
        model.quantile(x, QUANTILES)
    return (time.perf_counter() - t0) / repeats * 1000


def _metric_summary(m: dict) -> dict:
    keys = ("n", "pinball", "crps", "pit_ks", "strata", "strata_failing_noise_aware",
            "strata_outside_share", "coverage_gate_pass", "crossing_rate")  # fmt: skip
    return {k: m[k] for k in keys}


def _lift_result_summary(r: LiftResult) -> dict:
    return {
        "metrics": _metric_summary(r.metrics),
        "sanity": [dataclasses.asdict(s) for s in r.sanity],
        "external": r.external.to_dicts(),
        "fit_seconds": r.fit_seconds,
    }


def _write(name: str, obj: Any) -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / name).write_text(json.dumps(obj, indent=2, ensure_ascii=False, default=float))


def _read(name: str) -> Any:
    p = OUT / name
    return json.loads(p.read_text()) if p.exists() else None


# ----------------------------------------------------------------------------------------------
# Adımlar
# ----------------------------------------------------------------------------------------------


def search(key: str, n_trials: int = N_TRIALS) -> dict:
    cand = CANDIDATES[key]
    spec = DataSpec()
    trials: list[dict] = []

    def objective(trial: optuna.Trial) -> float:
        cfg = cand.suggest(trial)
        t0 = time.perf_counter()
        models, per_lift = quick_eval(cand.factory(cfg, SEEDS[0], spec), spec)
        size = cand.size_bytes(models)
        value = float(np.mean([m["pinball"] for m in per_lift.values()]))
        gate = all(m["coverage_gate_pass"] for m in per_lift.values())
        pruned = (not gate) or (key == "B" and size > SIZE_LIMIT_BYTES)
        rec = {
            "number": trial.number, "config": cfg, "pinball_mean": value, "gate": gate,
            "size_bytes": size, "pruned": pruned, "seconds": time.perf_counter() - t0,
            "per_lift": {lift: _metric_summary(m) for lift, m in per_lift.items()},
        }  # fmt: skip
        trials.append(rec)
        _write(f"search_{key}.json", {"candidate": key, "n_trials": n_trials, "trials": trials})
        print(f"[{key}] deneme {trial.number}: pinball {value:.4f} kapı={gate} boyut={size} "
              f"{'BUDANDI' if pruned else ''}", flush=True)  # fmt: skip
        if pruned:
            raise optuna.TrialPruned()
        return value

    optuna.logging.set_verbosity(optuna.logging.WARNING)
    study = optuna.create_study(
        direction="minimize", sampler=optuna.samplers.TPESampler(seed=SAMPLER_SEED)
    )
    study.optimize(objective, n_trials=n_trials)
    kept = [t for t in trials if not t["pruned"]]
    best = min(kept or trials, key=lambda t: t["pinball_mean"])
    result = {
        "candidate": key, "n_trials": n_trials, "trials": trials,
        "best": best, "all_pruned": not kept,
    }  # fmt: skip
    _write(f"search_{key}.json", result)
    return result


def final(key: str) -> dict:
    """En iyi yapılandırma: 3 tohum doğrulama + tek test bakışı (kilitli)."""
    cand = CANDIDATES[key]
    s = _read(f"search_{key}.json")
    if not s or "best" not in s:
        raise SystemExit(f"önce arama: search --cand {key}")
    cfg = s["best"]["config"]
    spec = DataSpec()
    lock = LOCKS / f"test_used_{key}.json"
    if lock.exists():
        raise SystemExit(f"{key} için test kümesine zaten bakıldı ({lock}); ikinci bakış yasak")

    out: dict[str, Any] = {"candidate": key, "config": cfg, "val": {}, "test": {}}
    for seed in SEEDS:
        res = evaluate_factory(cand.factory(cfg, seed, spec), spec)
        models = [r.model for r in res]
        out["val"][str(seed)] = {
            "lifts": {r.lift: _lift_result_summary(r) for r in res},
            "size_bytes": cand.size_bytes(models),
            "latency_ms": float(np.mean([latency_ms(m) for m in models])),
        }
        _write(f"final_{key}.json", out)
        print(f"[{key}] tohum {seed} doğrulama tamam", flush=True)

    LOCKS.mkdir(parents=True, exist_ok=True)
    lock.write_text(json.dumps({"config": cfg, "seeds": SEEDS, "at": time.time()}))
    for seed in SEEDS:
        res = evaluate_factory(cand.factory(cfg, seed, spec), spec, "test", _allow_test=True)
        out["test"][str(seed)] = {"lifts": {r.lift: _lift_result_summary(r) for r in res}}
        if seed == SEEDS[0]:
            # Katman kalibrasyon ısı haritaları için tablo; P057/P060 için tohum-1 modelleri.
            out["test_strata"] = {
                r.lift: metrics.coverage_table(r.model, load_lift(r.lift, "test", spec)).to_dicts()
                for r in res
            }
            for r in res:
                with (LOCKS / f"model_{key}_{r.lift}.pkl").open("wb") as f:
                    pickle.dump(r.model, f)
        _write(f"final_{key}.json", out)
        print(f"[{key}] tohum {seed} test tamam", flush=True)
    return out


SENSITIVITY = {
    "tested_all": DataSpec(tested_only=False),
    "wraps_dahil": DataSpec(include_wraps=True),
    "ağırlıksız": DataSpec(unweighted=True),
}


def sensitivity(key: str) -> dict:
    cand = CANDIDATES[key]
    cfg = _read(f"search_{key}.json")["best"]["config"]
    out: dict[str, Any] = {"candidate": key, "config": cfg, "variants": {}}
    for name, spec in SENSITIVITY.items():
        lifts = ("squat",) if name == "wraps_dahil" else LIFTS
        res = evaluate_factory(cand.factory(cfg, SEEDS[0], spec), spec, lifts=lifts)
        out["variants"][name] = {r.lift: _lift_result_summary(r) for r in res}
        _write(f"sens_{key}.json", out)
        print(f"[{key}] duyarlılık {name} tamam", flush=True)
    return out


def main() -> None:
    p = argparse.ArgumentParser(prog="gymml.tune.bakeoff")
    p.add_argument("step", choices=["search", "final", "sens", "report", "all"])
    p.add_argument("--cand", choices=sorted(CANDIDATES))
    p.add_argument("--trials", type=int, default=N_TRIALS)
    a = p.parse_args()
    if a.step == "report":
        from gymml.tune.report import write_report

        write_report()
        return
    if not a.cand:
        p.error("--cand gerekli")
    if a.step in ("search", "all"):
        search(a.cand, a.trials)
    if a.step in ("final", "all"):
        final(a.cand)
    if a.step in ("sens", "all"):
        sensitivity(a.cand)


if __name__ == "__main__":
    main()
