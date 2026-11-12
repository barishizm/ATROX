"""P028: catalog build (merge/validate/versioning) and seed (idempotent diff against a fake PostgREST)."""
from __future__ import annotations

import copy
import json
import urllib.parse
from pathlib import Path

import pytest

from catalog import build as cb
from catalog import seed as cs

BASE = [
    {"id": "bench-press", "equipment": "barbell", "mechanic": "compound", "force": "push", "level": "beginner",
     "category": "strength", "primary_muscles": ["chest"], "secondary_muscles": ["triceps"]},
    {"id": "plank", "equipment": "body_only", "mechanic": None, "force": "static", "level": "beginner",
     "category": "strength", "primary_muscles": ["abdominals"], "secondary_muscles": []},
]
TAX = [
    {"id": "bench-press", "movement_pattern": "horizontal_push", "scoring_type": "weighted", "load_convention": "total",
     "is_unilateral": False, "is_core": True, "anchor": None, "ratio": None, "tau": None, "ratio_confidence": None,
     "bw_fraction": None},
    {"id": "plank", "movement_pattern": "core", "scoring_type": "time", "load_convention": None,
     "is_unilateral": False, "is_core": False, "anchor": None, "ratio": None, "tau": None, "ratio_confidence": None,
     "bw_fraction": None},
]


def tr(prefix: str) -> list[dict]:
    return [{"id": e["id"], "name": f"{prefix} {e['id']}", "aliases": [f"{prefix}-alias"], "instructions": ["Do it."]}
            for e in BASE]


MANIFEST = {"exercises": {"bench-press": [{"full": "aa.f.webp", "thumb": "aa.t.webp", "source": "x/0.jpg"}]}}


def merged() -> list[dict]:
    return cb.merge(BASE, TAX, {"en": tr("EN"), "tr": tr("TR")}, MANIFEST)


def test_merge_combines_all_sources():
    bench, plank = merged()
    assert bench["movement_pattern"] == "horizontal_push" and bench["is_core"] is True
    assert bench["images"] == ["aa.f.webp"] and plank["images"] == []
    assert bench["translations"]["tr"]["name"] == "TR bench-press"
    assert set(bench["translations"]) == {"en", "tr"}
    assert cb.validate(merged()) == []


def test_validate_flags_unknown_vocabulary_and_partial_scoring():
    ex = merged()
    ex[0]["equipment"] = "body only"
    ex[0]["primary_muscles"] = ["lower back"]
    ex[0]["ratio"] = 1.0  # anchor/tau/confidence still null
    ex[1]["translations"]["tr"]["name"] = " "
    errors = "\n".join(cb.validate(ex))
    assert "equipment='body only'" in errors and "lower back" in errors
    assert "partially filled" in errors and "empty tr name" in errors


def test_checksum_is_stable_and_order_independent_of_keys():
    a = merged()
    b = [dict(reversed(list(e.items()))) for e in a]
    assert cb.checksum(a) == cb.checksum(b)
    c = copy.deepcopy(a)
    c[0]["translations"]["en"]["name"] = "changed"
    assert cb.checksum(a) != cb.checksum(c)


def test_version_bumps_only_when_content_changes(tmp_path: Path):
    vf = tmp_path / "v.json"
    ex = merged()
    assert cb.assign_version(ex, vf)[::2] == (1, True)
    assert cb.assign_version(ex, vf)[::2] == (1, False)  # unchanged -> same version
    ex[0]["level"] = "expert"
    assert cb.assign_version(ex, vf)[::2] == (2, True)


def test_render_roundtrip_and_header():
    ex = merged()
    doc = json.loads(cb.render(3, cb.checksum(ex), ex))
    assert doc["version"] == 3 and doc["format"] == cb.FORMAT and len(doc["exercises"]) == 2


# --- seed ---------------------------------------------------------------------------------------------------------

class FakePostgrest:
    """Just enough PostgREST: GET with limit/offset, POST upsert, PATCH id=in.(...)."""

    def __init__(self) -> None:
        self.tables: dict[str, list[dict]] = {"exercises": [], "exercise_translations": [], "catalog_versions": []}
        self.writes: list[tuple[str, str, int]] = []

    def __call__(self, method, url, headers, body):
        parsed = urllib.parse.urlparse(url)
        table = parsed.path.rsplit("/", 1)[1]
        qs = urllib.parse.parse_qs(parsed.query)
        rows = self.tables[table]
        data = json.loads(body) if body else None
        if method == "GET":
            off, lim = int(qs["offset"][0]), int(qs["limit"][0])
            return 200, json.dumps(rows[off:off + lim]).encode()
        if method == "POST":
            keys = {"exercises": ("id",), "exercise_translations": ("exercise_id", "locale"),
                    "catalog_versions": ("version",)}[table]
            for item in data:
                for i, r in enumerate(rows):
                    if all(r[k] == item[k] for k in keys):
                        rows[i] = {**r, **item}
                        break
                else:
                    rows.append(dict(item))
            self.writes.append((method, table, len(data)))
            return 201, b""
        if method == "PATCH":
            ids = qs["id"][0].removeprefix("in.(").removesuffix(")").replace('"', "").split(",")
            for r in rows:
                if r["id"] in ids:
                    r.update(data)
            self.writes.append((method, table, len(ids)))
            return 204, b""
        return 405, b""


def catalog(version=1, exercises=None) -> dict:
    ex = exercises or merged()
    return {"format": 1, "version": version, "checksum": cb.checksum(ex), "exercises": ex}


def test_seed_is_idempotent():
    fake = FakePostgrest()
    rest = cs.Rest("https://x.supabase.co", "k", fake)
    first = cs.seed(catalog(), rest)
    assert first == {"exercises": 2, "translations": 4, "archived": 0, "revived": 0, "version_published": 1}
    assert len(fake.tables["exercises"]) == 2 and len(fake.tables["exercise_translations"]) == 4
    assert fake.tables["exercises"][0]["image_paths"] == ["aa.f.webp"]
    fake.writes.clear()
    second = cs.seed(catalog(), rest)
    assert second == {"exercises": 0, "translations": 0, "archived": 0, "revived": 0, "version_published": 0}
    assert fake.writes == []  # nothing written -> updated_at on the server does not move


def test_seed_dry_run_writes_nothing():
    fake = FakePostgrest()
    summary = cs.seed(catalog(), cs.Rest("https://x", "k", fake), dry_run=True)
    assert summary["exercises"] == 2 and fake.writes == []


def test_translation_change_rewrites_only_that_exercise():
    fake = FakePostgrest()
    rest = cs.Rest("https://x", "k", fake)
    cs.seed(catalog(), rest)
    ex = merged()
    ex[1]["translations"]["tr"]["name"] = "Plank (yeni)"
    s = cs.seed(catalog(2, ex), rest)
    assert s["exercises"] == 1 and s["translations"] == 1 and s["version_published"] == 1
    assert {v["version"] for v in fake.tables["catalog_versions"]} == {1, 2}


def test_removed_exercise_is_archived_and_revived_when_it_returns():
    fake = FakePostgrest()
    rest = cs.Rest("https://x", "k", fake)
    cs.seed(catalog(), rest)
    s = cs.seed(catalog(2, merged()[:1]), rest, now=lambda: "2026-01-01T00:00:00+00:00")
    assert s["archived"] == 1
    plank = next(r for r in fake.tables["exercises"] if r["id"] == "plank")
    assert plank["archived_at"] == "2026-01-01T00:00:00+00:00"  # kept, not deleted
    s = cs.seed(catalog(3, merged()), rest)
    assert s["revived"] == 1
    assert next(r for r in fake.tables["exercises"] if r["id"] == "plank")["archived_at"] is None


def test_seed_refuses_changed_content_under_published_version_and_older_versions():
    fake = FakePostgrest()
    rest = cs.Rest("https://x", "k", fake)
    cs.seed(catalog(2), rest)
    ex = merged()
    ex[0]["level"] = "expert"
    with pytest.raises(RuntimeError, match="different checksum"):
        cs.seed(catalog(2, ex), rest)
    with pytest.raises(RuntimeError, match="newer"):
        cs.seed(catalog(1), rest)


def test_http_error_surfaces():
    rest = cs.Rest("https://x", "k", lambda *a: (401, b'{"message":"bad key"}'))
    with pytest.raises(RuntimeError, match="HTTP 401"):
        cs.seed(catalog(), rest)


def test_pagination_reads_every_row():
    fake = FakePostgrest()
    fake.tables["catalog_versions"] = [{"version": i, "checksum": str(i)} for i in range(1, 2501)]
    assert len(cs.Rest("https://x", "k", fake).get_all("catalog_versions?select=version,checksum")) == 2500


def test_real_catalog_builds_and_validates():
    """The committed pipeline outputs merge into a valid 876-exercise catalog (no network)."""
    out = cb.OUT
    if not (out / "image_manifest.json").exists():
        pytest.skip("pipeline outputs not present")
    import yaml
    load = lambda n: json.loads((out / n).read_text(encoding="utf-8"))  # noqa: E731
    tax = yaml.safe_load((cb.ROOT / "scoring_taxonomy.yaml").read_text(encoding="utf-8"))["exercises"]
    ex = cb.merge(load("exercises.base.json"), tax, {l: load(f"exercises.{l}.json") for l in cb.LOCALES},
                  load("image_manifest.json"))
    assert len(ex) == 876 and cb.validate(ex) == []
