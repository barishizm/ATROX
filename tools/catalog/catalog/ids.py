"""Stable slug ids. Once written to id_lock.json an id never changes."""
from __future__ import annotations

import json
import re
from pathlib import Path

LOCK_VERSION = 1


def slugify(source_id: str) -> str:
    slug = re.sub(r"[^a-z0-9]+", "-", source_id.lower()).strip("-")
    if not slug:
        raise ValueError(f"cannot derive slug from {source_id!r}")
    return slug


def load_lock(path: Path) -> dict[str, str]:
    if not path.exists():
        return {}
    data = json.loads(path.read_text(encoding="utf-8"))
    if data.get("version") != LOCK_VERSION:
        raise ValueError(f"unsupported id_lock version {data.get('version')!r}")
    ids = data["ids"]
    if len(set(ids.values())) != len(ids):
        raise ValueError("id_lock.json contains duplicate slugs")
    return ids


def save_lock(path: Path, ids: dict[str, str]) -> None:
    payload = {"version": LOCK_VERSION, "ids": dict(sorted(ids.items()))}
    path.write_text(json.dumps(payload, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


def assign_ids(source_ids: list[str], lock: dict[str, str]) -> tuple[dict[str, str], list[str]]:
    """Return (updated lock, notes). Locked ids are kept; new ones get a slug, suffixed -2, -3 on collision."""
    if len(set(source_ids)) != len(source_ids):
        raise ValueError("duplicate source ids in input")
    ids = dict(lock)
    used = set(ids.values())
    notes: list[str] = []
    for sid in sorted(source_ids):
        if sid in ids:
            continue
        base = slug = slugify(sid)
        n = 2
        while slug in used:
            slug = f"{base}-{n}"
            n += 1
        if slug != base:
            notes.append(f"slug collision: {sid!r} -> {slug!r}")
        ids[sid] = slug
        used.add(slug)
    return ids, notes
