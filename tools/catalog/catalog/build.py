"""catalog-build (P028): base + taxonomy + translations + image manifest -> versioned out/catalog.v{N}.json.

The version number is tracked in `catalog_version.json` (committed): it is bumped only when the content checksum
changes, so rebuilding unchanged inputs is a no-op. The same file is bundled into the app and seeded to Supabase.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import shutil
import sys
from pathlib import Path
from typing import Any

import yaml

ROOT = Path(__file__).resolve().parent.parent
REPO_ROOT = ROOT.parent.parent
OUT = ROOT / "out"
VERSION_FILE = ROOT / "catalog_version.json"
APP_CATALOG_DIR = REPO_ROOT / "ios/App/Resources/Catalog"
LOCALES = ("en", "tr")
FORMAT = 1  # layout of the JSON file; bump when the Swift decoder must change

# Allowed values = the CHECK constraints of supabase/migrations/20261112140000_schema_4_catalog_vocabulary.sql.
VOCAB: dict[str, set[str]] = {
    "equipment": {"barbell", "dumbbell", "kettlebell", "machine", "cable", "bands", "body_only", "ez_bar",
                  "exercise_ball", "foam_roll", "medicine_ball", "other"},
    "mechanic": {"compound", "isolation"},
    "force": {"push", "pull", "static"},
    "level": {"beginner", "intermediate", "expert"},
    "category": {"strength", "powerlifting", "olympic_weightlifting", "strongman", "plyometrics", "stretching",
                 "cardio"},
    "muscle": {"abdominals", "abductors", "adductors", "biceps", "calves", "chest", "forearms", "glutes",
               "hamstrings", "lats", "lower_back", "middle_back", "neck", "quadriceps", "shoulders", "traps",
               "triceps"},
    "movement_pattern": {"squat", "hip_hinge", "horizontal_push", "vertical_push", "horizontal_pull",
                         "vertical_pull", "isolation_biceps", "isolation_triceps", "isolation_forearms",
                         "isolation_shoulders", "isolation_chest", "isolation_back", "isolation_quads",
                         "isolation_hamstrings", "isolation_glutes", "isolation_calves", "isolation_hips",
                         "isolation_neck", "core", "carry", "olympic", "plyometric", "cardio", "mobility", "other"},
    "scoring_type": {"weighted", "bodyweight_loaded", "reps_only", "time", "none"},
    "anchor_lift": {"squat", "bench", "deadlift"},
    "load_convention": {"total", "per_hand", "per_side", "machine_stack", "bodyweight_plus"},
    "ratio_confidence": {"A", "B", "C"},
}


def canonical(obj: Any) -> str:
    return json.dumps(obj, sort_keys=True, ensure_ascii=False, separators=(",", ":"))


def checksum(exercises: list[dict[str, Any]]) -> str:
    return hashlib.sha256(canonical(exercises).encode("utf-8")).hexdigest()


def _image_names(manifest: dict[str, Any], exercise_id: str) -> list[str]:
    """Full-size file names in source order; the thumbnail is the same name with `.t.webp` (see images.py)."""
    return [v["full"] for v in manifest["exercises"].get(exercise_id, [])]


def merge(base: list[dict[str, Any]], taxonomy: list[dict[str, Any]],
          translations: dict[str, list[dict[str, Any]]], manifest: dict[str, Any]) -> list[dict[str, Any]]:
    tax = {e["id"]: e for e in taxonomy}
    tr = {loc: {t["id"]: t for t in rows} for loc, rows in translations.items()}
    out: list[dict[str, Any]] = []
    for b in sorted(base, key=lambda e: e["id"]):
        t = tax[b["id"]]
        out.append({
            "id": b["id"],
            "equipment": b["equipment"],
            "mechanic": b["mechanic"],
            "force": b["force"],
            "level": b["level"],
            "category": b["category"],
            "primary_muscles": b["primary_muscles"],
            "secondary_muscles": b["secondary_muscles"],
            "movement_pattern": t["movement_pattern"],
            "scoring_type": t["scoring_type"],
            "anchor_lift": t["anchor"],
            "load_convention": t["load_convention"],
            "ratio": t["ratio"],
            "tau": t["tau"],
            "ratio_confidence": t["ratio_confidence"],
            "bw_fraction": t["bw_fraction"],
            "is_core": t["is_core"],
            "is_unilateral": t["is_unilateral"],
            "images": _image_names(manifest, b["id"]),
            "translations": {
                loc: {k: tr[loc][b["id"]][k] for k in ("name", "aliases", "instructions")} for loc in LOCALES
            },
        })
    return out


def validate(exercises: list[dict[str, Any]]) -> list[str]:
    errors: list[str] = []
    seen: set[str] = set()
    for e in exercises:
        i = e["id"]
        if i in seen:
            errors.append(f"{i}: duplicate id")
        seen.add(i)
        for field in ("equipment", "mechanic", "force", "level", "category", "movement_pattern", "scoring_type",
                      "anchor_lift", "load_convention", "ratio_confidence"):
            v = e[field]
            if v is not None and v not in VOCAB[field]:
                errors.append(f"{i}: {field}={v!r} not allowed")
        for field in ("primary_muscles", "secondary_muscles"):
            bad = set(e[field]) - VOCAB["muscle"]
            if bad:
                errors.append(f"{i}: {field} has unknown {sorted(bad)}")
        if not e["primary_muscles"]:
            errors.append(f"{i}: no primary muscle")
        for loc in LOCALES:
            if not e["translations"][loc]["name"].strip():
                errors.append(f"{i}: empty {loc} name")
        if e["scoring_type"] in ("weighted", "bodyweight_loaded"):
            params = [e["anchor_lift"], e["ratio"], e["tau"], e["ratio_confidence"]]
            if any(p is not None for p in params) and any(p is None for p in params):
                errors.append(f"{i}: scoring parameters are partially filled")
    return errors


def assign_version(exercises: list[dict[str, Any]], version_file: Path) -> tuple[int, str, bool]:
    """Returns (version, checksum, bumped). Writes the version file when the content changed."""
    digest = checksum(exercises)
    current = json.loads(version_file.read_text(encoding="utf-8")) if version_file.exists() else None
    if current and current["checksum"] == digest:
        return current["version"], digest, False
    version = (current["version"] + 1) if current else 1
    version_file.write_text(json.dumps({"version": version, "checksum": digest}, indent=1) + "\n", encoding="utf-8")
    return version, digest, True


def render(version: int, digest: str, exercises: list[dict[str, Any]]) -> str:
    doc = {"format": FORMAT, "version": version, "checksum": digest, "exercises": exercises}
    return json.dumps(doc, sort_keys=True, ensure_ascii=False, separators=(",", ":")) + "\n"


def build(out_dir: Path = OUT, version_file: Path = VERSION_FILE, app_dir: Path | None = APP_CATALOG_DIR,
          *, check: bool = False) -> int:
    load = lambda name: json.loads((out_dir / name).read_text(encoding="utf-8"))  # noqa: E731
    taxonomy = yaml.safe_load((ROOT / "scoring_taxonomy.yaml").read_text(encoding="utf-8"))["exercises"]
    exercises = merge(load("exercises.base.json"), taxonomy,
                      {loc: load(f"exercises.{loc}.json") for loc in LOCALES}, load("image_manifest.json"))
    errors = validate(exercises)
    if errors:
        print("\n".join(errors[:50]), file=sys.stderr)
        print(f"{len(errors)} validation error(s)", file=sys.stderr)
        return 1
    if check:
        up_to_date = version_file.exists() and json.loads(version_file.read_text())["checksum"] == checksum(exercises)
        print("catalog up to date" if up_to_date else "catalog changed: run catalog-build", file=sys.stderr)
        return 0 if up_to_date else 1
    version, digest, bumped = assign_version(exercises, version_file)
    text = render(version, digest, exercises)
    target = out_dir / f"catalog.v{version}.json"
    target.write_text(text, encoding="utf-8")
    if app_dir is not None:  # the app bundles exactly the latest catalog
        app_dir.mkdir(parents=True, exist_ok=True)
        for old in app_dir.glob("catalog.v*.json"):
            old.unlink()
        shutil.copyfile(target, app_dir / target.name)
    print(f"catalog.v{version}.json: {len(exercises)} exercises, {len(text) / 1024:.0f} KB, "
          f"sha256 {digest[:12]}{' (new version)' if bumped else ''}")
    return 0


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(prog="catalog-build")
    ap.add_argument("--check", action="store_true", help="validate and fail if the committed version is stale")
    ap.add_argument("--no-app-copy", action="store_true", help="do not copy the file into the app bundle folder")
    a = ap.parse_args(argv)
    return build(app_dir=None if a.no_app_copy else APP_CATALOG_DIR, check=a.check)


if __name__ == "__main__":
    raise SystemExit(main())
