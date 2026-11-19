#!/usr/bin/env python3
"""Bound the full Swift test suite without cancelling the diagnostics steps."""

import argparse
from dataclasses import dataclass
import os
from pathlib import Path
import signal
import subprocess
import time


@dataclass(frozen=True)
class ProcessInfo:
    pid: int
    parent: int
    group: int
    elapsed: str
    state: str
    command: str


def suite_processes(leader):
    result = subprocess.run(
        ["ps", "-axo", "pid=,ppid=,pgid=,etime=,stat=,comm="],
        capture_output=True, text=True, check=True, timeout=5,
    )
    processes = []
    for line in result.stdout.splitlines():
        columns = line.split(maxsplit=5)
        if len(columns) == 6:
            pid, parent, group = map(int, columns[:3])
            processes.append(ProcessInfo(pid, parent, group, *columns[3:5], Path(columns[5]).name))

    selected = {p.pid for p in processes if p.group == leader} | {leader}
    while True:
        expanded = selected | {p.pid for p in processes if p.parent in selected}
        if expanded == selected:
            return [p for p in processes if p.pid in selected]
        selected = expanded


def snapshot(processes):
    rows = ["PID PPID PGID ELAPSED STAT COMMAND"]
    rows.extend(f"{p.pid} {p.parent} {p.group} {p.elapsed} {p.state} {p.command}" for p in processes)
    return "\n".join(rows)


def sample_test_processes(processes, leader, diagnostics):
    sampler = Path("/usr/bin/sample")
    if not sampler.exists():
        return
    test_runners = [p.pid for p in processes if p.pid != leader and "xctest" in p.command.lower()]
    for pid in [leader, *test_runners[:2]]:
        destination = diagnostics / f"timeout-stack-{pid}.txt"
        try:
            subprocess.run(
                [str(sampler), str(pid), "1", "10", "-file", str(destination)],
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=True, timeout=8,
            )
            report = destination.read_text(encoding="utf-8", errors="replace")
            call_graph = report.partition("Call graph:")[2].partition("Binary Images:")[0]
            destination.write_text(f"PID {pid}\nCall graph:{call_graph}", encoding="utf-8")
        except (OSError, subprocess.SubprocessError) as error:
            destination.unlink(missing_ok=True)
            print(f"::warning::Could not sample Swift test PID {pid}: {error}", flush=True)


def signal_process(target, signum):
    try:
        os.kill(target, signum)
    except ProcessLookupError:
        pass
    except PermissionError as error:
        print(f"::warning::Could not signal Swift test target {target}: {error}", flush=True)


def terminate_suite(process, descendants):
    # Foundation can spawn XCTest into a group separate from SwiftPM's.
    for signum in (signal.SIGTERM, signal.SIGKILL):
        for pid in descendants:
            signal_process(pid, signum)
        signal_process(-process.pid, signum)
        if signum == signal.SIGTERM:
            time.sleep(3)
            process.poll()
    process.wait(timeout=5)


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
        descendants = []
        try:
            processes = suite_processes(process.pid)
            descendants = [p.pid for p in processes if p.group != process.pid]
            args.diagnostics.mkdir(parents=True, exist_ok=True)
            (args.diagnostics / "timeout-processes.txt").write_text(
                f"{message}\n{snapshot(processes)}\n", encoding="utf-8",
            )
            if any(p.pid == process.pid and p.command in {"swift", "swift-test"} for p in processes):
                sample_test_processes(processes, process.pid, args.diagnostics)
        except (OSError, subprocess.SubprocessError) as error:
            print(f"::warning::Could not collect the Swift test diagnostics: {error}", flush=True)
        finally:
            terminate_suite(process, descendants)
        return 124


if __name__ == "__main__":
    raise SystemExit(main())
