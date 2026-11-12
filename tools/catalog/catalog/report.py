"""Quality report: counts, null fields, category distribution."""
from __future__ import annotations

from collections import Counter
from typing import Any

from .validate import OPTIONAL_ENUMS


def build_report(exercises: list[dict[str, Any]], errors: list[str], notes: list[str],
                 warnings: list[str] | None = None) -> dict[str, Any]:
    null_counts = {f: sum(1 for e in exercises if e.get(f) is None) for f in OPTIONAL_ENUMS}
    null_counts["instructions_empty"] = sum(1 for e in exercises if not e["instructions"])
    null_counts["images_empty"] = sum(1 for e in exercises if not e["images"])
    null_counts["secondary_muscles_empty"] = sum(1 for e in exercises if not e["secondary_muscles"])
    warnings = warnings or []
    return {
        "total": len(exercises),
        "null_fields": null_counts,
        "categories": dict(Counter(e["category"] for e in exercises).most_common()),
        "levels": dict(Counter(e["level"] for e in exercises).most_common()),
        "equipment": dict(Counter(e["equipment"] or "null" for e in exercises).most_common()),
        "primary_muscles": dict(Counter(m for e in exercises for m in e["primary_muscles"]).most_common()),
        "image_count": sum(len(e["images"]) for e in exercises),
        "validation_errors": errors,
        "warnings": warnings,
        "notes": notes,
    }


def render_markdown(report: dict[str, Any]) -> str:
    lines = ["# Catalog quality report", "", f"- Exercises: **{report['total']}**",
             f"- Images: {report['image_count']}", f"- Validation errors: {len(report['validation_errors'])}", "",
             "## Null / empty fields", ""]
    lines += [f"- `{k}`: {v}" for k, v in report["null_fields"].items()]
    for title, key in (("Categories", "categories"), ("Levels", "levels"),
                       ("Equipment", "equipment"), ("Primary muscles", "primary_muscles")):
        lines += ["", f"## {title}", ""] + [f"- {k}: {v}" for k, v in report[key].items()]
    if report["notes"]:
        lines += ["", "## Notes", ""] + [f"- {n}" for n in report["notes"]]
    if report["warnings"]:
        lines += ["", "## Warnings (upstream data gaps)", ""] + [f"- {w}" for w in report["warnings"]]
    if report["validation_errors"]:
        lines += ["", "## Validation errors", ""] + [f"- {e}" for e in report["validation_errors"]]
    return "\n".join(lines) + "\n"
