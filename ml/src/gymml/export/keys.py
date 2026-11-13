"""P060: Ed25519 signing for model bundles.

    python -m gymml.export.keys generate [--out PATH]   # new key pair; prints the public key
    python -m gymml.export.keys verify BUNDLE_DIR [--public-key B64]

The private key never enters the repository (see docs/KURULUM.md). The public key (raw 32 bytes,
base64) is pinned in `ios/Packages/StrengthKit/Sources/StrengthKit/Model/ModelBundle.swift`.
"""
# ruff: noqa: E501

from __future__ import annotations

import argparse
import base64
import hashlib
import json
import os
import sys
from pathlib import Path

from cryptography.exceptions import InvalidSignature
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey, Ed25519PublicKey

DEFAULT_KEY_PATH = Path.home() / ".config" / "atrox" / "model-signing-ed25519.pem"
KEY_ENV = "ATROX_MODEL_SIGNING_KEY"  # path override
# Must equal `ModelBundle.trustedPublicKeyBase64` in StrengthKit.
PUBLIC_KEY_B64 = "BkYuzm+Izi7IbGVvSGTa/u/qsP5ki542VwSlnr4llbM="
MANIFEST = "manifest.json"
SIGNATURE = "manifest.sig"


def key_path() -> Path:
    return Path(os.environ.get(KEY_ENV, DEFAULT_KEY_PATH)).expanduser()


def public_b64(key: Ed25519PublicKey) -> str:
    raw = key.public_bytes(serialization.Encoding.Raw, serialization.PublicFormat.Raw)
    return base64.b64encode(raw).decode()


def generate(out: Path) -> str:
    if out.exists():
        raise FileExistsError(f"{out} exists; refusing to overwrite a signing key")
    key = Ed25519PrivateKey.generate()
    out.parent.mkdir(parents=True, exist_ok=True)
    pem = key.private_bytes(
        serialization.Encoding.PEM, serialization.PrivateFormat.PKCS8, serialization.NoEncryption()
    )
    fd = os.open(out, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(fd, "wb") as f:
        f.write(pem)
    return public_b64(key.public_key())


def load_private(path: Path | None = None) -> Ed25519PrivateKey:
    data = (path or key_path()).read_bytes()
    key = serialization.load_pem_private_key(data, password=None)
    if not isinstance(key, Ed25519PrivateKey):
        raise TypeError("signing key is not Ed25519")
    return key


def sign_bundle(bundle: Path, key: Ed25519PrivateKey) -> None:
    (bundle / SIGNATURE).write_bytes(key.sign((bundle / MANIFEST).read_bytes()))


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def verify_bundle(bundle: Path, public_key_b64: str = PUBLIC_KEY_B64) -> dict:
    """Checks the signature over manifest.json and every listed file's SHA-256. Raises on failure."""
    pub = Ed25519PublicKey.from_public_bytes(base64.b64decode(public_key_b64))
    manifest_bytes = (bundle / MANIFEST).read_bytes()
    try:
        pub.verify((bundle / SIGNATURE).read_bytes(), manifest_bytes)
    except InvalidSignature as exc:
        raise ValueError("manifest signature is invalid") from exc
    manifest = json.loads(manifest_bytes)
    for name, digest in manifest["files"].items():
        if sha256(bundle / name) != digest:
            raise ValueError(f"SHA-256 mismatch for {name}")
    return manifest


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(prog="gymml.export.keys")
    sub = ap.add_subparsers(dest="cmd", required=True)
    g = sub.add_parser("generate")
    g.add_argument("--out", type=Path, default=None)
    v = sub.add_parser("verify")
    v.add_argument("bundle", type=Path)
    v.add_argument("--public-key", default=PUBLIC_KEY_B64)
    args = ap.parse_args(argv)
    if args.cmd == "generate":
        out = args.out or key_path()
        print(f"private key: {out}\npublic key (base64): {generate(out)}")
        return 0
    m = verify_bundle(args.bundle, args.public_key)
    print(f"OK: {args.bundle} v{m['version']} ({len(m['files'])} files)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
