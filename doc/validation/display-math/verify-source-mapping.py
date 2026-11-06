#!/usr/bin/env python3
"""Verify capture sources match a review head outside evidence and build counts."""
import subprocess
import sys
from pathlib import Path

root = Path(__file__).resolve().parents[3]
head = sys.argv[1] if len(sys.argv) > 1 else "HEAD"
captures = {
    "component": "ec218f2b1bf55624cd527b2625e802d14b0cde63",
    "packaged": "cc71996d39bf4c73c592be9d522ac9bf615fd3a0",
}
for label, revision in captures.items():
    subprocess.run([
        "git", "diff", "--exit-code", revision, head, "--", ".",
        ":(exclude)doc/validation/display-math/**",
        ":(exclude)deploy/version/entries/363.yaml",
    ], cwd=root, check=True)
    print(f"{label}: all tracked product, build, test, guide and workflow inputs match {head}")
