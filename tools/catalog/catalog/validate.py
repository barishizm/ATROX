"""Validation of normalized exercises. Errors fail the import; null optional fields are only reported."""
from __future__ import annotations

import re
from collections import defaultdict
from typing import Any, Iterable

REQUIRED = ("id", "source_id", "name", "level", "category")
# Upstream data gaps: reported in the quality report, not blocking (handled in P026/P027).
WARN_IF_EMPTY = ("instructions", "images")
OPTIONAL_ENUMS = ("force", "mechanic", "equipment")


def _name_key(name: str) -> str:
    return re.sub(r"[^a-z0-9]+", "", name.casefold())


def validate(exercises: list[dict[str, Any]], image_paths: Iterable[str] | None,
             warnings: list[str] | None = None) -> list[str]:
    """Return error strings (blocking). Non-blocking gaps are appended to `warnings`.
    image_paths=None skips the image-existence check."""
    errors: list[str] = []
    warnings = warnings if warnings is not None else []
    images = set(image_paths) if image_paths is not None else None
    names: dict[str, list[str]] = defaultdict(list)
    ids: dict[str, str] = {}
    for ex in exercises:
        eid = ex.get("id", "<no id>")
        for field in REQUIRED:
            if not ex.get(field):
                errors.append(f"{eid}: missing required field {field}")
        for field in WARN_IF_EMPTY:
            if not ex.get(field):
                warnings.append(f"{eid}: empty {field}")
        if not ex.get("primary_muscles"):
            errors.append(f"{eid}: no primary muscle")
        if eid in ids:
            errors.append(f"{eid}: duplicate id")
        ids[eid] = ex.get("source_id", "")
        if images is not None:
            for img in ex.get("images") or []:
                if img not in images:
                    errors.append(f"{eid}: image file missing {img}")
        if ex.get("name"):
            names[_name_key(ex["name"])].append(eid)
    for key, group in names.items():
        if len(group) > 1:
            errors.append(f"duplicate name {key!r}: {', '.join(group)}")
    return errors
