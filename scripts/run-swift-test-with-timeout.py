#!/usr/bin/env python3
"""Bound the full Swift test suite without cancelling the diagnostics steps."""

import argparse
from dataclasses import dataclass
import os
from pathlib import Path
from selectors import DefaultSelector, EVENT_READ
import signal
import subprocess
import sys
import tempfile
import time


@dataclass(frozen=True)
class ProcessInfo:
    pid: int
    parent: int
    group: int
    elapsed: str
    state: str
    command: str


def belongs_to_session(pid, session):
    try:
        return os.getsid(pid) == session
    except OSError:
        return False


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

    selected = {p.pid for p in processes if belongs_to_session(p.pid, leader)} | {leader}
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
    candidates = [
        p for p in processes
        if "xctest" in p.command.lower() or (p.pid == leader and p.command in {"swift", "swift-test"})
    ]
    for process in candidates[:3]:
        pid = process.pid
        try:
            with tempfile.TemporaryDirectory(prefix="swift-test-sample-") as scratch:
                raw = Path(scratch) / "sample.txt"
                subprocess.run(
                    [str(sampler), str(pid), "1", "10", "-file", str(raw)],
                    stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=True, timeout=8,
                )
                report = raw.read_text(encoding="utf-8", errors="replace")
            call_graph = report.partition("Call graph:")[2].partition("Binary Images:")[0]
            if not call_graph.strip():
                print(f"::warning::No call graph for Swift test PID {pid}.", flush=True)
                continue
            with tempfile.NamedTemporaryFile(
                mode="w", encoding="utf-8", dir=diagnostics, suffix=".tmp", delete=False,
            ) as output:
                pending = Path(output.name)
                output.write(f"PID {pid}\nCall graph:{call_graph}")
            pending.replace(diagnostics / f"timeout-stack-{pid}.txt")
        except (OSError, subprocess.SubprocessError) as error:
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


def wait_with_output(process, seconds):
    deadline = time.monotonic() + seconds
    with DefaultSelector() as selector:
        selector.register(process.stdout, EVENT_READ)
        while True:
            remaining = deadline - time.monotonic()
            if remaining <= 0 or not selector.select(remaining):
                raise subprocess.TimeoutExpired(process.args, seconds)
            chunk = os.read(process.stdout.fileno(), 65536)
            if not chunk:
                break
            sys.stdout.buffer.write(chunk)
            sys.stdout.buffer.flush()
    return process.wait(timeout=max(0, deadline - time.monotonic()))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--seconds", type=int, required=True)
    parser.add_argument("--diagnostics", type=Path, required=True)
    parser.add_argument("--skip", action="append", default=[], help="Exclude a SwiftPM test filter")
    args = parser.parse_args()
    if args.seconds <= 0:
        parser.error("--seconds must be positive")
    command = ["swift", "test", "--verbose"]
    for pattern in args.skip:
        command.extend(("--skip", pattern))
    process = subprocess.Popen(
        command, start_new_session=True,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
    )
    try:
        return wait_with_output(process, args.seconds)
    except subprocess.TimeoutExpired:
        message = f"Swift test exceeded the {args.seconds}-second deadline."
        print(f"\n::error::{message}", flush=True)
        descendants = []
        try:
            processes = suite_processes(process.pid)
            descendants = [p.pid for p in processes if p.group != process.pid]
            args.diagnostics.mkdir(parents=True, exist_ok=True)
            (args.diagnostics / "timeout-processes.txt").write_text(
                f"{message}\n{snapshot(processes)}\n", encoding="utf-8",
            )
            sample_test_processes(processes, process.pid, args.diagnostics)
        except (OSError, subprocess.SubprocessError) as error:
            print(f"::warning::Could not collect the Swift test diagnostics: {error}", flush=True)
        finally:
            terminate_suite(process, descendants)
        return 124
    finally:
        process.stdout.close()


if __name__ == "__main__":
    raise SystemExit(main())
