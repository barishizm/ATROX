"""Çalıştırma dizini: runs/<zaman>-<ad>/ altına yapılandırma, git özeti, metrikler, grafikler."""

from __future__ import annotations

import dataclasses
import json
import subprocess
from datetime import UTC, datetime
from pathlib import Path
from typing import Any

import yaml


def git_summary(cwd: Path | None = None) -> dict[str, Any]:
    def run(*args: str) -> str:
        return subprocess.run(
            ["git", *args], cwd=cwd, capture_output=True, text=True, check=True
        ).stdout.strip()

    try:
        return {
            "commit": run("rev-parse", "HEAD"),
            "branch": run("rev-parse", "--abbrev-ref", "HEAD"),
            "dirty": bool(run("status", "--porcelain")),
            "subject": run("log", "-1", "--format=%s"),
        }
    except (subprocess.CalledProcessError, FileNotFoundError):
        return {"commit": None, "branch": None, "dirty": None, "subject": None}


class Run:
    """Tek bir deneyin çıktı klasörü."""

    def __init__(self, root: Path, name: str, config: Any, now: datetime | None = None):
        stamp = (now or datetime.now(UTC)).strftime("%Y%m%dT%H%M%SZ")
        self.dir = Path(root) / f"{stamp}-{name}"
        self.dir.mkdir(parents=True, exist_ok=False)
        (self.dir / "plots").mkdir()
        cfg = dataclasses.asdict(config) if dataclasses.is_dataclass(config) else dict(config)
        (self.dir / "config.yaml").write_text(
            yaml.safe_dump(cfg, allow_unicode=True, sort_keys=False), encoding="utf-8"
        )
        (self.dir / "git.json").write_text(
            json.dumps(git_summary(), indent=2, ensure_ascii=False), encoding="utf-8"
        )

    def write_metrics(self, metrics: dict[str, Any]) -> Path:
        path = self.dir / "metrics.json"
        path.write_text(json.dumps(metrics, indent=2, ensure_ascii=False), encoding="utf-8")
        return path

    def save_figure(self, fig: Any, name: str) -> Path:
        path = self.dir / "plots" / name
        fig.savefig(path, dpi=150, bbox_inches="tight")
        return path
