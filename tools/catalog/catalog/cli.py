"""catalog-import: free-exercise-db -> out/exercises.base.json + quality report."""
from __future__ import annotations

import argparse
import datetime
import json
import sys
from pathlib import Path

from . import ids, mapping, report, source, validate

ROOT = Path(__file__).resolve().parent.parent


def build(src: source.Source, lock: dict[str, str]):
    new_lock, notes = ids.assign_ids([e["id"] for e in src.exercises], lock)
    orphans = sorted(set(lock) - {e["id"] for e in src.exercises})
    notes += [f"locked id no longer in source (kept): {o}" for o in orphans]
    exercises = sorted((mapping.map_exercise(e, new_lock[e["id"]]) for e in src.exercises), key=lambda e: e["id"])
    warnings: list[str] = []
    errors = validate.validate(exercises, src.image_paths, warnings)
    return exercises, new_lock, report.build_report(exercises, errors, notes, warnings)


def render_sources(src: source.Source, accessed: str) -> str:
    return f"""# Catalog sources

## free-exercise-db

- Repository: https://github.com/{source.REPO}
- Pinned commit: `{source.PINNED_COMMIT}`
- License: Unlicense (public domain) — upstream `LICENSE.md` verified by the importer
- Accessed: {accessed}
- `dist/exercises.json` SHA-256: `{src.exercises_sha256}`
- Records: {len(src.exercises)}

The importer refuses to run if the license text is not the Unlicense. Image files are referenced by their path
inside upstream `exercises/`; their existence is verified against the pinned commit's git tree.
"""


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--cache", type=Path, default=ROOT / "cache")
    ap.add_argument("--out", type=Path, default=ROOT / "out")
    ap.add_argument("--lock", type=Path, default=ROOT / "id_lock.json")
    ap.add_argument("--offline", action="store_true", help="use only files already in --cache")
    a = ap.parse_args(argv)

    src = source.load_cached(a.cache) if a.offline else source.fetch(a.cache)
    exercises, new_lock, rep = build(src, ids.load_lock(a.lock))

    a.out.mkdir(parents=True, exist_ok=True)
    (a.out / "quality_report.json").write_text(json.dumps(rep, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    (a.out / "quality_report.md").write_text(report.render_markdown(rep), encoding="utf-8")
    if rep["validation_errors"]:
        print(f"{len(rep['validation_errors'])} validation errors; see {a.out / 'quality_report.md'}", file=sys.stderr)
        return 1
    ids.save_lock(a.lock, new_lock)
    (a.out / "exercises.base.json").write_text(
        json.dumps(exercises, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    (ROOT / "SOURCES.md").write_text(render_sources(src, datetime.date.today().isoformat()), encoding="utf-8")
    print(f"{len(exercises)} exercises written to {a.out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
