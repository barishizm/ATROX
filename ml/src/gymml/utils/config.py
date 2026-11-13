"""YAML + tipli dataclass yapılandırma."""

from __future__ import annotations

import dataclasses
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, get_type_hints

import yaml

ML_ROOT = Path(__file__).resolve().parents[3]


@dataclass(frozen=True)
class PathsConfig:
    raw: str = "data/raw"
    interim: str = "data/interim"
    processed: str = "data/processed"
    runs: str = "runs"


@dataclass(frozen=True)
class DataConfig:
    # Toplu CSV'nin sabit indirme adresi kodda değil SOURCES.md'de belgelenir (P047).
    opl_zip: str = "data/raw/openpowerlifting.zip"
    opl_parquet: str = "data/interim/opl.parquet"
    min_rows: int = 1_000_000


@dataclass(frozen=True)
class RunConfig:
    name: str = "smoke"
    seed: int = 20260101
    paths: PathsConfig = field(default_factory=PathsConfig)
    data: DataConfig = field(default_factory=DataConfig)


def _build[T](cls: type[T], raw: dict[str, Any], where: str) -> T:
    hints = get_type_hints(cls)
    known = {f.name for f in dataclasses.fields(cls)}  # type: ignore[arg-type]
    unknown = set(raw) - known
    if unknown:
        raise ValueError(f"{where}: bilinmeyen anahtar(lar): {sorted(unknown)}")
    kwargs: dict[str, Any] = {}
    for key, value in raw.items():
        hint = hints[key]
        if dataclasses.is_dataclass(hint):
            if not isinstance(value, dict):
                raise TypeError(f"{where}.{key}: eşleme bekleniyordu")
            kwargs[key] = _build(hint, value, f"{where}.{key}")
        else:
            if not isinstance(value, hint):
                raise TypeError(f"{where}.{key}: {hint.__name__} bekleniyordu, {value!r} geldi")
            kwargs[key] = value
    return cls(**kwargs)


def load_config[T](path: str | Path, cls: type[T] = RunConfig) -> T:  # type: ignore[assignment]
    """YAML dosyasını tipli yapılandırmaya çevirir; bilinmeyen/yanlış tipli alan hata verir."""
    raw = yaml.safe_load(Path(path).read_text(encoding="utf-8")) or {}
    if not isinstance(raw, dict):
        raise TypeError(f"{path}: kök bir eşleme olmalı")
    return _build(cls, raw, str(path))
