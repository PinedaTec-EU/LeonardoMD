"""Source and canonical-checkpoint guards for Little Leonardo distribution."""

from __future__ import annotations

import hashlib
import json
from pathlib import Path
import re
import subprocess


class SourceGuardError(ValueError):
    """Raised when an archive source is not a frozen accepted checkpoint."""


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def git_text(root: Path, *arguments: str) -> str:
    try:
        result = subprocess.run(["git", *arguments], cwd=root, check=True,
                                capture_output=True, text=True)
    except (OSError, subprocess.CalledProcessError) as error:
        raise SourceGuardError(f"Git query failed: {' '.join(arguments)}") from error
    return result.stdout.strip()


def source_inputs_sha256(root: Path) -> str:
    try:
        result = subprocess.run(["git", "ls-files", "-z"], cwd=root, check=True,
                                capture_output=True)
    except (OSError, subprocess.CalledProcessError) as error:
        raise SourceGuardError("Cannot enumerate source inputs") from error
    digest = hashlib.sha256()
    paths = sorted(item for item in result.stdout.split(b"\0") if item)
    for raw_path in paths:
        relative = raw_path.decode("utf-8")
        if relative.startswith("deploy/version/entries/"):
            continue
        path = root / relative
        if not path.is_file():
            raise SourceGuardError(f"Tracked source input is unavailable: {relative}")
        digest.update(raw_path + b"\0")
        digest.update(bytes.fromhex(sha256_file(path)))
    return digest.hexdigest()


def _worktree_paths(root: Path) -> list[bytes]:
    try:
        result = subprocess.run(
            ["git", "status", "--porcelain=v1", "--untracked-files=all", "-z"],
            cwd=root,
            check=True,
            capture_output=True,
        )
    except (OSError, subprocess.CalledProcessError) as error:
        raise SourceGuardError("Cannot inspect source checkout changes") from error

    records = result.stdout.split(b"\0")
    if records and records[-1] == b"":
        records.pop()
    paths: list[bytes] = []
    index = 0
    while index < len(records):
        record = records[index]
        if len(record) < 4 or record[2:3] != b" ":
            raise SourceGuardError("Git returned an invalid source checkout status")
        status = record[:2]
        paths.append(record[3:])
        if b"R" in status or b"C" in status:
            index += 1
            if index >= len(records):
                raise SourceGuardError("Git returned an incomplete source rename status")
            paths.append(records[index])
        index += 1
    return paths


def author_archive_source_guard(root: Path, recorder_pr: int) -> tuple[str, str]:
    if isinstance(recorder_pr, bool) or recorder_pr <= 0:
        raise SourceGuardError("Author archive PR number must be positive")
    allowed_entry = f"deploy/version/entries/{recorder_pr}.yaml".encode("ascii")
    if any(path != allowed_entry for path in _worktree_paths(root)):
        raise SourceGuardError(
            "Author archive source checkout must be clean except for its own version entry"
        )
    source_sha = git_text(root, "rev-parse", "HEAD")
    return source_sha, source_inputs_sha256(root)


def ensure_source_unchanged(root: Path, source_sha: str, inputs_sha: str) -> None:
    if git_text(root, "rev-parse", "HEAD") != source_sha:
        raise SourceGuardError("Source HEAD changed during archive production")
    if source_inputs_sha256(root) != inputs_sha:
        raise SourceGuardError("Tracked source inputs changed during archive production")


def clean_worktree(root: Path) -> None:
    if _worktree_paths(root):
        raise SourceGuardError("Publisher source checkout must be clean")


def canonical_version(path: Path) -> str:
    value = path.read_text(encoding="utf-8").strip()
    if not re.fullmatch(r"(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)", value):
        raise SourceGuardError(f"Invalid canonical version.nfo: {value!r}")
    return value


def canonical_checkpoint(root: Path, version: str) -> None:
    try:
        state = json.loads((root / "deploy/version/version.yaml").read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise SourceGuardError("Cannot read the canonical release checkpoint") from error
    if state.get("current_version") != version:
        raise SourceGuardError("version.nfo differs from the canonical release checkpoint")
    applied = state.get("applied")
    if not isinstance(applied, list) or not applied or applied[-1].get("to_version") != version:
        raise SourceGuardError("Canonical release checkpoint has no matching applied version")
    entries = sorted((root / "deploy/version/entries").glob("*.yaml"))
    if entries:
        raise SourceGuardError("Publisher source still contains a pending version entry")


def publisher_source_guard(root: Path, expected_source: str) -> tuple[str, str]:
    if not re.fullmatch(r"[0-9a-f]{40}", expected_source):
        raise SourceGuardError("Publisher expected source must be a full Git SHA")
    if git_text(root, "rev-parse", "HEAD") != expected_source:
        raise SourceGuardError("Publisher HEAD does not match --expected-source")
    clean_worktree(root)
    origin_main = git_text(root, "rev-parse", "origin/main")
    ancestry = subprocess.run(["git", "merge-base", "--is-ancestor", expected_source, origin_main],
                              cwd=root)
    if ancestry.returncode:
        raise SourceGuardError("Publisher source is not an ancestor of origin/main")
    version = canonical_version(root / "version.nfo")
    for relative in ("version.nfo", "deploy/version/version.yaml"):
        expected = git_text(root, "show", f"{expected_source}:{relative}")
        materialized = git_text(root, "show", f"{origin_main}:{relative}")
        if expected != materialized:
            raise SourceGuardError("Publisher source is not the origin/main canonical checkpoint")
    canonical_checkpoint(root, version)
    return expected_source, source_inputs_sha256(root)
