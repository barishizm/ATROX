"""`python -m gymml.cli smoke` — örnek çalıştırma; runs/ altında iz bırakır."""

from __future__ import annotations

import argparse
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402
import numpy as np  # noqa: E402

from gymml.utils.config import ML_ROOT, load_config  # noqa: E402
from gymml.utils.runs import Run  # noqa: E402
from gymml.utils.seed import seed_everything  # noqa: E402


def smoke(config_path: Path) -> Path:
    cfg = load_config(config_path)
    seed_everything(cfg.seed)
    run = Run(ML_ROOT / cfg.paths.runs, cfg.name, cfg)
    sample = np.random.default_rng(cfg.seed).normal(size=1000)
    fig, ax = plt.subplots()
    ax.hist(sample, bins=30)
    run.save_figure(fig, "smoke.png")
    plt.close(fig)
    run.write_metrics({"mean": float(sample.mean()), "std": float(sample.std())})
    return run.dir


def main() -> None:
    parser = argparse.ArgumentParser(prog="gymml")
    sub = parser.add_subparsers(dest="cmd", required=True)
    p = sub.add_parser("smoke", help="Duman testi çalıştırması")
    p.add_argument("--config", default=str(ML_ROOT / "configs/smoke.yaml"))
    args = parser.parse_args()
    if args.cmd == "smoke":
        print(smoke(Path(args.config)))


if __name__ == "__main__":
    main()
