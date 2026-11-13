"""P060: `make export` — signed model bundle + golden vectors.

    uv run python -m gymml.export.bundle [--version 1.0.0] [--min-app 1.0.0] [--no-sign]

Steps: P053 winner pickles -> `anchor_tables.json` (+ parity on 2,000 random inputs, target < 1e-4)
-> `params.json` (JSON Schema validated) + `taxonomy.json` -> golden vectors (`ml/golden/`) and the
bundle's `smoke.json` subset -> `manifest.json` (SHA-256 of every file) -> `manifest.sig` (Ed25519)
-> verify -> copy to the StrengthKit embedded bundle.
"""
# ruff: noqa: E501

from __future__ import annotations

import argparse
import json
import pickle
import shutil
import sys
from datetime import date
from pathlib import Path

import yaml

from gymml import imbalance, progress
from gymml.export import anchor_tables, golden, keys, params
from gymml.scoring import AnchorModel, Params
from gymml.scoring_run import TAXONOMY, load_catalog

ML_ROOT = Path(__file__).resolve().parents[3]
REPO = ML_ROOT.parent
DIST = ML_ROOT / "dist"
EMBEDDED = REPO / "ios/Packages/StrengthKit/Sources/StrengthKit/Resources/ModelBundle"
FORMAT = "atrox-model-bundle/1"
SMOKE_CASES = 5
PARITY_TARGET = 1e-4


def _dump(path: Path, doc: dict) -> None:
    path.write_text(json.dumps(doc, ensure_ascii=False, allow_nan=False, separators=(",", ":")) + "\n",
                    encoding="utf-8")


def _load_winner(p: Params) -> dict:
    cfg = p.scoring["anchor_model"]
    out = {}
    for lift in anchor_tables.LIFTS:
        path = ML_ROOT / cfg["pickle_pattern"].format(key=cfg["key"], lift=lift)
        with path.open("rb") as f:
            out[lift] = pickle.load(f)
    return out


def _test_metrics() -> dict:
    final = json.loads((ML_ROOT / "reports/bakeoff/final_A.json").read_text(encoding="utf-8"))
    lifts = final["test"]["1"]["lifts"]
    return {
        lift: {k: lifts[lift]["metrics"][k] for k in ("n", "pinball", "pit_ks", "coverage_gate_pass")}
        for lift in anchor_tables.LIFTS
    }


def build(version: str, min_app: str, sign: bool) -> Path:
    p = Params.load()
    winner = _load_winner(p)
    tables = anchor_tables.tables_from_models(winner)
    parity = anchor_tables.parity(winner, tables)
    worst = max(v[m] for k, v in parity.items() if k != "n" for m in v)
    if worst >= PARITY_TARGET:
        raise SystemExit(f"anchor table parity {worst:.2e} >= {PARITY_TARGET}")

    out = DIST / f"model-bundle-v{version}"
    if out.exists():
        shutil.rmtree(out)
    out.mkdir(parents=True)

    clip = next(iter(winner.values())).to_dict()["clip"]
    pj = params.build_params({"age": clip["age"], "bodyweightKg": clip["bodyweight_kg"]})
    params.validate(pj, "params.schema.json")
    _dump(out / "params.json", pj)
    _dump(out / "anchor_tables.json", tables)

    cat = load_catalog()
    tax_rows = {r["id"]: r for r in yaml.safe_load(TAXONOMY.read_text(encoding="utf-8"))["exercises"]}
    _dump(out / "taxonomy.json", params.build_taxonomy(cat, tax_rows))

    model = AnchorModel(anchor_tables.table_models(tables), p)
    pp = progress.params_from_dict(json.loads(progress.DEFAULT_PARAMS_PATH.read_text(encoding="utf-8")))
    ip = imbalance.ImbalanceParams.from_dict(params.imbalance_draft_with_bundle_correlation())
    counts = golden.write_all(cat, model, p, pp, ip)
    e2e = json.loads((golden.GOLDEN_DIR / "end_to_end.json").read_text(encoding="utf-8"))
    e2e["cases"] = e2e["cases"][:SMOKE_CASES]
    _dump(out / "smoke.json", e2e)

    files = sorted(f.name for f in out.iterdir())
    manifest = {
        "format": FORMAT,
        "version": version,
        "schemaVersion": params.PARAMS_SCHEMA_VERSION,
        "minAppVersion": min_app,
        "createdAt": date.today().isoformat(),
        "anchor": {"kind": "tables", "file": "anchor_tables.json", "model": "A · Spline-LMS (BCPE), P053"},
        "files": {name: keys.sha256(out / name) for name in files},
        "trainingData": {
            "source": "OpenPowerlifting (Raw + Wraps, Tested sensitivity), see ml/data/SOURCES.md",
            "cohort": "P048 athlete-year best per lift, ages 14-85, bodyweight 30-250 kg",
            "split": "athlete-grouped 70/15/15, seed 20260101",
        },
        "metrics": {"test_seed1": _test_metrics(), "export_parity": parity, "golden_cases": counts},
    }
    params.validate(manifest, "manifest.schema.json")
    _dump(out / keys.MANIFEST, manifest)
    if sign:
        keys.sign_bundle(out, keys.load_private())
        keys.verify_bundle(out)
        if EMBEDDED.exists():
            shutil.rmtree(EMBEDDED)
        shutil.copytree(out, EMBEDDED)
    print(json.dumps({"bundle": str(out), "parity": parity, "golden": counts}, indent=2))
    return out


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(prog="gymml.export.bundle")
    ap.add_argument("--version", default="1.0.0")
    ap.add_argument("--min-app", default="1.0.0")
    ap.add_argument("--no-sign", action="store_true", help="skip signing (no private key needed)")
    args = ap.parse_args(argv)
    build(args.version, args.min_app, not args.no_sign)
    return 0


if __name__ == "__main__":
    sys.exit(main())
