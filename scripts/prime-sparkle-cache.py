#!/usr/bin/env python3
"""Prime SwiftPM with the exact pinned Sparkle asset through GitHub's asset API."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile

# Bound to the reviewed upstream Package.swift at this immutable revision.
VERSION = "2.9.6"
REVISION = "ac2def288cbff5cfc7df3ffef6abdf45b72bcb0a"
CHECKSUM = "8d5fb41d960b43f4a68aa14126bf62b098544ec8d191cdcc73eb14e63a8e7606"
SIZE = 11577555
ASSET_API = "repos/sparkle-project/Sparkle/releases/assets/517328210"
ARTIFACT_URL = f"https://github.com/sparkle-project/Sparkle/releases/download/{VERSION}/Sparkle-for-Swift-Package-Manager.zip"
CACHE_NAME = re.sub(r"[^A-Za-z0-9]", "_", ARTIFACT_URL)


def verify_pin(root):
    pins = json.loads((root / "Package.resolved").read_text())["pins"]
    sparkle = [pin for pin in pins if pin.get("identity") == "sparkle"]
    if len(sparkle) != 1 or sparkle[0].get("location") != "https://github.com/sparkle-project/Sparkle":
        raise ValueError("Unexpected Sparkle repository pin")
    if sparkle[0].get("state") != {"revision": REVISION, "version": VERSION}:
        raise ValueError("Sparkle pin changed; review the cache asset identity before use")


def verified(path):
    if path.is_symlink():
        raise ValueError("Refusing a symlinked artifact cache entry")
    if not path.exists():
        return False
    if not path.is_file():
        raise ValueError("Artifact cache entry is not a regular file")
    return path.stat().st_size == SIZE and hashlib.sha256(path.read_bytes()).hexdigest() == CHECKSUM


def download(destination):
    # gh handles authenticated API redirects without putting credentials in arguments.
    with destination.open("wb") as stream:
        try:
            subprocess.run(["gh", "api", ASSET_API, "-H", "Accept: application/octet-stream"],
                           stdout=stream, stderr=subprocess.PIPE, check=True, timeout=90)
        except (subprocess.SubprocessError, OSError) as error:
            raise ValueError("Official Sparkle asset API download failed") from error


def prime(root, cache, fetch=download):
    verify_pin(root)
    destination = cache / CACHE_NAME
    if verified(destination):
        print(f"sparkle_cache outcome=verified_existing version={VERSION} sha256={CHECKSUM}")
        return destination
    cache.mkdir(parents=True, exist_ok=True)
    descriptor, name = tempfile.mkstemp(prefix=".sparkle-verified-", dir=cache)
    os.close(descriptor)
    staged = Path(name)
    try:
        fetch(staged)
        if not verified(staged):
            raise ValueError("Sparkle asset size/checksum mismatch; cache was not replaced")
        os.replace(staged, destination)
    finally:
        staged.unlink(missing_ok=True)
    print(f"sparkle_cache outcome=verified_download version={VERSION} sha256={CHECKSUM}")
    return destination


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--cache-dir", type=Path,
                        default=Path.home() / "Library/Caches/org.swift.swiftpm/artifacts")
    args = parser.parse_args()
    try:
        prime(args.root, args.cache_dir)
    except (ValueError, KeyError, OSError) as error:
        parser.exit(1, f"sparkle_cache outcome=failed reason={error}\n")


if __name__ == "__main__":
    main()
