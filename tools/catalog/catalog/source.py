"""Download free-exercise-db pinned to one commit and verify its license."""
from __future__ import annotations

import hashlib
import json
import urllib.request
from dataclasses import dataclass
from pathlib import Path

REPO = "yuhonas/free-exercise-db"
PINNED_COMMIT = "f00c92c7dcf1216a928a52c3706c7ce8e2f71ed5"
RAW = f"https://raw.githubusercontent.com/{REPO}/{PINNED_COMMIT}"
TREE_URL = f"https://api.github.com/repos/{REPO}/git/trees/{PINNED_COMMIT}?recursive=1"
IMAGE_PREFIX = "exercises/"


class LicenseError(RuntimeError):
    pass


def check_license(text: str) -> None:
    """The upstream LICENSE must be the Unlicense (public domain dedication)."""
    if "free and unencumbered software released into the public domain" not in text \
            or "unlicense.org" not in text:
        raise LicenseError("LICENSE.md is not the Unlicense; refusing to import")


def _get(url: str) -> bytes:
    req = urllib.request.Request(url, headers={"User-Agent": "atrox-catalog-import"})
    with urllib.request.urlopen(req, timeout=60) as r:  # noqa: S310 - fixed https URLs
        return r.read()


@dataclass
class Source:
    exercises: list[dict]
    license_text: str
    image_paths: set[str]  # paths relative to the exercises/ directory, e.g. "Ab_Roller/0.jpg"
    exercises_sha256: str


def fetch(cache_dir: Path) -> Source:
    cache_dir.mkdir(parents=True, exist_ok=True)
    files = {
        "exercises.json": f"{RAW}/dist/exercises.json",
        "LICENSE.md": f"{RAW}/LICENSE.md",
        "tree.json": TREE_URL,
    }
    for name, url in files.items():
        target = cache_dir / f"{PINNED_COMMIT[:12]}-{name}"
        if not target.exists():
            target.write_bytes(_get(url))
    return load_cached(cache_dir)


def load_cached(cache_dir: Path) -> Source:
    p = PINNED_COMMIT[:12]
    raw = (cache_dir / f"{p}-exercises.json").read_bytes()
    license_text = (cache_dir / f"{p}-LICENSE.md").read_text(encoding="utf-8")
    check_license(license_text)
    tree = json.loads((cache_dir / f"{p}-tree.json").read_text(encoding="utf-8"))
    if tree.get("truncated"):
        raise RuntimeError("git tree listing truncated; cannot verify images")
    images = {t["path"][len(IMAGE_PREFIX):] for t in tree["tree"]
              if t["type"] == "blob" and t["path"].startswith(IMAGE_PREFIX) and t["path"].endswith((".jpg", ".png"))}
    return Source(json.loads(raw), license_text, images, hashlib.sha256(raw).hexdigest())
