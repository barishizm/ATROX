import json
from pathlib import Path

from PIL import Image

from catalog import images


def _jpg(path: Path, size=(850, 567), color=(200, 30, 30)):
    path.parent.mkdir(parents=True, exist_ok=True)
    Image.new("RGB", size, color).save(path, "JPEG")


def _setup(tmp_path):
    src, out = tmp_path / "src", tmp_path / "out"
    _jpg(src / "A/0.jpg"); _jpg(src / "A/1.jpg", color=(0, 0, 200)); _jpg(src / "B/0.jpg", size=(400, 300))
    base = [{"id": "a", "images": ["A/0.jpg", "A/1.jpg"]}, {"id": "b", "images": ["B/0.jpg"]},
            {"id": "c", "images": []}, {"id": "d", "images": ["D/0.jpg"]}]
    return src, out, base


def test_sizes_and_no_upscale(tmp_path):
    src, out, base = _setup(tmp_path)
    m = images.build(base, src, out, {"a"})
    a0 = m["exercises"]["a"][0]
    assert m["files"][a0["thumb"]]["w"] == 320
    assert m["files"][a0["full"]]["w"] == 850  # capped at source width
    b0 = m["exercises"]["b"][0]
    assert m["files"][b0["thumb"]]["w"] == 320 and m["files"][b0["full"]]["w"] == 400
    with Image.open(out / a0["thumb"]) as im:
        assert im.format == "WEBP"


def test_content_addressed_and_idempotent(tmp_path):
    src, out, base = _setup(tmp_path)
    m1 = images.build(base, src, out, set())
    mtimes = {p.name: p.stat().st_mtime_ns for p in out.iterdir()}
    m2 = images.build(base, src, out, set())
    assert m1 == m2
    assert mtimes == {p.name: p.stat().st_mtime_ns for p in out.iterdir()}  # nothing re-encoded
    _jpg(src / "A/0.jpg", color=(1, 2, 3))
    m3 = images.build(base, src, out, set())
    assert m3["exercises"]["a"][0]["thumb"] != m1["exercises"]["a"][0]["thumb"]
    assert m3["exercises"]["a"][1] == m1["exercises"]["a"][1]


def test_identical_sources_dedupe(tmp_path):
    src, out, _ = _setup(tmp_path)
    (src / "C").mkdir(); (src / "C/0.jpg").write_bytes((src / "A/0.jpg").read_bytes())
    m = images.build([{"id": "a", "images": ["A/0.jpg"]}, {"id": "c", "images": ["C/0.jpg"]}], src, out, set())
    assert m["exercises"]["a"][0]["thumb"] == m["exercises"]["c"][0]["thumb"]
    assert len(m["files"]) == 2


def test_report_and_bundle(tmp_path):
    src, out, base = _setup(tmp_path)
    m = images.build(base, src, out, {"a", "c"})
    assert len(m["bundled"]) == 2  # thumbs only, core only
    r = images.make_report(m, {"a", "c"})
    assert r["exercises_without_images"] == ["c", "d"]
    assert r["core_without_images"] == ["c"]
    assert r["missing_source_files"] == ["D/0.jpg"]
    assert r["images_per_exercise"] == {"0": 2, "1": 1, "2": 1}
    assert r["bundle_within_budget"] and "Core exercises without images: 1" in images.render_report(r)
    bundle = tmp_path / "bundle"; (bundle).mkdir(); (bundle / "stale.webp").write_bytes(b"x")
    images.sync_bundle(m, out, bundle)
    assert sorted(p.name for p in bundle.iterdir()) == sorted(m["bundled"])


def test_upload_only_missing(tmp_path):
    src, out, base = _setup(tmp_path)
    m = images.build(base, src, out, set())
    names = list(m["files"])
    present = {names[0]}
    put = []
    res = images.upload(m, out, "https://x.supabase.co/", "k", exists=lambda b, n: n in present,
                        put=lambda b, k, n, d: put.append((b, n, len(d) > 0)))
    assert res["skipped"] == [names[0]] and len(res["uploaded"]) == len(names) - 1
    assert all(b == "https://x.supabase.co" for b, _, _ in put) and len(put) == len(names) - 1
    put.clear()
    images.upload(m, out, "https://x", "k", dry_run=True, exists=lambda b, n: False, put=lambda *a: put.append(a))
    assert put == []


def test_real_manifest_if_present():
    p = images.ROOT / "out/image_manifest.json"
    m = json.loads(p.read_text())
    r = images.make_report(m, images.core_ids(images.ROOT / "scoring_taxonomy.yaml"))
    assert r["bundle_within_budget"] and not r["core_without_images"] and not r["missing_source_files"]
