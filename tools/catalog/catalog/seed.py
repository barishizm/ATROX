"""catalog-seed (P028): push out/catalog.v{N}.json to Supabase (exercises, exercise_translations, catalog_versions).

Idempotent and incremental: only rows that differ from the server are written, so `updated_at` (which the app uses to
fetch changes) moves only for real changes. Exercises missing from the catalog are *archived* (`archived_at`), never
deleted, because workouts reference them. The catalog_versions row is written last, so a client that sees version N
is guaranteed to find all of its data. Needs SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY (service role = write access).
"""
from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path
from typing import Any, Callable

ROOT = Path(__file__).resolve().parent.parent
BATCH = 200
PAGE = 1000

EXERCISE_COLUMNS = (
    "equipment", "mechanic", "force", "level", "category", "primary_muscles", "secondary_muscles",
    "movement_pattern", "scoring_type", "anchor_lift", "load_convention", "ratio", "tau", "ratio_confidence",
    "bw_fraction", "is_core", "is_unilateral",
)
TRANSLATION_COLUMNS = ("name", "aliases", "instructions")

# transport(method, url, headers, body) -> (status, response bytes)
Transport = Callable[[str, str, dict[str, str], bytes | None], tuple[int, bytes]]


def urllib_transport(method: str, url: str, headers: dict[str, str], body: bytes | None) -> tuple[int, bytes]:
    req = urllib.request.Request(url, data=body, method=method, headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=120) as r:  # noqa: S310
            return r.status, r.read()
    except urllib.error.HTTPError as e:
        return e.code, e.read()


class Rest:
    def __init__(self, base_url: str, key: str, transport: Transport = urllib_transport) -> None:
        self.base = base_url.rstrip("/") + "/rest/v1"
        self.headers = {"apikey": key, "Authorization": f"Bearer {key}", "Content-Type": "application/json"}
        self.transport = transport

    def call(self, method: str, path: str, body: Any = None, prefer: str | None = None) -> Any:
        headers = dict(self.headers)
        if prefer:
            headers["Prefer"] = prefer
        data = None if body is None else json.dumps(body, ensure_ascii=False).encode("utf-8")
        status, raw = self.transport(method, f"{self.base}/{path}", headers, data)
        if status >= 300:
            raise RuntimeError(f"{method} {path}: HTTP {status}: {raw[:500].decode('utf-8', 'replace')}")
        return json.loads(raw) if raw else None

    def get_all(self, path: str) -> list[dict[str, Any]]:
        rows: list[dict[str, Any]] = []
        sep = "&" if "?" in path else "?"
        while True:
            page = self.call("GET", f"{path}{sep}limit={PAGE}&offset={len(rows)}")
            rows += page
            if len(page) < PAGE:
                return rows


def exercise_row(e: dict[str, Any]) -> dict[str, Any]:
    row = {"id": e["id"], **{c: e[c] for c in EXERCISE_COLUMNS}}
    row["image_paths"] = e["images"]
    return row


def translation_rows(e: dict[str, Any]) -> list[dict[str, Any]]:
    return [{"exercise_id": e["id"], "locale": loc, **{c: t[c] for c in TRANSLATION_COLUMNS}}
            for loc, t in sorted(e["translations"].items())]


def _num(v: Any) -> Any:
    return float(v) if isinstance(v, (int, float)) and not isinstance(v, bool) else v


def _norm(row: dict[str, Any]) -> dict[str, Any]:
    return {k: _num(v) for k, v in row.items()}


def plan(catalog: dict[str, Any], remote_ex: list[dict[str, Any]], remote_tr: list[dict[str, Any]],
         version_rows: list[dict[str, Any]]) -> dict[str, Any]:
    """Pure diff between the catalog and the server state."""
    remote_by_id = {r["id"]: r for r in remote_ex}
    remote_tr_by_key = {(r["exercise_id"], r["locale"]): r for r in remote_tr}
    ex_changed: dict[str, dict[str, Any]] = {}
    tr_changed: list[dict[str, Any]] = []
    revived = 0
    for e in catalog["exercises"]:
        row = exercise_row(e)
        remote = remote_by_id.get(e["id"])
        differs = remote is None or remote.get("archived_at") is not None or _norm(row) != _norm(
            {k: remote.get(k) for k in row})
        if remote is not None and remote.get("archived_at") is not None:
            revived += 1
        translations_differ = False
        for t in translation_rows(e):
            r = remote_tr_by_key.get((t["exercise_id"], t["locale"]))
            if r is None or any(r.get(k) != v for k, v in t.items()):
                tr_changed.append(t)
                translations_differ = True
        if differs or translations_differ:
            # Parent row is written too, so its updated_at moves and clients re-fetch its translations.
            ex_changed[e["id"]] = {**row, "archived_at": None}
    ids = {e["id"] for e in catalog["exercises"]}
    to_archive = sorted(i for i, r in remote_by_id.items() if i not in ids and r.get("archived_at") is None)
    existing = next((v for v in version_rows if v["version"] == catalog["version"]), None)
    if existing and existing["checksum"] != catalog["checksum"]:
        raise RuntimeError(f"version {catalog['version']} already published with a different checksum; "
                           "run catalog-build to bump the version")
    newer = [v["version"] for v in version_rows if v["version"] > catalog["version"]]
    if newer:
        raise RuntimeError(f"server already has newer catalog version(s) {newer}")
    return {
        "exercises": list(ex_changed.values()),
        "translations": tr_changed,
        "archive": to_archive,
        "revived": revived,
        "publish_version": existing is None,
    }


def _chunks(items: list[Any], n: int):
    for i in range(0, len(items), n):
        yield items[i:i + n]


def seed(catalog: dict[str, Any], rest: Rest, *, dry_run: bool = False,
         now: Callable[[], str] = lambda: dt.datetime.now(dt.timezone.utc).isoformat(),
         progress: Callable[[str], None] = lambda _: None) -> dict[str, int]:
    remote_ex = rest.get_all("exercises?select=id,archived_at," + ",".join(EXERCISE_COLUMNS) + ",image_paths")
    remote_tr = rest.get_all("exercise_translations?select=exercise_id,locale," + ",".join(TRANSLATION_COLUMNS))
    versions = rest.get_all("catalog_versions?select=version,checksum")
    p = plan(catalog, remote_ex, remote_tr, versions)
    summary = {"exercises": len(p["exercises"]), "translations": len(p["translations"]),
               "archived": len(p["archive"]), "revived": p["revived"], "version_published": int(p["publish_version"])}
    if dry_run:
        return summary
    merge = "resolution=merge-duplicates,return=minimal"
    for chunk in _chunks(p["exercises"], BATCH):
        rest.call("POST", "exercises?on_conflict=id", chunk, merge)
        progress(f"exercises +{len(chunk)}")
    for chunk in _chunks(p["translations"], BATCH):
        rest.call("POST", "exercise_translations?on_conflict=exercise_id,locale", chunk, merge)
        progress(f"translations +{len(chunk)}")
    for chunk in _chunks(p["archive"], 50):
        ids = ",".join(f'"{i}"' for i in chunk)
        rest.call("PATCH", f"exercises?id=in.({urllib.parse.quote(ids)})", {"archived_at": now()}, "return=minimal")
        progress(f"archived {len(chunk)}")
    if p["publish_version"]:
        rest.call("POST", "catalog_versions", [{"version": catalog["version"], "checksum": catalog["checksum"]}],
                  "return=minimal")
        progress(f"published catalog version {catalog['version']}")
    return summary


def latest_catalog_path(out_dir: Path = ROOT / "out") -> Path:
    files = sorted(out_dir.glob("catalog.v*.json"), key=lambda p: int(p.stem.split(".v")[1]))
    if not files:
        raise FileNotFoundError("no out/catalog.v*.json; run catalog-build")
    return files[-1]


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(prog="catalog-seed")
    ap.add_argument("--file", type=Path, help="catalog file (default: newest out/catalog.v*.json)")
    ap.add_argument("--dry-run", action="store_true", help="show what would change, write nothing")
    a = ap.parse_args(argv)
    url, key = os.environ.get("SUPABASE_URL", ""), os.environ.get("SUPABASE_SERVICE_ROLE_KEY", "")
    if not url or not key:
        print("SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY must be set", file=sys.stderr)
        return 2
    path = a.file or latest_catalog_path()
    catalog = json.loads(path.read_text(encoding="utf-8"))
    print(f"{path.name} -> {url}{' (dry run)' if a.dry_run else ''}")
    summary = seed(catalog, Rest(url, key), dry_run=a.dry_run, progress=lambda m: print("  " + m, flush=True))
    print(("would change " if a.dry_run else "changed ") + ", ".join(f"{k}={v}" for k, v in summary.items()))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
