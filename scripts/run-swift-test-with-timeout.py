#!/usr/bin/env python3
"""Bound the full Swift test suite without cancelling the diagnostics steps."""

import argparse
from pathlib import Path
import os
import signal
import subprocess
import time


def process_snapshot(group):
    result = subprocess.run(
        ["ps", "-axo", "pid=,ppid=,pgid=,etime=,stat=,comm="],
        capture_output=True, text=True, check=True, timeout=5,
    )
    rows = ["PID PPID PGID ELAPSED STAT COMMAND"]
    for line in result.stdout.splitlines():
        columns = line.split(maxsplit=5)
        if len(columns) == 6 and columns[2] == str(group):
            rows.append(" ".join([*columns[:5], Path(columns[5]).name]))
    return "\n".join(rows)


def signal_group(group, signum):
    try:
        os.killpg(group, signum)
    except ProcessLookupError:
        pass
    except PermissionError as error:
        print(f"::warning::Could not signal Swift test group {group}: {error}", flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--seconds", type=int, required=True)
    parser.add_argument("--diagnostics", type=Path, required=True)
    args = parser.parse_args()
    if args.seconds <= 0:
        parser.error("--seconds must be positive")
    process = subprocess.Popen(["swift", "test", "--verbose"], start_new_session=True)
    try:
        return process.wait(timeout=args.seconds)
    except subprocess.TimeoutExpired:
        message = f"Swift test exceeded the {args.seconds}-second deadline."
        print(f"::error::{message}", flush=True)
        try:
            args.diagnostics.mkdir(parents=True, exist_ok=True)
            snapshot = args.diagnostics / "timeout-processes.txt"
            snapshot.write_text(f"{message}\n{process_snapshot(process.pid)}\n", encoding="utf-8")
        except (OSError, subprocess.SubprocessError) as error:
            print(f"::warning::Could not collect the Swift test process snapshot: {error}", flush=True)
        finally:
            signal_group(process.pid, signal.SIGTERM)
            # The group may outlive its leader. Give all children time to exit.
            time.sleep(3)
            process.poll()  # Reap an exited leader before the final group signal.
            signal_group(process.pid, signal.SIGKILL)
            process.wait(timeout=5)
        return 124


if __name__ == "__main__":
    raise SystemExit(main())
