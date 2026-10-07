#!/usr/bin/env python3
"""Apply public release metadata only; never reads or stores a private signing key."""
import base64
import os
import plistlib
import re
import sys
from pathlib import Path


def configure(path, environment):
    version = environment.get("LEONARDO_VERSION", "0.1.0")
    build = environment.get("LEONARDO_BUILD", "1")
    key = environment.get("SPARKLE_PUBLIC_KEY", "")
    if not re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", version):
        raise ValueError("LEONARDO_VERSION must be a stable major.minor.patch version")
    if not re.fullmatch(r"[1-9][0-9]*", build):
        raise ValueError("LEONARDO_BUILD must be a positive, monotonically increasing integer")
    if key and len(base64.b64decode(key, validate=True)) != 32:
        raise ValueError("SPARKLE_PUBLIC_KEY must encode a 32-byte Ed25519 public key")
    if environment.get("LEONARDO_DISTRIBUTION") == "1" and not key:
        raise ValueError("Distribution requires SPARKLE_PUBLIC_KEY")
    with path.open("rb") as source:
        metadata = plistlib.load(source)
    metadata["CFBundleVersion"] = build
    metadata["CFBundleShortVersionString"] = version
    metadata.pop("SUPublicEDKey", None)
    if key:
        metadata["SUPublicEDKey"] = key
    with path.open("wb") as target:
        plistlib.dump(metadata, target)


if __name__ == "__main__":
    configure(Path(sys.argv[1]), os.environ)
