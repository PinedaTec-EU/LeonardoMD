#!/usr/bin/env python3
"""Record one successful Swift or Xcode compilation command in its source PR delta."""
import argparse
import fcntl
import json
import os
import subprocess
import tempfile
from pathlib import Path

SEGMENTS = {"release", "feature", "build"}


def read_entry(path: Path, pr: int) -> dict | None:
    if not path.exists():
        return None
    entry = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(entry, dict) or set(entry) - SEGMENTS - {"delta", "pr", "summary"}:
        raise ValueError("Entry contains fields not supported by the release ledger")
    declared_pr = entry.get("pr")
    if declared_pr is not None and (isinstance(declared_pr, bool) or not isinstance(declared_pr, int) or declared_pr != pr):
        raise ValueError("Entry PR number must match the recorder PR")
    if "delta" in entry:
        if set(entry) & SEGMENTS:
            raise ValueError("Entry must use either nested delta or top-level segment fields, not both")
        delta = entry["delta"]
    else:
        delta = {key: value for key, value in entry.items() if key in SEGMENTS}
    if not isinstance(delta, dict) or not delta or set(delta) - SEGMENTS:
        raise ValueError("Entry must contain one or more release, feature or build deltas")
    if any(isinstance(value, bool) or not isinstance(value, int) or value <= 0 for value in delta.values()):
        raise ValueError("Entry deltas must be positive integers")
    if "summary" in entry:
        import unicodedata
        text = entry["summary"]
        if (not isinstance(text, str) or not text or text != text.strip() or len(text) > 280
                or any(unicodedata.category(char) in {"Cc", "Cs", "Zl", "Zp"} for char in text)):
            raise ValueError("Summary must be 1–280 single-line plain-text characters")
    return entry


def compile_and_record(root: Path, pr: int, command: list[str]) -> int:
    if pr <= 0:
        raise ValueError("PR number must be positive")
    executable = Path(command[0]).name if command else ""
    swift = (len(command) >= 2 and executable == "swift"
             and command[1] in {"build", "test", "run"}
             and not {"--show-bin-path", "--skip-build", "--help", "-h", "--version"} & set(command[2:]))
    xcode = (executable == "xcodebuild"
             and bool({"build", "test", "build-for-testing", "archive"} & set(command[1:]))
             and not {"-list", "-showBuildSettings", "-showdestinations", "-showsdks", "-version", "-help",
                      "-resolvePackageDependencies", "test-without-building"} & set(command[1:]))
    if not swift and not xcode:
        raise ValueError("Use a compiling swift build/test/run or xcodebuild build/test/archive command")
    entry = root / "deploy/version/entries" / f"{pr}.yaml"
    read_entry(entry, pr)  # Reject malformed existing data before compiling.
    result = subprocess.run(command, cwd=root)
    if result.returncode:
        return result.returncode
    entry.parent.mkdir(parents=True, exist_ok=True)
    lock_path = root / ".build/release-ledger-compilation.lock"
    lock_path.parent.mkdir(parents=True, exist_ok=True)
    with lock_path.open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        recorded_entry = read_entry(entry, pr) or {"delta": {}}
        delta = recorded_entry["delta"] if "delta" in recorded_entry else recorded_entry
        delta["build"] = delta.get("build", 0) + 1
        with tempfile.NamedTemporaryFile(mode="w", dir=entry.parent, delete=False) as output:
            temporary = Path(output.name)
            json.dump(recorded_entry, output, indent=2)
            output.write("\n")
        try:
            os.replace(temporary, entry)
        finally:
            temporary.unlink(missing_ok=True)
    print(f"Recorded successful compilation for PR #{pr}: build delta {delta['build']}")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--pr-number", type=int, required=True)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parent.parent)
    parser.add_argument("command", nargs=argparse.REMAINDER)
    args = parser.parse_args()
    command = args.command[1:] if args.command[:1] == ["--"] else args.command
    try:
        return compile_and_record(args.root.resolve(), args.pr_number, command)
    except (ValueError, OSError) as error:
        parser.exit(1, f"compile-and-record: {error}\n")


if __name__ == "__main__":
    raise SystemExit(main())
