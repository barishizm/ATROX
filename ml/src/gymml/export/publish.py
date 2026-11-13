"""P063: publish a signed model bundle to Supabase (Storage + `model_versions`).

    SUPABASE_URL=... SUPABASE_SERVICE_ROLE_KEY=... \
        uv run python -m gymml.export.publish dist/model-bundle-v1.1.0 [--rollout 10] [--activate]

Files go to the `model-bundles` bucket as individual objects under `v<version>/` (no zip: the app is
Foundation-only and iOS has no unzip API; every file is covered by the signed manifest anyway). The
row is inserted with is_active = false unless `--activate`; activate / roll back later by flipping
`is_active` (and `rollout_percent`) in the table. The service role key comes from the environment
(password manager, see docs/KURULUM.md) and never from the repository.
"""

# ruff: noqa: E501

from __future__ import annotations

import argparse
import json
import os
import sys
import urllib.request
from collections.abc import Callable
from pathlib import Path

from gymml.export import keys

BUCKET = "model-bundles"
Transport = Callable[[str, str, dict[str, str], bytes], int]


def _urllib_transport(method: str, url: str, headers: dict[str, str], body: bytes) -> int:
    req = urllib.request.Request(url, data=body, headers=headers, method=method)
    with urllib.request.urlopen(req, timeout=60) as resp:  # noqa: S310 - URL is the configured Supabase project
        return resp.status


def row_for(manifest: dict, manifest_sha256: str, rollout: int, activate: bool) -> dict:
    return {
        "version": manifest["version"],
        "schema_version": manifest["schemaVersion"],
        "min_app_version": manifest["minAppVersion"],
        "storage_path": f"v{manifest['version']}",
        "manifest_sha256": manifest_sha256,
        "metrics": manifest.get("metrics", {}),
        "is_active": activate,
        "rollout_percent": rollout,
    }


def publish(
    bundle: Path, base_url: str, service_key: str, rollout: int = 100, activate: bool = False,
    transport: Transport = _urllib_transport, public_key_b64: str = keys.PUBLIC_KEY_B64,
) -> dict:
    if not 0 <= rollout <= 100:
        raise ValueError("rollout must be 0-100")
    manifest = keys.verify_bundle(bundle, public_key_b64)  # never publish an unverifiable bundle
    row = row_for(manifest, keys.sha256(bundle / keys.MANIFEST), rollout, activate)
    auth = {"Authorization": f"Bearer {service_key}", "apikey": service_key}
    names = [keys.MANIFEST, keys.SIGNATURE, *sorted(manifest["files"])]
    for name in names:
        ctype = "application/octet-stream" if name == keys.SIGNATURE else "application/json"
        url = f"{base_url.rstrip('/')}/storage/v1/object/{BUCKET}/{row['storage_path']}/{name}"
        status = transport("POST", url, {**auth, "Content-Type": ctype, "x-upsert": "false"}, (bundle / name).read_bytes())
        if status >= 300:
            raise RuntimeError(f"upload of {name} failed: HTTP {status}")
    status = transport(
        "POST", f"{base_url.rstrip('/')}/rest/v1/model_versions",
        {**auth, "Content-Type": "application/json", "Prefer": "return=minimal"}, json.dumps(row).encode(),
    )
    if status >= 300:
        raise RuntimeError(f"insert into model_versions failed: HTTP {status}")
    return row


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(prog="gymml.export.publish")
    ap.add_argument("bundle", type=Path)
    ap.add_argument("--rollout", type=int, default=100)
    ap.add_argument("--activate", action="store_true")
    args = ap.parse_args(argv)
    url, key = os.environ.get("SUPABASE_URL"), os.environ.get("SUPABASE_SERVICE_ROLE_KEY")
    if not url or not key:
        print("SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY must be set", file=sys.stderr)
        return 2
    row = publish(args.bundle, url, key, args.rollout, args.activate)
    print(f"published {row['version']} -> {BUCKET}/{row['storage_path']} (active={row['is_active']}, rollout={row['rollout_percent']}%)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
