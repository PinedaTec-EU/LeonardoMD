#!/usr/bin/env python3
"""Verify current-candidate inputs and hash-bound images for PR #377."""
import hashlib
import json
from pathlib import Path
import subprocess
import sys

root = Path(__file__).resolve().parents[3]
head = sys.argv[1] if len(sys.argv) > 1 else "HEAD"
source = "347dd5ae46e93137741afb050500b003b607cff2"
subprocess.run([
    "git", "diff", "--exit-code", source, head, "--", ".",
    ":(exclude)doc/validation/math-outline/**",
    ":(exclude)deploy/version/entries/377.yaml",
    ":(exclude)deploy/release-notes.md",
], cwd=root, check=True)
expected_notes = subprocess.check_output(["git", "show", "4f1ed5dfa9cb1ea72dbe5db9bf3480a42db973e2:deploy/release-notes.md"], cwd=root)
actual_notes = subprocess.check_output(["git", "show", f"{head}:deploy/release-notes.md"], cwd=root)
assert actual_notes == expected_notes, "Publication-only notes differ from accepted main checkpoint"
print(f"Current component/native captures: product, build, test, guide and workflow inputs match {head}")
for sidecar in Path(__file__).parent.rglob("*.metadata.json"):
    metadata = json.loads(sidecar.read_text())
    suffix = ".png" if metadata["image"]["format"] == "png" else ".jpg"
    original = sidecar.with_name(sidecar.name.removesuffix(".metadata.json") + suffix)
    assert hashlib.sha256(original.read_bytes()).hexdigest() == metadata["image"]["sha256"], original
    print(f"Image hash verified: {original.relative_to(root)}")
