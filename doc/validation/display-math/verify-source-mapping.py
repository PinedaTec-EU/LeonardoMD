#!/usr/bin/env python3
"""Verify capture sources match a review head outside evidence, build counts and non-packaged revision inventory."""
import subprocess
import sys
from pathlib import Path

root = Path(__file__).resolve().parents[3]
head = sys.argv[1] if len(sys.argv) > 1 else "HEAD"
captures = {
    "component": "8061b04d640ea87554205e96ba60ea6ae4f165b0",
    "packaged": "8061b04d640ea87554205e96ba60ea6ae4f165b0",
}
for label, revision in captures.items():
    subprocess.run([
        "git", "diff", "--exit-code", revision, head, "--", ".",
        ":(exclude)doc/validation/display-math/**",
        ":(exclude)deploy/version/entries/363.yaml",
        # This inventory is not consumed by the guide packager or app build.
        ":(exclude)doc/guide/feature-coverage.md",
    ], cwd=root, check=True)
    print(f"{label}: all tracked product, build, test, guide and workflow inputs match {head}")
