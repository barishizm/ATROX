"""P060: model bundle export (no pickles needed: works from the committed embedded bundle)."""
# ruff: noqa: E501

from __future__ import annotations

import json
import shutil

import numpy as np
import pytest
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey

from gymml import imbalance, progress
from gymml.export import anchor_tables, bundle, golden, keys, params
from gymml.models.spline_lms import SplineLMS, SplineLMSConfig, _SexFit
from gymml.scoring import AnchorModel, Params
from gymml.scoring_run import TAXONOMY, load_catalog

EMBEDDED = bundle.EMBEDDED


def _read(name: str) -> dict:
    return json.loads((EMBEDDED / name).read_text(encoding="utf-8"))


def test_embedded_bundle_signature_and_digests():
    m = keys.verify_bundle(EMBEDDED)
    assert set(m["files"]) == {"anchor_tables.json", "params.json", "smoke.json", "taxonomy.json"}
    params.validate(m, "manifest.schema.json")


def test_tampered_bundle_is_rejected(tmp_path):
    copy = tmp_path / "b"
    shutil.copytree(EMBEDDED, copy)
    p = copy / "params.json"
    p.write_text(p.read_text().replace('"windowDays":42', '"windowDays":43'))
    with pytest.raises(ValueError, match="SHA-256"):
        keys.verify_bundle(copy)
    m = copy / "manifest.json"
    m.write_text(m.read_text().replace('"1.0.0"', '"9.9.9"', 1))
    with pytest.raises(ValueError, match="signature"):
        keys.verify_bundle(copy)


def test_sign_roundtrip_with_fresh_key(tmp_path):
    copy = tmp_path / "b"
    shutil.copytree(EMBEDDED, copy)
    key = Ed25519PrivateKey.generate()
    keys.sign_bundle(copy, key)
    keys.verify_bundle(copy, keys.public_b64(key.public_key()))
    with pytest.raises(ValueError):
        keys.verify_bundle(copy)  # pinned key does not match the fresh one


def test_params_match_drafts_and_schema():
    committed = _read("params.json")
    params.validate(committed, "params.schema.json")
    assert params.build_params(committed["inputClip"]) == committed


def test_taxonomy_only_scorable_rows():
    rows = _read("taxonomy.json")["exercises"]
    cat = load_catalog()
    assert {r["id"] for r in rows} == {e.id for e in cat.values() if e.scorable}
    bench = next(r for r in rows if r["id"] == "barbell-bench-press-medium-grip")
    assert bench["isAnchor"] and bench["anchor"] == "bench" and bench["ratio"] == 1.0
    assert TAXONOMY.exists()


def test_table_lift_matches_spline_lms():
    cfg = SplineLMSConfig(age_segments=5, bw_segments=4)
    m = SplineLMS(cfg)
    rng = np.random.default_rng(0)
    base = {"mu": 4.5, "sigma": -1.6, "nu": 0.5, "tau": 0.6}
    for sex in ("M", "F"):
        m.fits[sex] = _SexFit({k: v + 0.1 * rng.normal(size=(m.ka, m.kw)) for k, v in base.items()}, [])
    tables = anchor_tables.tables_from_models({lift: m for lift in anchor_tables.LIFTS})
    res = anchor_tables.parity({lift: m for lift in anchor_tables.LIFTS}, tables, n=300)
    assert max(v[k] for lift, v in res.items() if lift != "n" for k in v) < 1e-10


def _assert_close(a, b, path: str) -> None:
    if isinstance(a, float) or isinstance(b, float):
        assert a == pytest.approx(b, rel=1e-9, abs=1e-9), path
    elif isinstance(a, dict):
        assert a.keys() == b.keys(), path
        for k in a:
            _assert_close(a[k], b[k], f"{path}.{k}")
    elif isinstance(a, list):
        assert len(a) == len(b), path
        for i, (x, y) in enumerate(zip(a, b, strict=True)):
            _assert_close(x, y, f"{path}[{i}]")
    else:
        assert a == b, path


def test_golden_vectors_reproduce_from_committed_bundle(tmp_path):
    p = Params.load()
    model = AnchorModel(anchor_tables.table_models(_read("anchor_tables.json")), p)
    pp = progress.params_from_dict(json.loads(progress.DEFAULT_PARAMS_PATH.read_text()))
    ip = imbalance.ImbalanceParams.from_dict(params.imbalance_draft_with_bundle_correlation())
    counts = golden.write_all(load_catalog(), model, p, pp, ip, out=tmp_path)
    assert all(n > 0 for n in counts.values())
    for name in counts:
        new = json.loads((tmp_path / f"{name}.json").read_text())
        old = json.loads((golden.GOLDEN_DIR / f"{name}.json").read_text())
        _assert_close(new, old, name)
    smoke = _read("smoke.json")
    e2e = json.loads((golden.GOLDEN_DIR / "end_to_end.json").read_text())
    assert smoke["cases"] == e2e["cases"][: bundle.SMOKE_CASES]


def test_publish_uploads_every_file_then_inserts_inactive_row():
    from gymml.export import publish

    calls = []

    def transport(method, url, headers, body):
        calls.append((method, url, headers, body))
        return 200

    row = publish.publish(EMBEDDED, "https://example.supabase.co/", "service-key", rollout=10, transport=transport)
    uploads = [c[1].rsplit("/", 1)[1] for c in calls[:-1]]
    assert uploads == ["manifest.json", "manifest.sig", "anchor_tables.json", "params.json", "smoke.json", "taxonomy.json"]
    assert all("/storage/v1/object/model-bundles/v1.0.0/" in c[1] for c in calls[:-1])
    assert calls[-1][1] == "https://example.supabase.co/rest/v1/model_versions"
    assert json.loads(calls[-1][3]) == row
    assert row["is_active"] is False and row["rollout_percent"] == 10
    assert row["manifest_sha256"] == keys.sha256(EMBEDDED / "manifest.json")


def test_publish_refuses_tampered_bundle(tmp_path):
    from gymml.export import publish

    copy = tmp_path / "b"
    shutil.copytree(EMBEDDED, copy)
    (copy / "taxonomy.json").write_text("{}")
    with pytest.raises(ValueError):
        publish.publish(copy, "https://x", "k", transport=lambda *a: 200)
