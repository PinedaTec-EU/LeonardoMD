#!/usr/bin/env python3
"""Compare the bundled public key with an existing Sparkle signing account."""
import plistlib
import subprocess
import sys
from pathlib import Path


def verify(plist, tool, account):
    with plist.open("rb") as source:
        embedded = plistlib.load(source).get("SUPublicEDKey")
    # -p only reads an existing public key; it never generates or exports a private key.
    result = subprocess.run([str(tool), "--account", account, "-p"],
                            capture_output=True, text=True, check=True)
    if not embedded or result.stdout.strip() != embedded:
        raise ValueError("Bundle updater public key does not match signing account")


if __name__ == "__main__":
    verify(Path(sys.argv[1]), Path(sys.argv[2]), sys.argv[3])
