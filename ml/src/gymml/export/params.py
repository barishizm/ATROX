"""P060: merge `params_draft/*.json` into the bundle's `params.json` and build `taxonomy.json`.

Field names are camelCase (Swift `Codable` without a key strategy); map keys (lifts, sexes, populations,
age bands, categories, patterns) stay verbatim. Shape is pinned by `ml/schemas/params.schema.json`.
"""
# ruff: noqa: E501

from __future__ import annotations

import csv
import json
from pathlib import Path

import jsonschema

from gymml.calibration.reference import _BAND_EDGES
from gymml.scoring import PARAMS_DIR, Exercise

ML_ROOT = Path(__file__).resolve().parents[3]
SCHEMA_DIR = ML_ROOT / "schemas"
PARAMS_SCHEMA_VERSION = 1
TAXONOMY_SCHEMA_VERSION = 1
REP_NORMS = ML_ROOT / "data" / "rep_norms.csv"


def _read(name: str, directory: Path = PARAMS_DIR) -> dict:
    return json.loads((directory / f"{name}.json").read_text(encoding="utf-8"))


def camel(s: str) -> str:
    head, *rest = s.split("_")
    return head + "".join(w[:1].upper() + w[1:] for w in rest)


def _struct(d: dict) -> dict:
    """Recursively camelCase a dict that only holds struct fields; drops `_doc`/`provenance`/source notes."""
    out = {}
    for k, v in d.items():
        if k.startswith("_") or k in ("provenance", "source"):
            continue
        out[camel(k)] = _struct(v) if isinstance(v, dict) else v
    return out


def _ladder(d: dict) -> list[float]:
    return [d["mild"], d["moderate"], d["severe"]]


def build_params(input_clip: dict, directory: Path = PARAMS_DIR) -> dict:
    """`directory` holds the `params_draft` files (P094 passes a candidate copy)."""
    e1rm, scoring = _read("e1rm", directory), _read("scoring", directory)
    progress, imb = _read("progress", directory), _read("imbalance", directory)
    cal = _read("calibration", directory)["calibration"]
    cs, es, agg = scoring["current_strength"], scoring["exercise_score"], scoring["aggregate"]
    corr = scoring["anchor_correlation"]
    return {
        "schemaVersion": PARAMS_SCHEMA_VERSION,
        "e1rm": {
            "family": e1rm["family"],
            "rMax": e1rm["r_max"],
            "defaultCategory": e1rm["default_category"],
            "patternCategory": e1rm["pattern_category"],
            "categories": {k: {"k": v["k"], "p": v["p"]} for k, v in e1rm["categories"].items()},
            "confidence": _struct(e1rm["confidence"]),
        },
        "currentStrength": {
            "windowDays": cs["window_days"],
            "outlierJump": cs["outlier_jump"],
            "staleDecayPerWeek": cs["stale_decay_per_week"],
            "minSetConfidence": cs["min_set_confidence"],
            "confidenceLevels": {k: _struct(v) for k, v in cs["confidence_levels"].items()},
        },
        "anchor": {
            "cdfClip": scoring["anchor_model"]["cdf_clip"],
            "scaleQuantiles": scoring["anchor_model"]["scale_quantiles"],
        },
        "exerciseScore": {
            "populations": es["populations"],
            "defaultPopulation": es["default_population"],
            "scoreClip": es["score_clip"],
            "calibrationMinAge": float(es["calibration_min_age_band"].split("-")[0]),
            "unspecifiedSexMix": es["unspecified_sex_mix"],
            "gradeConfidenceCap": es["grade_confidence_cap"],
            "machineConventions": es["machine_conventions"],
            "machineEquipment": es["machine_equipment"],
        },
        "calibration": {
            "ageBands": [{"key": k, "min": lo, "max": hi} for k, (lo, hi) in _BAND_EDGES.items()],
            "delta": cal["delta"],
            "kappa": cal["kappa"],
            "uncertaintyHalfWidth": {
                k: v["median_half_width"] for k, v in cal["uncertainty_band_pct_points"].items()
                if isinstance(v, dict)
            },
        },
        "correlation": {"variables": corr["variables"], "matrix": corr["matrix"]},
        "aggregate": {
            "muscleWeights": agg["muscle_weights"],
            "confidenceWeights": agg["confidence_weights"],
            "staleWeight": agg["stale_weight"],
            "machineWeight": agg["machine_weight"],
            "unknownPairCorrelation": agg["unknown_pair_correlation"],
            "sameAnchorCorrelation": agg["same_anchor_correlation"],
            "patternCorrelation": agg["pattern_correlation"],
            "patterns": agg["patterns"],
            "upperPatterns": agg["upper_patterns"],
            "lowerPatterns": agg["lower_patterns"],
            "minPatternsForFullScore": agg["min_patterns_for_full_score"],
        },
        "levels": scoring["levels"],
        "progress": {
            "daysPerMonth": progress["units"]["days_per_month"],
            **{camel(k): _struct(progress[k])
               for k in ("trend", "expected_curve", "score", "plateau", "forecast")},
        },
        # P059 shipped a placeholder matrix; the bundle uses the P057 anchor correlation (`correlation`).
        "imbalance": {
            "minVariables": imb["residual"]["min_variables"],
            "severitySd": _ladder(imb["residual"]["severity_sd"]),
            "unknownPairCorrelation": imb["aggregation"]["unknown_pair_correlation"],
            "confidenceWeights": imb["aggregation"]["confidence_weights"],
            "allowedConfidence": imb["gate"]["allowed_confidence"],
            "excludeMachine": imb["gate"]["exclude_machine"],
            "ratioRules": [
                {
                    "id": r["id"],
                    "groupA": r["group_a"]["name"], "patternsA": r["group_a"]["patterns"],
                    "groupB": r["group_b"]["name"], "patternsB": r["group_b"]["patterns"],
                    "minExercisesPerGroup": r["min_exercises_per_group"],
                    "severityZGap": _ladder(r["severity_z_gap"]),
                }
                for r in imb["ratio_rules"]
            ],
            "severityAsymmetry": _ladder(imb["left_right"]["severity_asymmetry"]),
        },
        "repNorms": rep_norms(),
        "inputClip": input_clip,
    }


def imbalance_draft_with_bundle_correlation() -> dict:
    """The imbalance draft with the bundle's correlation (what Swift sees)."""
    raw = _read("imbalance")
    raw["correlation"] = dict(raw["correlation"], **{
        k: _read("scoring")["anchor_correlation"][k] for k in ("variables", "matrix")
    })
    return raw


def rep_norms() -> list[dict]:
    with REP_NORMS.open(newline="", encoding="utf-8") as f:
        return [
            {
                "exerciseIds": r["exercise_ids"].split(";"),
                "sex": r["sex"],
                "ageMin": int(r["age_min"]),
                "ageMax": int(r["age_max"]),
                "percentile": float(r["percentile"]),
                "reps": float(r["reps"]),
            }
            for r in csv.DictReader(f)
        ]


def build_taxonomy(catalog: dict[str, Exercise], catalog_meta: dict[str, dict]) -> dict:
    rows = []
    for ex in sorted(catalog.values(), key=lambda e: e.id):
        if not ex.scorable:
            continue
        rows.append({
            "id": ex.id,
            "movementPattern": ex.movement_pattern,
            "scoringType": ex.scoring_type,
            "loadConvention": ex.load_convention,
            "anchor": ex.anchor,
            "ratio": ex.ratio,
            "tau": ex.tau,
            "ratioConfidence": ex.ratio_confidence,
            "bwFraction": ex.bw_fraction,
            "isAnchor": ex.is_anchor,
            "isUnilateral": bool(catalog_meta.get(ex.id, {}).get("is_unilateral", False)),
            "primaryMuscles": list(ex.primary_muscles),
            "secondaryMuscles": list(ex.secondary_muscles),
            "equipment": ex.equipment,
        })
    return {"schemaVersion": TAXONOMY_SCHEMA_VERSION, "exercises": rows}


def validate(doc: dict, schema_name: str) -> None:
    schema = json.loads((SCHEMA_DIR / schema_name).read_text(encoding="utf-8"))
    jsonschema.validate(doc, schema)
