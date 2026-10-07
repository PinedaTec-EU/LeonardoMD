#!/usr/bin/env python3
"""Record one successful Swift compilation command in its source PR delta."""
import argparse
import fcntl
import json
import os
import subprocess
import tempfile
from pathlib import Path

SEGMENTS = {"release", "feature", "build"}


def read_delta(path: Path) -> dict[str, int]:
    if not path.exists():
        return {}
    delta = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(delta, dict) or set(delta) - SEGMENTS:
        raise ValueError("Entry must contain only release, feature and build deltas")
    if any(isinstance(value, bool) or not isinstance(value, int) or value <= 0 for value in delta.values()):
        raise ValueError("Entry deltas must be positive integers")
    return delta


def compile_and_record(root: Path, pr: int, command: list[str]) -> int:
    if pr <= 0:
        raise ValueError("PR number must be positive")
    if (len(command) < 2 or Path(command[0]).name != "swift"
            or command[1] not in {"build", "test", "run"}
            or {"--show-bin-path", "--skip-build", "--help", "-h", "--version"} & set(command[2:])):
        raise ValueError("Use a compiling swift build, test or run command")
    entry = root / "deploy/version/entries" / f"{pr}.yaml"
    read_delta(entry)  # Reject malformed existing data before compiling.
    result = subprocess.run(command, cwd=root)
    if result.returncode:
        return result.returncode
    entry.parent.mkdir(parents=True, exist_ok=True)
    with (entry.parent / ".compilation.lock").open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        delta = read_delta(entry)
        delta["build"] = delta.get("build", 0) + 1
        with tempfile.NamedTemporaryFile(mode="w", dir=entry.parent, delete=False) as output:
            temporary = Path(output.name)
            json.dump(delta, output, indent=2)
            output.write("\n")
        try:
            os.replace(temporary, entry)
        finally:
            temporary.unlink(missing_ok=True)
    print(f"Recorded successful Swift compilation for PR #{pr}: build delta {delta['build']}")
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
