#!/usr/bin/env python3
"""Inspect, safely extract, validate, and pack Leonardo MDLZ archives.

The helper deliberately handles transport only.  The Markdown document remains
declarative and must be validated by the versioned Leonardo format schema.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import stat
import sys
import unicodedata
import uuid
import zipfile
from dataclasses import dataclass
from pathlib import Path, PurePosixPath
from typing import Iterable, Iterator


ARCHIVE_SUFFIX = ".mdlz"
DOCUMENT_SUFFIXES = frozenset({".mdlf", ".mdlr"})
ASSET_PREFIX = "assets/"
CHUNK_SIZE = 1024 * 1024
MAX_ENTRIES = 1_024
MAX_MEMBER_BYTES = 64 * 1024 * 1024
MAX_TOTAL_BYTES = 256 * 1024 * 1024
MAX_COMPRESSION_RATIO = 500
MIN_RATIO_CHECK_BYTES = 64 * 1024
WINDOWS_DRIVE = re.compile(r"^[A-Za-z]:")
SUPPORTED_FORMAT_VERSIONS = frozenset({1})


class ArchiveError(ValueError):
    """A package violates the MDLZ transport contract or safety boundary."""


@dataclass(frozen=True)
class Limits:
    max_entries: int = MAX_ENTRIES
    max_member_bytes: int = MAX_MEMBER_BYTES
    max_total_bytes: int = MAX_TOTAL_BYTES
    max_compression_ratio: int = MAX_COMPRESSION_RATIO


@dataclass(frozen=True)
class ArchiveEntry:
    info: zipfile.ZipInfo
    name: str
    is_directory: bool


@dataclass(frozen=True)
class SourceEntry:
    path: Path
    name: str
    is_directory: bool


def _display_path(path: Path) -> str:
    return str(path.expanduser())


def _assert_regular_file(path: Path, label: str) -> None:
    try:
        mode = path.lstat().st_mode
    except FileNotFoundError as exc:
        raise ArchiveError(f"{label} does not exist: {path}") from exc
    if stat.S_ISLNK(mode):
        raise ArchiveError(f"{label} must not be a symlink: {path}")
    if not stat.S_ISREG(mode):
        raise ArchiveError(f"{label} must be a regular file: {path}")


def _assert_directory(path: Path, label: str, *, must_exist: bool = True) -> None:
    if not must_exist:
        return
    try:
        mode = path.lstat().st_mode
    except FileNotFoundError as exc:
        raise ArchiveError(f"{label} does not exist: {path}") from exc
    if stat.S_ISLNK(mode):
        raise ArchiveError(f"{label} must not be a symlink: {path}")
    if not stat.S_ISDIR(mode):
        raise ArchiveError(f"{label} must be a directory: {path}")


def _canonical_member_name(raw_name: str, *, is_directory: bool) -> str:
    """Return a safe POSIX member name, rejecting ambiguous path spellings."""

    if not raw_name or "\x00" in raw_name:
        raise ArchiveError("archive member has an empty name or NUL byte")
    if "\\" in raw_name:
        raise ArchiveError(f"archive member uses a backslash: {raw_name!r}")
    if raw_name.startswith("/") or WINDOWS_DRIVE.match(raw_name):
        raise ArchiveError(f"archive member is absolute: {raw_name!r}")

    name = raw_name[:-1] if is_directory and raw_name.endswith("/") else raw_name
    parts = name.split("/")
    if not name or any(part in {"", ".", ".."} for part in parts):
        raise ArchiveError(f"archive member is not a canonical relative path: {raw_name!r}")
    if any(ord(character) < 0x20 for character in name):
        raise ArchiveError(f"archive member contains a control character: {raw_name!r}")
    return name


def _collision_key(name: str) -> str:
    return unicodedata.normalize("NFC", name).casefold()


def _member_type(info: zipfile.ZipInfo) -> int:
    return stat.S_IFMT((info.external_attr >> 16) & 0xFFFF)


def _is_zip_directory(info: zipfile.ZipInfo) -> bool:
    return info.is_dir() or _member_type(info) == stat.S_IFDIR


def _validate_zip_members(
    archive: zipfile.ZipFile,
    limits: Limits = Limits(),
) -> tuple[list[ArchiveEntry], str]:
    infos = archive.infolist()
    if len(infos) > limits.max_entries:
        raise ArchiveError(f"archive contains too many entries (limit {limits.max_entries})")

    entries: list[ArchiveEntry] = []
    names: set[str] = set()
    total_bytes = 0
    documents: list[str] = []

    for info in infos:
        is_directory = _is_zip_directory(info)
        member_type = _member_type(info)
        if member_type == stat.S_IFLNK:
            raise ArchiveError(f"archive member is a symlink: {info.filename!r}")
        if member_type not in {0, stat.S_IFREG, stat.S_IFDIR}:
            raise ArchiveError(f"archive member has an unsupported file type: {info.filename!r}")
        if info.flag_bits & 0x1:
            raise ArchiveError(f"encrypted archive members are unsupported: {info.filename!r}")

        name = _canonical_member_name(info.filename, is_directory=is_directory)
        key = _collision_key(name)
        if key in names:
            raise ArchiveError(f"archive contains duplicate or colliding member names: {name!r}")
        names.add(key)

        if info.file_size < 0 or info.file_size > limits.max_member_bytes:
            raise ArchiveError(
                f"archive member is too large: {name!r} (limit {limits.max_member_bytes} bytes)"
            )
        total_bytes += info.file_size
        if total_bytes > limits.max_total_bytes:
            raise ArchiveError(f"archive expands beyond the total limit of {limits.max_total_bytes} bytes")
        if not is_directory and info.file_size >= MIN_RATIO_CHECK_BYTES:
            if info.compress_size <= 0 or info.file_size / info.compress_size > limits.max_compression_ratio:
                raise ArchiveError(f"archive member has a suspicious compression ratio: {name!r}")

        if is_directory:
            if name != "assets" and not name.startswith(ASSET_PREFIX):
                raise ArchiveError(f"only the assets directory may be present beside the document: {name!r}")
        elif _is_document_name(name):
            if "/" in name:
                raise ArchiveError(f"the document must be at the archive root: {name!r}")
            documents.append(name)
        elif name.startswith(ASSET_PREFIX):
            pass
        else:
            raise ArchiveError(f"non-document archive members must be below assets/: {name!r}")

        entries.append(ArchiveEntry(info=info, name=name, is_directory=is_directory))

    if len(documents) != 1:
        raise ArchiveError(f"archive must contain exactly one root .mdlf or .mdlr document (found {len(documents)})")
    return entries, documents[0]


def _is_document_name(name: str) -> bool:
    return "/" not in name and Path(name).suffix.lower() in DOCUMENT_SUFFIXES


def inspect_archive(path: Path, limits: Limits = Limits()) -> dict[str, object]:
    _assert_regular_file(path, "archive")
    if path.suffix.lower() != ARCHIVE_SUFFIX:
        raise ArchiveError(f"archive must use the {ARCHIVE_SUFFIX} extension: {path}")
    try:
        with zipfile.ZipFile(path, "r") as archive:
            entries, document = _validate_zip_members(archive, limits)
            return {
                "archive": _display_path(path),
                "document": document,
                "entries": [
                    {
                        "path": entry.name,
                        "directory": entry.is_directory,
                        "compressedBytes": entry.info.compress_size,
                        "uncompressedBytes": entry.info.file_size,
                    }
                    for entry in sorted(entries, key=lambda item: item.name)
                ],
                "totalUncompressedBytes": sum(entry.info.file_size for entry in entries),
                "limits": {
                    "maxEntries": limits.max_entries,
                    "maxMemberBytes": limits.max_member_bytes,
                    "maxTotalBytes": limits.max_total_bytes,
                    "maxCompressionRatio": limits.max_compression_ratio,
                },
            }
    except zipfile.BadZipFile as exc:
        raise ArchiveError(f"not a valid ZIP archive: {path}") from exc


def _ensure_within(root: Path, candidate: Path) -> None:
    try:
        candidate.relative_to(root)
    except ValueError as exc:
        raise ArchiveError(f"archive member escapes the extraction directory: {candidate}") from exc


def _write_archive_member(archive: zipfile.ZipFile, entry: ArchiveEntry, target: Path) -> None:
    target.parent.mkdir(parents=True, exist_ok=True)
    for parent in [target.parent, *target.parent.parents]:
        if parent == target.parent.parent:
            break
        if parent.exists() and parent.is_symlink():
            raise ArchiveError(f"extraction path contains a symlink: {parent}")
    flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL
    try:
        descriptor = os.open(target, flags, 0o600)
    except FileExistsError as exc:
        raise ArchiveError(f"duplicate extraction target: {target}") from exc
    try:
        with os.fdopen(descriptor, "wb") as output, archive.open(entry.info, "r") as source:
            remaining = entry.info.file_size
            while remaining:
                chunk = source.read(min(CHUNK_SIZE, remaining))
                if not chunk:
                    raise ArchiveError(f"archive member ended before its declared size: {entry.name!r}")
                output.write(chunk)
                remaining -= len(chunk)
            if source.read(1):
                raise ArchiveError(f"archive member exceeded its declared size: {entry.name!r}")
    except Exception:
        try:
            target.unlink()
        except FileNotFoundError:
            pass
        raise


def extract_archive(path: Path, destination: Path, limits: Limits = Limits()) -> dict[str, object]:
    _assert_regular_file(path, "archive")
    if path.suffix.lower() != ARCHIVE_SUFFIX:
        raise ArchiveError(f"archive must use the {ARCHIVE_SUFFIX} extension: {path}")
    if os.path.lexists(destination):
        raise ArchiveError(f"extraction destination already exists: {destination}")
    parent = destination.parent
    _assert_directory(parent, "extraction destination parent")

    temporary = parent / f".{destination.name}.mdlz-extract-{uuid.uuid4().hex}"
    temporary.mkdir(mode=0o700)
    try:
        with zipfile.ZipFile(path, "r") as archive:
            entries, document = _validate_zip_members(archive, limits)
            for entry in entries:
                target = temporary.joinpath(*entry.name.split("/"))
                _ensure_within(temporary, target)
                if entry.is_directory:
                    target.mkdir(parents=True, exist_ok=True)
                    continue
                _write_archive_member(archive, entry, target)
        try:
            temporary.rename(destination)
        except FileExistsError as exc:
            raise ArchiveError(f"extraction destination appeared during extraction: {destination}") from exc
        return {
            "archive": _display_path(path),
            "destination": _display_path(destination),
            "document": document,
            "entries": len(entries),
        }
    except zipfile.BadZipFile as exc:
        raise ArchiveError(f"not a valid ZIP archive: {path}") from exc
    finally:
        if temporary.exists():
            shutil.rmtree(temporary, ignore_errors=True)


def _iter_source_entries(root: Path, limits: Limits = Limits()) -> tuple[list[SourceEntry], str]:
    _assert_directory(root, "source directory")
    entries: list[SourceEntry] = []
    names: set[str] = set()
    documents: list[str] = []
    total_bytes = 0

    for current, directory_names, file_names in os.walk(root, topdown=True, followlinks=False):
        current_path = Path(current)
        for directory_name in sorted(directory_names):
            directory = current_path / directory_name
            mode = directory.lstat().st_mode
            if stat.S_ISLNK(mode):
                raise ArchiveError(f"source directory contains a symlink: {directory}")
            if not stat.S_ISDIR(mode):
                raise ArchiveError(f"source directory contains a special entry: {directory}")
            relative = directory.relative_to(root).as_posix()
            name = _canonical_member_name(relative, is_directory=True)
            if name != "assets" and not name.startswith(ASSET_PREFIX):
                raise ArchiveError(f"only assets/ may contain source files: {name!r}")
            key = _collision_key(name)
            if key in names:
                raise ArchiveError(f"source names collide after normalization: {name!r}")
            names.add(key)
            entries.append(SourceEntry(path=directory, name=name, is_directory=True))

        for file_name in sorted(file_names):
            file_path = current_path / file_name
            _assert_regular_file(file_path, "source member")
            relative = file_path.relative_to(root).as_posix()
            name = _canonical_member_name(relative, is_directory=False)
            if _is_document_name(name):
                if "/" in name:
                    raise ArchiveError(f"the document must be at the source root: {name!r}")
                documents.append(name)
            elif name.startswith(ASSET_PREFIX):
                pass
            else:
                raise ArchiveError(f"non-document source files must be below assets/: {name!r}")
            key = _collision_key(name)
            if key in names:
                raise ArchiveError(f"source names collide after normalization: {name!r}")
            names.add(key)
            size = file_path.stat().st_size
            if size > limits.max_member_bytes:
                raise ArchiveError(f"source member is too large: {name!r}")
            total_bytes += size
            if total_bytes > limits.max_total_bytes:
                raise ArchiveError(f"source expands beyond the total limit of {limits.max_total_bytes} bytes")
            entries.append(SourceEntry(path=file_path, name=name, is_directory=False))

    if len(documents) != 1:
        raise ArchiveError(f"source must contain exactly one root .mdlf or .mdlr document (found {len(documents)})")
    return entries, documents[0]


def _zip_directory_info(name: str) -> zipfile.ZipInfo:
    info = zipfile.ZipInfo(name.rstrip("/") + "/")
    info.date_time = (1980, 1, 1, 0, 0, 0)
    info.create_system = 3
    info.external_attr = (stat.S_IFDIR | 0o755) << 16 | 0x10
    info.compress_type = zipfile.ZIP_STORED
    return info


def _zip_file_info(name: str) -> zipfile.ZipInfo:
    info = zipfile.ZipInfo(name)
    info.date_time = (1980, 1, 1, 0, 0, 0)
    info.create_system = 3
    info.external_attr = (stat.S_IFREG | 0o644) << 16
    info.compress_type = zipfile.ZIP_DEFLATED
    return info


def pack_directory(source: Path, output: Path, limits: Limits = Limits()) -> dict[str, object]:
    if output.suffix.lower() != ARCHIVE_SUFFIX:
        raise ArchiveError(f"package output must use the {ARCHIVE_SUFFIX} extension: {output}")
    if os.path.lexists(output):
        raise ArchiveError(f"package output already exists: {output}")
    _assert_directory(output.parent, "package output parent")
    entries, document = _iter_source_entries(source, limits)
    temporary = output.parent / f".{output.name}.mdlz-pack-{uuid.uuid4().hex}"
    try:
        with zipfile.ZipFile(
            temporary,
            "w",
            compression=zipfile.ZIP_DEFLATED,
            compresslevel=9,
            strict_timestamps=False,
        ) as archive:
            for entry in sorted(entries, key=lambda item: (not item.is_directory, item.name)):
                if entry.is_directory:
                    archive.writestr(_zip_directory_info(entry.name), b"")
                    continue
                info = _zip_file_info(entry.name)
                with entry.path.open("rb") as source_stream, archive.open(info, "w") as target:
                    shutil.copyfileobj(source_stream, target, length=CHUNK_SIZE)
        try:
            os.link(temporary, output)
        except FileExistsError as exc:
            raise ArchiveError(f"package output appeared during packing: {output}") from exc
        temporary.unlink()
        return {
            "source": _display_path(source),
            "archive": _display_path(output),
            "document": document,
            "entries": len(entries),
        }
    except Exception:
        try:
            temporary.unlink()
        except FileNotFoundError:
            pass
        raise


def _metadata_without_duplicate_keys(value: list[tuple[str, object]]) -> dict[str, object]:
    result: dict[str, object] = {}
    for key, item in value:
        if key in result:
            raise ValueError(f"duplicate metadata key: {key}")
        result[key] = item
    return result


def _parse_format_front_matter(text: str) -> dict[str, object]:
    normalized = text.replace("\r\n", "\n").replace("\r", "\n")
    if normalized.startswith("\ufeff"):
        normalized = normalized[1:]
    lines = normalized.split("\n")
    if not lines or lines[0].strip() != "---":
        raise ArchiveError("document is missing Leonardo front matter")
    closing_index = next(
        (index for index, line in enumerate(lines[1:], start=1) if line.strip() in {"---", "..."}),
        None,
    )
    if closing_index is None:
        raise ArchiveError("document has an unterminated front matter block")
    metadata_text = "\n".join(lines[1:closing_index]).strip()
    if not metadata_text:
        raise ArchiveError("document has empty front matter")
    try:
        metadata = json.loads(metadata_text, object_pairs_hook=_metadata_without_duplicate_keys)
    except (TypeError, ValueError, json.JSONDecodeError) as exc:
        raise ArchiveError(f"document front matter is not valid JSON: {exc}") from exc
    if not isinstance(metadata, dict):
        raise ArchiveError("document front matter must be a JSON object")
    if metadata.get("format") != "mdlf":
        raise ArchiveError("document front matter must identify the mdlf format")
    version = metadata.get("formatVersion")
    if isinstance(version, bool) or not isinstance(version, int):
        raise ArchiveError("document front matter must contain an integer formatVersion")
    if version not in SUPPORTED_FORMAT_VERSIONS:
        supported = ", ".join(str(item) for item in sorted(SUPPORTED_FORMAT_VERSIONS))
        raise ArchiveError(f"unsupported Leonardo formatVersion {version}; supported versions: {supported}")
    return metadata


def validate_document(path: Path) -> dict[str, object]:
    """Check the MDLF envelope, leaving detailed validation to the schema."""

    _assert_regular_file(path, "document")
    suffix = path.suffix.lower()
    if suffix not in DOCUMENT_SUFFIXES:
        raise ArchiveError(f"document must use .mdlf or .mdlr: {path}")
    size = path.stat().st_size
    if size > MAX_MEMBER_BYTES:
        raise ArchiveError(f"document is too large (limit {MAX_MEMBER_BYTES} bytes)")
    data = path.read_bytes()
    try:
        text = data.decode("utf-8")
    except UnicodeDecodeError as exc:
        raise ArchiveError(f"document is not valid UTF-8: {path}") from exc
    if "\x00" in text:
        raise ArchiveError(f"document contains a NUL byte: {path}")

    metadata = _parse_format_front_matter(text)
    document_metadata = metadata.get("document")
    kind = document_metadata.get("kind") if isinstance(document_metadata, dict) else None
    if suffix == ".mdlr" and kind != "form":
        raise ArchiveError(".mdlr documents must declare document.kind as form")
    fields = metadata.get("fields")
    values = metadata.get("values")
    if fields is not None and not isinstance(fields, dict):
        raise ArchiveError("document fields metadata must be an object")
    if values is not None and not isinstance(values, dict):
        raise ArchiveError("document values metadata must be an object")
    return {
        "document": _display_path(path),
        "extension": suffix,
        "utf8": True,
        "bytes": len(data),
        "format": metadata["format"],
        "formatVersion": metadata["formatVersion"],
        "documentKind": kind,
        "fieldCount": len(fields) if isinstance(fields, dict) else 0,
        "valueCount": len(values) if isinstance(values, dict) else 0,
        "semanticValidation": "Use the versioned Leonardo schema under doc/format.",
    }


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)

    inspect_command = commands.add_parser("inspect", help="validate and describe an MDLZ archive")
    inspect_command.add_argument("archive", type=Path)

    extract_command = commands.add_parser("extract", help="safely extract an MDLZ archive into a new folder")
    extract_command.add_argument("archive", type=Path)
    extract_command.add_argument("destination", type=Path)

    pack_command = commands.add_parser("pack", help="pack one MDLF/MDLR and assets/ into an MDLZ archive")
    pack_command.add_argument("source", type=Path)
    pack_command.add_argument("output", type=Path)

    validate_command = commands.add_parser("validate", help="validate an MDLF/MDLR or MDLZ transport")
    validate_command.add_argument("path", type=Path)
    return parser


def _run(arguments: argparse.Namespace) -> dict[str, object]:
    if arguments.command == "inspect":
        return inspect_archive(arguments.archive)
    if arguments.command == "extract":
        return extract_archive(arguments.archive, arguments.destination)
    if arguments.command == "pack":
        return pack_directory(arguments.source, arguments.output)
    if arguments.command == "validate":
        if arguments.path.suffix.lower() == ARCHIVE_SUFFIX:
            return inspect_archive(arguments.path)
        return validate_document(arguments.path)
    raise ArchiveError(f"unknown command: {arguments.command}")


def main(argv: Iterable[str] | None = None) -> int:
    arguments = _parser().parse_args(list(argv) if argv is not None else None)
    try:
        result = _run(arguments)
    except (ArchiveError, OSError, zipfile.BadZipFile) as exc:
        print(f"mdlz.py: error: {exc}", file=sys.stderr)
        return 2
    print(json.dumps(result, ensure_ascii=False, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
