"""Build, render and validate `scoring_taxonomy.yaml` (P025)."""
from __future__ import annotations

import json
from pathlib import Path
from typing import Any

import yaml
from jsonschema import Draft202012Validator

from . import taxonomy

ROOT = Path(__file__).resolve().parent.parent
SCHEMA_PATH = ROOT / "scoring_taxonomy.schema.json"
RATIOS_PATH = ROOT / "ratios.yaml"
OVERRIDABLE = ("movement_pattern", "scoring_type", "load_convention", "is_unilateral")
CORE_RANGE = (120, 180)
SCORED = ("weighted", "bodyweight_loaded")
PARAMS = ("anchor", "ratio", "tau", "ratio_confidence")
RATIO_FIELDS = {"anchor", "ratio", "grade", "tau", "bw_fraction", "sources", "note"}
MACHINE_EQUIPMENT = ("machine", "cable")
MACHINE_LOADS = ("machine_stack", "per_side")


def load_overrides(path: Path) -> dict[str, Any]:
    data = yaml.safe_load(path.read_text(encoding="utf-8")) or {}
    return {"core": list(data.get("core") or []), "overrides": dict(data.get("overrides") or {})}


def load_ratios(path: Path = RATIOS_PATH) -> dict[str, Any]:
    """ratios.yaml (P056): tau table, consistency settings, sources and per-exercise anchor ratios."""
    data = yaml.safe_load(path.read_text(encoding="utf-8")) or {}
    return {"tau": dict(data.get("tau") or {}), "consistency": dict(data.get("consistency") or {}),
            "sources": dict(data.get("sources") or {}), "exercises": dict(data.get("exercises") or {})}


def is_machine(equipment: str | None, load_convention: str | None) -> bool:
    return equipment in MACHINE_EQUIPMENT or load_convention in MACHINE_LOADS


def tau_for(row: dict[str, Any], tau_table: dict[str, float], machine: bool) -> float | None:
    """Explicit tau wins; else the anchor lift itself, machines, then the grade decide (ratios.yaml header)."""
    if row.get("anchor") is None:
        return None
    if row.get("tau") is not None:
        return float(row["tau"])
    if "anchor" in row.get("sources", []):
        return float(tau_table["anchor"])
    if machine:
        return float(tau_table["machine"])
    return float(tau_table[row["grade"]])


def _apply_ratio(entry: dict[str, Any], row: dict[str, Any], ratios: dict[str, Any], machine: bool) -> None:
    bad = set(row) - RATIO_FIELDS
    if bad:
        raise ValueError(f"{entry['id']}: unknown ratios.yaml fields {sorted(bad)}")
    unknown_src = [s for s in row.get("sources", []) if s not in ratios["sources"]]
    if not row.get("sources") or unknown_src:
        raise ValueError(f"{entry['id']}: ratios.yaml row needs known sources, got {row.get('sources')}")
    entry["anchor"] = row.get("anchor")
    entry["ratio"] = None if row.get("ratio") is None else float(row["ratio"])
    entry["tau"] = tau_for(row, ratios["tau"], machine)
    entry["ratio_confidence"] = row.get("grade")
    entry["bw_fraction"] = None if row.get("bw_fraction") is None else float(row["bw_fraction"])
    entry["ratio_source"] = "; ".join(row["sources"])
    entry["ratio_note"] = row.get("note")


def build(exercises: list[dict[str, Any]], overrides: dict[str, Any], base_sha: str | None = None,
          ratios: dict[str, Any] | None = None) -> dict[str, Any]:
    ratios = ratios or {"tau": {}, "consistency": {}, "sources": {}, "exercises": {}}
    by_id = {e["id"]: e for e in exercises}
    core = overrides["core"]
    unknown = [i for i in list(core) + list(overrides["overrides"]) if i not in by_id]
    if unknown:
        raise ValueError(f"taxonomy_overrides.yaml references unknown ids: {sorted(set(unknown))}")
    not_core = sorted(set(ratios["exercises"]) - set(core))
    if not_core:
        raise ValueError(f"ratios.yaml rows must be core exercises: {not_core}")
    if len(set(core)) != len(core):
        raise ValueError("duplicate ids in core list")
    core_set = set(core)

    entries = []
    for ex in exercises:
        t = taxonomy.classify(ex)
        ov = overrides["overrides"].get(ex["id"])
        assignment = "rule"
        notes = list(t["review_notes"])
        needs_review = t["needs_review"]
        if ov:
            bad = set(ov) - set(OVERRIDABLE) - {"note", "still_unsure"}
            if bad:
                raise ValueError(f"{ex['id']}: unknown override fields {sorted(bad)}")
            for k in OVERRIDABLE:
                if k in ov:
                    t[k] = ov[k]
            assignment = "manual"
            needs_review = bool(ov.get("still_unsure"))
            notes = [ov["note"]] if ov.get("note") else []
        entry = {
            "id": ex["id"],
            "name": ex["name"],
            "movement_pattern": t["movement_pattern"],
            "scoring_type": t["scoring_type"],
            "load_convention": t["load_convention"],
            "is_unilateral": t["is_unilateral"],
            "is_core": ex["id"] in core_set,
            "anchor": None,
            "ratio": None,
            "tau": None,
            "ratio_confidence": None,
            "bw_fraction": None,
            "ratio_source": None,
            "ratio_note": None,
            "assignment": assignment,
            "rule": t["rule"],
            "needs_review": needs_review,
            "review_notes": notes,
        }
        if ex["id"] in ratios["exercises"]:
            _apply_ratio(entry, ratios["exercises"][ex["id"]], ratios,
                         is_machine(ex.get("equipment"), entry["load_convention"]))
        entries.append(entry)
    return {"version": 1, "source_exercises_sha256": base_sha, "exercises": entries}


def render(doc: dict[str, Any]) -> str:
    header = (
        "# Generated by `uv run catalog-taxonomy` (P025). Do not edit by hand: change catalog/taxonomy.py rules or\n"
        "# taxonomy_overrides.yaml. anchor/ratio/tau/ratio_confidence/bw_fraction/ratio_* come from ratios.yaml (P056).\n"
    )
    return header + yaml.safe_dump(doc, sort_keys=False, allow_unicode=True, width=120)


def load_schema() -> dict[str, Any]:
    return json.loads(SCHEMA_PATH.read_text(encoding="utf-8"))


def validate(doc: dict[str, Any], exercises: list[dict[str, Any]]) -> list[str]:
    """Return a list of problems (empty when the taxonomy is valid)."""
    errors = [
        f"{'/'.join(map(str, e.absolute_path)) or '<root>'}: {e.message}"
        for e in sorted(Draft202012Validator(load_schema()).iter_errors(doc), key=lambda e: list(e.absolute_path))
    ]
    entries = doc.get("exercises", []) if isinstance(doc, dict) else []
    ids = [e.get("id") for e in entries if isinstance(e, dict)]
    if len(ids) != len(set(ids)):
        errors.append("duplicate exercise ids in taxonomy")
    missing = {e["id"] for e in exercises} - set(ids)
    extra = set(ids) - {e["id"] for e in exercises}
    if missing:
        errors.append(f"{len(missing)} catalog exercises have no taxonomy entry, e.g. {sorted(missing)[:3]}")
    if extra:
        errors.append(f"taxonomy entries not in catalog: {sorted(extra)[:3]}")
    equipment = {e["id"]: e.get("equipment") for e in exercises}
    core = 0
    for e in entries:
        if not isinstance(e, dict):
            continue
        eid = e.get("id")
        st, lc = e.get("scoring_type"), e.get("load_convention")
        if st in ("none", "time", "reps_only") and lc is not None:
            errors.append(f"{eid}: scoring_type {st} must have load_convention null")
        if st == "weighted" and lc in (None, "bodyweight_plus"):
            errors.append(f"{eid}: weighted needs a load convention other than bodyweight_plus")
        if st == "bodyweight_loaded" and lc != "bodyweight_plus":
            errors.append(f"{eid}: bodyweight_loaded requires load_convention bodyweight_plus")
        if e.get("is_core"):
            core += 1
            if st == "none":
                errors.append(f"{eid}: core exercise cannot have scoring_type none")
        errors += _scoring_param_errors(e, equipment.get(eid))
        if e.get("movement_pattern") in ("cardio", "mobility", "plyometric") and st != "none":
            errors.append(f"{eid}: {e['movement_pattern']} must be scoring_type none")
    if not CORE_RANGE[0] <= core <= CORE_RANGE[1]:
        errors.append(f"core set has {core} exercises; expected {CORE_RANGE[0]}-{CORE_RANGE[1]} (~150)")
    return errors


def _scoring_param_errors(e: dict[str, Any], equipment: str | None) -> list[str]:
    """Strict P011 rule (restored in P056): a scored core exercise carries every parameter; nothing else scores."""
    eid, st = e.get("id"), e.get("scoring_type")
    params = [e.get(k) for k in PARAMS]
    errs: list[str] = []
    if st in SCORED and e.get("is_core"):
        if any(p is None for p in params) or not e.get("ratio_source"):
            errs.append(f"{eid}: scored core exercise needs anchor, ratio, tau, ratio_confidence and ratio_source")
        if st == "bodyweight_loaded" and e.get("bw_fraction") is None:
            errs.append(f"{eid}: bodyweight_loaded needs bw_fraction")
        if is_machine(equipment, e.get("load_convention")) and e.get("ratio_confidence") not in (None, "C"):
            errs.append(f"{eid}: machine/cable exercises are capped at ratio_confidence C")
    elif any(e.get(k) is not None for k in ("anchor", "ratio", "tau")):
        errs.append(f"{eid}: only scored core exercises (weighted/bodyweight_loaded) carry anchor ratios")
    elif e.get("ratio_confidence") is not None and e.get("bw_fraction") is None:
        errs.append(f"{eid}: ratio_confidence without a ratio or bw_fraction")
    return errs
