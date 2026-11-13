import json
import random
from datetime import UTC, datetime
from pathlib import Path

import numpy as np
import pytest
import yaml

from gymml.cli import smoke
from gymml.utils.config import ML_ROOT, RunConfig, load_config
from gymml.utils.runs import Run
from gymml.utils.seed import seed_everything


def test_seed_everything_is_reproducible():
    import torch

    seed_everything(7)
    a = (random.random(), np.random.rand(), torch.rand(1).item())
    seed_everything(7)
    b = (random.random(), np.random.rand(), torch.rand(1).item())
    assert a == b


def test_load_config_typed(tmp_path: Path):
    p = tmp_path / "c.yaml"
    p.write_text("name: x\nseed: 3\ndata:\n  min_rows: 5\n")
    cfg = load_config(p)
    assert isinstance(cfg, RunConfig)
    assert (cfg.name, cfg.seed, cfg.data.min_rows) == ("x", 3, 5)
    assert cfg.paths.runs == "runs"


@pytest.mark.parametrize("body", ["bogus: 1", "seed: abc", "data:\n  nope: 1"])
def test_load_config_rejects_bad_input(tmp_path: Path, body: str):
    p = tmp_path / "c.yaml"
    p.write_text(body)
    with pytest.raises((ValueError, TypeError)):
        load_config(p)


def test_run_writes_trace(tmp_path: Path):
    run = Run(tmp_path, "t", RunConfig(name="t"), now=datetime(2026, 1, 2, 3, 4, 5, tzinfo=UTC))
    run.write_metrics({"a": 1})
    assert run.dir.name == "20260102T030405Z-t"
    assert yaml.safe_load((run.dir / "config.yaml").read_text())["name"] == "t"
    assert set(json.loads((run.dir / "git.json").read_text())) == {
        "commit",
        "branch",
        "dirty",
        "subject",
    }
    assert json.loads((run.dir / "metrics.json").read_text()) == {"a": 1}


def test_smoke_run_leaves_trace(tmp_path: Path, monkeypatch):
    cfg = tmp_path / "s.yaml"
    cfg.write_text(f"name: smoke\npaths:\n  runs: {tmp_path / 'runs'}\n")
    out = smoke(cfg)
    assert out.parent == tmp_path / "runs"
    for f in ("config.yaml", "git.json", "metrics.json", "plots/smoke.png"):
        assert (out / f).is_file()


def test_layout_exists():
    for d in ("data/raw", "data/interim", "data/processed", "runs", "golden", "reports", "configs"):
        assert (ML_ROOT / d).is_dir()
