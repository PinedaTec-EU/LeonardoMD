#!/usr/bin/env python3
"""Verify current-candidate inputs and hash-bound images for PR #377."""
import hashlib
import json
from pathlib import Path
import subprocess
import sys

root = Path(__file__).resolve().parents[3]
head = sys.argv[1] if len(sys.argv) > 1 else "HEAD"
source = "4ba13fe895a80cfe9dc3a791deab321b56003d67"
subprocess.run([
    "git", "diff", "--exit-code", source, head, "--", ".",
    ":(exclude)doc/validation/math-outline/**",
    ":(exclude)deploy/version/entries/377.yaml",
], cwd=root, check=True)
print(f"Current component/native captures: product, build, test, guide and workflow inputs match {head}")
for sidecar in Path(__file__).parent.rglob("*.metadata.json"):
    metadata = json.loads(sidecar.read_text())
    suffix = ".png" if metadata["image"]["format"] == "png" else ".jpg"
    original = sidecar.with_name(sidecar.name.removesuffix(".metadata.json") + suffix)
    assert hashlib.sha256(original.read_bytes()).hexdigest() == metadata["image"]["sha256"], original
    print(f"Image hash verified: {original.relative_to(root)}")
