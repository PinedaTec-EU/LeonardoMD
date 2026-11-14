#!/usr/bin/env python3
"""Write a sanitized summary of recent macOS Swift test crash reports."""

from __future__ import annotations

import argparse
import json
import re
from pathlib import Path


SAFE_TEXT = re.compile(r"[^A-Za-z0-9 _.,:<>@+=-]")
REPORT_NAME = re.compile(r"(xctest|swift|leonardo)", re.IGNORECASE)


def safe(value: object, limit: int = 180) -> str:
    return SAFE_TEXT.sub("_", str(value)).strip()[:limit]


def _json_objects(text: str) -> list[dict[str, object]]:
    objects: list[dict[str, object]] = []
    for line in text.splitlines():
        try:
            value = json.loads(line)
        except json.JSONDecodeError:
            continue
        if isinstance(value, dict):
            objects.append(value)
    if not objects:
        try:
            value = json.loads(text)
        except json.JSONDecodeError:
            return []
        if isinstance(value, dict):
            objects.append(value)
    return objects


def _ips_summary(text: str) -> list[str]:
    objects = _json_objects(text)
    report = next(
        (value for value in reversed(objects) if "procName" in value or "exception" in value),
        objects[-1] if objects else {},
    )
    lines: list[str] = []
    process = report.get("procName") or report.get("app_name")
    if process:
        lines.append(f"process={safe(process)}")

    exception = report.get("exception")
    if isinstance(exception, dict):
        parts = [exception.get("type"), exception.get("signal")]
        value = " ".join(safe(part) for part in parts if part is not None)
        if value:
            lines.append(f"exception={value}")

    termination = report.get("termination")
    if isinstance(termination, dict):
        parts = [termination.get(key) for key in ("namespace", "code", "indicator")]
        value = " ".join(safe(part) for part in parts if part is not None)
        if value:
            lines.append(f"termination={value}")

    threads = report.get("threads")
    if isinstance(threads, list):
        faulting = report.get("faultingThread")
        thread = next(
            (item for item in threads if isinstance(item, dict) and item.get("id") == faulting),
            next((item for item in threads if isinstance(item, dict) and item.get("triggered")), None),
        )
        if isinstance(thread, dict):
            lines.append(f"faulting_thread={safe(thread.get('id', faulting))}")
            frames = thread.get("frames")
            if isinstance(frames, list):
                for index, frame in enumerate(frames[:5]):
                    if not isinstance(frame, dict):
                        continue
                    image = frame.get("imageName") or frame.get("image")
                    symbol = frame.get("symbol") or frame.get("symbolName")
                    parts = [safe(part) for part in (image, symbol) if part is not None]
                    if parts:
                        lines.append(f"frame[{index}]={' | '.join(parts)}")
    return lines or ["crash_fields=unavailable"]


def _crash_summary(text: str) -> list[str]:
    lines: list[str] = []
    patterns = (
        ("process", r"^Process:\s*(.+)$"),
        ("exception", r"^Exception Type:\s*(.+)$"),
        ("termination", r"^Termination Reason:\s*(.+)$"),
    )
    for label, pattern in patterns:
        match = re.search(pattern, text, re.MULTILINE)
        if match:
            value = safe(match.group(1))
            if value:
                lines.append(f"{label}={value}")

    thread_match = re.search(r"^Thread (\d+) Crashed:", text, re.MULTILINE)
    if thread_match:
        thread_id = thread_match.group(1)
        lines.append(f"faulting_thread={thread_id}")
        after_header = text[thread_match.end():]
        next_thread = re.search(r"^Thread \d+", after_header, re.MULTILINE)
        stack = after_header[:next_thread.start()] if next_thread else after_header
        frame_index = 0
        for frame in re.finditer(
            r"^\s*\d+\s+(\S+)\s+0x[0-9a-fA-F]+\s+(.+?)\s+\+\s+\d+\s*$",
            stack,
            re.MULTILINE,
        ):
            image, symbol = safe(frame.group(1)), safe(frame.group(2))
            lines.append(f"frame[{frame_index}]={image} | {symbol}")
            frame_index += 1
            if frame_index == 5:
                break
    return lines or ["crash_fields=unavailable"]


def summarize_report(path: Path) -> str:
    try:
        text = path.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return f"report={safe(path.name)} unreadable=true"
    fields = _ips_summary(text) if path.suffix == ".ips" else _crash_summary(text)
    return "\n".join([f"report={safe(path.name)}", *fields])


def collect_summaries(directory: Path, started_after: float) -> list[str]:
    if not directory.is_dir():
        return []
    reports = [
        path
        for path in directory.iterdir()
        if path.is_file()
        and path.suffix in {".ips", ".crash"}
        and REPORT_NAME.search(path.name)
        and path.stat().st_mtime >= started_after
    ]
    reports.sort(key=lambda path: path.stat().st_mtime, reverse=True)
    return [summarize_report(path) for path in reports[:10]]


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--report-directory", type=Path, required=True)
    parser.add_argument("--started-after", type=float, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()

    summaries = collect_summaries(args.report_directory, args.started_after)
    text = "Sanitized Swift test crash diagnostics; raw reports and full paths are omitted.\n\n"
    text += "\n\n".join(summaries) if summaries else "No matching crash report found after test start."
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(text + "\n", encoding="utf-8")
    print(text)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
