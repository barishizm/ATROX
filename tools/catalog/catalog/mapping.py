"""Enum mapping from free-exercise-db values to ATROX catalog enums (docs/00-KARARLAR.md §5.4)."""
from __future__ import annotations

from typing import Any

FORCE = {"push": "push", "pull": "pull", "static": "static"}
LEVEL = {"beginner": "beginner", "intermediate": "intermediate", "expert": "expert"}
MECHANIC = {"compound": "compound", "isolation": "isolation"}
EQUIPMENT = {
    "barbell": "barbell",
    "dumbbell": "dumbbell",
    "other": "other",
    "body only": "body_only",
    "cable": "cable",
    "machine": "machine",
    "kettlebells": "kettlebell",
    "bands": "bands",
    "medicine ball": "medicine_ball",
    "exercise ball": "exercise_ball",
    "foam roll": "foam_roll",
    "e-z curl bar": "ez_bar",
}
CATEGORY = {
    "strength": "strength",
    "stretching": "stretching",
    "plyometrics": "plyometrics",
    "powerlifting": "powerlifting",
    "olympic weightlifting": "olympic_weightlifting",
    "strongman": "strongman",
    "cardio": "cardio",
}
MUSCLES = {
    "abdominals": "abdominals",
    "abductors": "abductors",
    "adductors": "adductors",
    "biceps": "biceps",
    "calves": "calves",
    "chest": "chest",
    "forearms": "forearms",
    "glutes": "glutes",
    "hamstrings": "hamstrings",
    "lats": "lats",
    "lower back": "lower_back",
    "middle back": "middle_back",
    "neck": "neck",
    "quadriceps": "quadriceps",
    "shoulders": "shoulders",
    "traps": "traps",
    "triceps": "triceps",
}


class MappingError(ValueError):
    """Raised when the source holds a value outside the agreed enum."""


def _map(table: dict[str, str], field: str, value: Any, source_id: str) -> str | None:
    if value is None:
        return None
    try:
        return table[value]
    except (KeyError, TypeError):
        raise MappingError(f"{source_id}: unknown {field} value {value!r}") from None


def map_exercise(raw: dict[str, Any], catalog_id: str) -> dict[str, Any]:
    """Convert one source record to the normalized base record. Null enum fields stay null."""
    sid = raw["id"]
    return {
        "id": catalog_id,
        "source_id": sid,
        "name": raw["name"].strip(),
        "force": _map(FORCE, "force", raw.get("force"), sid),
        "level": _map(LEVEL, "level", raw.get("level"), sid),
        "mechanic": _map(MECHANIC, "mechanic", raw.get("mechanic"), sid),
        "equipment": _map(EQUIPMENT, "equipment", raw.get("equipment"), sid),
        "category": _map(CATEGORY, "category", raw.get("category"), sid),
        "primary_muscles": [_map(MUSCLES, "muscle", m, sid) for m in raw.get("primaryMuscles") or []],
        "secondary_muscles": [_map(MUSCLES, "muscle", m, sid) for m in raw.get("secondaryMuscles") or []],
        "instructions": [s.strip() for s in raw.get("instructions") or [] if s and s.strip()],
        "images": list(raw.get("images") or []),
    }
