"""catalog-images: source JPGs -> content-addressed WebP thumbnails/full images, manifest, report, Storage upload.

Format decision (measured on 30 random source images, mean bytes per file):
  source JPG 50.9 KB | WebP q75: 320 px 7.7 KB, 850 px 27.9 KB | HEIC q60: 320 px 11.2 KB, 850 px 39.4 KB
WebP is ~30% smaller than HEIC here, decodes natively in SwiftUI/ImageIO on iOS 14+, and is produced by Pillow
without platform tools, so the pipeline runs on any machine/CI. The upstream sources are 850 px wide, so the
"full" size is capped at the source width (never upscaled) instead of 960 px.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import shutil
import sys
import urllib.error
import urllib.parse
import urllib.request
from dataclasses import dataclass
from pathlib import Path

import yaml
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
REPO_ROOT = ROOT.parent.parent
BUCKET = "exercise-images"
THUMB_WIDTH = 320
FULL_WIDTH = 960  # upper bound; sources are narrower and are never upscaled
WEBP_QUALITY = 75
RECIPE = f"webp-q{WEBP_QUALITY}-t{THUMB_WIDTH}-f{FULL_WIDTH}-m6"  # change => all file names change
CACHE_CONTROL = "max-age=31536000"  # Supabase Storage sets the header from this value
BUNDLE_BUDGET_BYTES = 15 * 1024 * 1024
DEFAULT_BUNDLE_DIR = REPO_ROOT / "ios/App/Resources/ExerciseThumbs"


@dataclass(frozen=True)
class Variant:
    name: str  # file name inside the bucket
    width: int
    height: int
    bytes: int


def content_hash(data: bytes) -> str:
    return hashlib.sha256(RECIPE.encode() + b"\0" + data).hexdigest()[:16]


def _encode(im: Image.Image, width: int, dest: Path) -> Variant:
    if im.width > width:
        im = im.resize((width, max(1, round(im.height * width / im.width))), Image.LANCZOS)
    dest.parent.mkdir(parents=True, exist_ok=True)
    tmp = dest.with_suffix(".tmp")
    im.save(tmp, "WEBP", quality=WEBP_QUALITY, method=6)
    os.replace(tmp, dest)
    return Variant(dest.name, im.width, im.height, dest.stat().st_size)


def process_image(src: Path, out_dir: Path) -> dict:
    """Returns {"thumb": Variant, "full": Variant, "src_bytes": int}; skips files that already exist."""
    data = src.read_bytes()
    h = content_hash(data)
    res: dict = {"src_bytes": len(data)}
    im = None
    for key, width, suffix in (("thumb", THUMB_WIDTH, "t"), ("full", FULL_WIDTH, "f")):
        dest = out_dir / f"{h}.{suffix}.webp"
        if dest.exists():
            with Image.open(dest) as e:
                res[key] = Variant(dest.name, e.width, e.height, dest.stat().st_size)
            continue
        if im is None:
            im = Image.open(src).convert("RGB")
        res[key] = _encode(im, width, dest)
    return res


def core_ids(taxonomy_path: Path) -> set[str]:
    doc = yaml.safe_load(taxonomy_path.read_text(encoding="utf-8"))
    return {e["id"] for e in doc["exercises"] if e["is_core"]}


def build(base: list[dict], src_dir: Path, out_dir: Path, core: set[str]) -> dict:
    """Process every referenced image; returns the manifest dict."""
    exercises: dict[str, list[dict]] = {}
    missing_files: list[str] = []
    files: dict[str, Variant] = {}
    cache: dict[str, dict] = {}
    for ex in base:
        entries = []
        for rel in ex.get("images") or []:
            src = src_dir / rel
            if not src.exists():
                missing_files.append(rel)
                continue
            if rel not in cache:
                cache[rel] = process_image(src, out_dir)
            r = cache[rel]
            files[r["thumb"].name] = r["thumb"]
            files[r["full"].name] = r["full"]
            entries.append({"thumb": r["thumb"].name, "full": r["full"].name, "source": rel})
        exercises[ex["id"]] = entries
    bundled = sorted({e["thumb"] for i in core for e in exercises.get(i, [])})
    return {
        "recipe": RECIPE,
        "bucket": BUCKET,
        "cache_control": CACHE_CONTROL,
        "exercises": exercises,
        "files": {n: {"w": v.width, "h": v.height, "bytes": v.bytes} for n, v in sorted(files.items())},
        "bundled": bundled,
        "missing_source_files": sorted(missing_files),
    }


def make_report(manifest: dict, core: set[str]) -> dict:
    files, ex = manifest["files"], manifest["exercises"]
    thumbs = {n for n in files if n.endswith(".t.webp")}
    fulls = {n for n in files if n.endswith(".f.webp")}
    per_count: dict[int, int] = {}
    for entries in ex.values():
        per_count[len(entries)] = per_count.get(len(entries), 0) + 1
    bundle_bytes = sum(files[n]["bytes"] for n in manifest["bundled"])
    return {
        "exercise_count": len(ex),
        "images_per_exercise": {str(k): v for k, v in sorted(per_count.items())},
        "exercises_without_images": sorted(i for i, e in ex.items() if not e),
        "core_without_images": sorted(i for i in core if not ex.get(i)),
        "missing_source_files": manifest["missing_source_files"],
        "unique_files": len(files),
        "thumb_total_bytes": sum(files[n]["bytes"] for n in thumbs),
        "full_total_bytes": sum(files[n]["bytes"] for n in fulls),
        "total_bytes": sum(v["bytes"] for v in files.values()),
        "bundle_files": len(manifest["bundled"]),
        "bundle_bytes": bundle_bytes,
        "bundle_budget_bytes": BUNDLE_BUDGET_BYTES,
        "bundle_within_budget": bundle_bytes < BUNDLE_BUDGET_BYTES,
    }


def render_report(r: dict) -> str:
    mb = lambda b: f"{b / 1048576:.2f} MB"  # noqa: E731
    lines = [
        "# Image processing report (P027)", "",
        f"- Exercises: {r['exercise_count']}; unique files: {r['unique_files']}",
        f"- Thumbnails: {mb(r['thumb_total_bytes'])}; full images: {mb(r['full_total_bytes'])}; total: {mb(r['total_bytes'])}",
        f"- App bundle (core thumbnails): {r['bundle_files']} files, {mb(r['bundle_bytes'])} "
        f"(budget {mb(r['bundle_budget_bytes'])}, {'OK' if r['bundle_within_budget'] else 'OVER BUDGET'})",
        "- Images per exercise: " + ", ".join(f"{k}→{v}" for k, v in r["images_per_exercise"].items()),
        f"- Exercises without images: {len(r['exercises_without_images'])}",
        f"- Core exercises without images: {len(r['core_without_images'])}",
        f"- Missing source files: {len(r['missing_source_files'])}",
    ]
    for key, title in (("exercises_without_images", "Exercises without images"),
                       ("core_without_images", "Core exercises without images"),
                       ("missing_source_files", "Missing source files")):
        if r[key]:
            lines += ["", f"## {title}", ""] + [f"- `{i}`" for i in r[key]]
    return "\n".join(lines) + "\n"


def sync_bundle(manifest: dict, out_dir: Path, bundle_dir: Path) -> None:
    """Make bundle_dir contain exactly the manifest's bundled thumbnails."""
    bundle_dir.mkdir(parents=True, exist_ok=True)
    want = set(manifest["bundled"])
    for f in bundle_dir.glob("*.webp"):
        if f.name not in want:
            f.unlink()
    for n in want:
        dest = bundle_dir / n
        if not dest.exists():
            shutil.copyfile(out_dir / n, dest)


# --- Supabase Storage upload ---------------------------------------------------------------------------------

def _object_url(base: str, name: str, public: bool) -> str:
    kind = "public/" if public else ""
    return f"{base}/storage/v1/object/{kind}{BUCKET}/{urllib.parse.quote(name)}"


def remote_exists(base: str, name: str) -> bool:
    req = urllib.request.Request(_object_url(base, name, True), method="HEAD")
    try:
        with urllib.request.urlopen(req, timeout=30):  # noqa: S310
            return True
    except urllib.error.HTTPError as e:
        if e.code in (400, 404):
            return False
        raise


def upload_one(base: str, key: str, name: str, data: bytes) -> None:
    req = urllib.request.Request(
        _object_url(base, name, False), data=data, method="POST",
        headers={"Authorization": f"Bearer {key}", "apikey": key, "Content-Type": "image/webp",
                 "Cache-Control": CACHE_CONTROL,
                 "x-upsert": "false"})
    try:
        urllib.request.urlopen(req, timeout=60).close()  # noqa: S310
    except urllib.error.HTTPError as e:
        if e.code == 409:  # already there (content-addressed => identical)
            return
        raise


def upload(manifest: dict, out_dir: Path, base: str, key: str, *, dry_run: bool = False,
           exists=remote_exists, put=upload_one) -> dict:
    """Upload only files missing in the bucket. Names are content hashes, so 'exists' means 'unchanged'."""
    base = base.rstrip("/")
    uploaded, skipped = [], []
    for name in manifest["files"]:
        if exists(base, name):
            skipped.append(name)
            continue
        if not dry_run:
            put(base, key, name, (out_dir / name).read_bytes())
        uploaded.append(name)
    return {"uploaded": uploaded, "skipped": skipped, "dry_run": dry_run}


# --- CLI -------------------------------------------------------------------------------------------------------

def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(prog="catalog-images")
    sub = ap.add_subparsers(dest="cmd", required=True)
    b = sub.add_parser("build", help="convert images, write manifest/report, sync app bundle thumbnails")
    b.add_argument("--src", type=Path, default=ROOT / "cache/images")
    b.add_argument("--out", type=Path, default=ROOT / "cache/images-out", help="gitignored WebP output")
    b.add_argument("--bundle-dir", type=Path, default=DEFAULT_BUNDLE_DIR)
    u = sub.add_parser("upload", help="upload files missing from the Supabase Storage bucket")
    u.add_argument("--out", type=Path, default=ROOT / "cache/images-out")
    u.add_argument("--dry-run", action="store_true")
    a = ap.parse_args(argv)

    manifest_path = ROOT / "out/image_manifest.json"
    if a.cmd == "build":
        base = json.loads((ROOT / "out/exercises.base.json").read_text(encoding="utf-8"))
        core = core_ids(ROOT / "scoring_taxonomy.yaml")
        manifest = build(base, a.src, a.out, core)
        manifest_path.write_text(json.dumps(manifest, indent=1, sort_keys=True, ensure_ascii=False) + "\n", encoding="utf-8")
        rep = make_report(manifest, core)
        (ROOT / "out/image_report.json").write_text(json.dumps(rep, indent=1, ensure_ascii=False) + "\n", encoding="utf-8")
        (ROOT / "out/image_report.md").write_text(render_report(rep), encoding="utf-8")
        sync_bundle(manifest, a.out, a.bundle_dir)
        print(render_report(rep))
        return 0 if rep["bundle_within_budget"] and not rep["missing_source_files"] else 1

    base_url, key = os.environ.get("SUPABASE_URL", ""), os.environ.get("SUPABASE_SERVICE_ROLE_KEY", "")
    if not base_url or (not key and not a.dry_run):
        print("SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY must be set", file=sys.stderr)
        return 2
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    res = upload(manifest, a.out, base_url, key, dry_run=a.dry_run)
    print(f"{'would upload' if a.dry_run else 'uploaded'} {len(res['uploaded'])}, unchanged {len(res['skipped'])}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
