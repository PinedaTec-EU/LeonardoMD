"""Descriptor-relative, no-follow extraction for MDLZ archives.

The caller validates the ZIP envelope and the root document before invoking
this module.  This module owns only the destination claim, descriptor-relative
directory traversal, member writes, and ownership-aware failure cleanup.
"""

from __future__ import annotations

import errno
import os
import posixpath
import stat
import zipfile
from contextlib import contextmanager
from dataclasses import dataclass
from pathlib import Path
from typing import Callable, Iterator, Protocol, Sequence


MAX_PATH_COMPONENTS = 64
DIRECTORY_MODE = 0o700
FILE_MODE = 0o600
_SYSTEM_ALIAS_TARGETS = {"tmp": "/private/tmp", "var": "/private/var"}


class SecureExtractionError(ValueError):
    """The destination cannot be handled by the secure extraction boundary."""


class SecureExtractionUnavailable(SecureExtractionError):
    """The host does not expose the descriptor-relative no-follow API."""


class ArchiveEntryLike(Protocol):
    name: str
    info: zipfile.ZipInfo


EventCallback = Callable[[str, str], None]


@dataclass(frozen=True)
class _Identity:
    device: int
    inode: int
    file_type: int


@dataclass(frozen=True)
class _OwnedPath:
    parts: tuple[str, ...]
    identity: _Identity
    is_directory: bool


def _emit(callback: EventCallback | None, event: str, name: str) -> None:
    if callback is not None:
        callback(event, name)


def _identity_from_stat(result: os.stat_result) -> _Identity:
    return _Identity(
        device=result.st_dev,
        inode=result.st_ino,
        file_type=stat.S_IFMT(result.st_mode),
    )


def _same_identity(result: os.stat_result, expected: _Identity) -> bool:
    return _identity_from_stat(result) == expected


def _directory_flags() -> int:
    return (
        os.O_RDONLY
        | os.O_DIRECTORY
        | os.O_NOFOLLOW
        | getattr(os, "O_CLOEXEC", 0)
    )


def _require_capabilities() -> None:
    missing: list[str] = []
    if not callable(getattr(os, "geteuid", None)):
        missing.append("geteuid")
    if not isinstance(getattr(os, "O_NOFOLLOW", None), int) or os.O_NOFOLLOW == 0:
        missing.append("O_NOFOLLOW")
    if not isinstance(getattr(os, "O_DIRECTORY", None), int) or os.O_DIRECTORY == 0:
        missing.append("O_DIRECTORY")

    supports_dir_fd = getattr(os, "supports_dir_fd", ()) or ()
    for function, name in (
        (os.open, "open(dir_fd=)"),
        (os.mkdir, "mkdir(dir_fd=)"),
        (os.stat, "stat(dir_fd=)"),
        (os.unlink, "unlink(dir_fd=)"),
        (os.rmdir, "rmdir(dir_fd=)"),
    ):
        if function not in supports_dir_fd:
            missing.append(name)
    if os.stat not in (getattr(os, "supports_follow_symlinks", ()) or ()):
        missing.append("stat(follow_symlinks=False)")
    if missing:
        raise SecureExtractionUnavailable(
            "secure extraction requires POSIX descriptor-relative no-follow support "
            f"({', '.join(missing)})"
        )


def _path_components(destination: Path) -> tuple[bool, tuple[str, ...]]:
    raw = os.fspath(destination)
    if isinstance(raw, bytes):
        raw = os.fsdecode(raw)
    if not raw or "\x00" in raw:
        raise SecureExtractionError("extraction destination is empty or contains a NUL byte")

    absolute = raw.startswith("/")
    raw_parts = raw.split("/")
    if any(part == ".." for part in raw_parts):
        raise SecureExtractionError("extraction destination must not contain '..' components")
    parts = tuple(part for part in raw_parts if part not in {"", "."})
    if not parts:
        raise SecureExtractionError("extraction destination must name a directory")

    if absolute and parts[0] in _SYSTEM_ALIAS_TARGETS:
        alias = parts[0]
        alias_path = f"/{alias}"
        try:
            alias_stat = os.lstat(alias_path)
        except FileNotFoundError:
            pass
        except OSError as error:
            raise SecureExtractionError(f"could not inspect system path alias: {alias_path}") from error
        else:
            if stat.S_ISLNK(alias_stat.st_mode):
                try:
                    target = posixpath.normpath(posixpath.join("/", os.readlink(alias_path)))
                except OSError as error:
                    raise SecureExtractionError(
                        f"could not inspect system path alias: {alias_path}"
                    ) from error
                if alias_stat.st_uid != 0 or target != _SYSTEM_ALIAS_TARGETS[alias]:
                    raise SecureExtractionError(
                        f"extraction destination contains an unsupported symlink: {alias_path}"
                    )
                parts = ("private", alias, *parts[1:])

    return absolute, parts


def _raise_open_error(name: str, error: OSError) -> None:
    if error.errno == errno.ELOOP:
        raise SecureExtractionError(f"extraction path contains a symlink: {name}") from error
    if error.errno == errno.ENOENT:
        raise SecureExtractionError(f"extraction path does not exist: {name}") from error
    if error.errno == errno.ENOTDIR:
        raise SecureExtractionError(f"extraction path component is not a directory: {name}") from error
    raise SecureExtractionError(f"could not open extraction path component: {name}") from error


def _open_directory_at(parent_fd: int, name: str) -> int:
    try:
        descriptor = os.open(name, _directory_flags(), dir_fd=parent_fd)
    except OSError as error:
        if error.errno == errno.ENOTDIR:
            try:
                entry = os.stat(name, dir_fd=parent_fd, follow_symlinks=False)
            except OSError:
                entry = None
            if entry is not None and stat.S_ISLNK(entry.st_mode):
                raise SecureExtractionError(f"extraction path contains a symlink: {name}") from error
        _raise_open_error(name, error)
    try:
        result = os.fstat(descriptor)
    except OSError:
        os.close(descriptor)
        raise
    if not stat.S_ISDIR(result.st_mode):
        os.close(descriptor)
        raise SecureExtractionError(f"extraction path component is not a directory: {name}")
    return descriptor


def _stat_at(parent_fd: int, name: str) -> os.stat_result:
    try:
        return os.stat(name, dir_fd=parent_fd, follow_symlinks=False)
    except OSError as error:
        if error.errno == errno.ELOOP:
            raise SecureExtractionError(f"extraction path contains a symlink: {name}") from error
        raise


def _open_start_directory(absolute: bool) -> int:
    start = "/" if absolute else "."
    try:
        return os.open(start, _directory_flags())
    except OSError as error:
        _raise_open_error(start, error)


def _close(descriptor: int | None) -> None:
    if descriptor is not None:
        try:
            os.close(descriptor)
        except OSError:
            pass


def _open_destination_parent(
    absolute: bool,
    parent_parts: Sequence[str],
    callback: EventCallback | None,
) -> int:
    current = _open_start_directory(absolute)
    traversed: list[str] = []
    try:
        for component in parent_parts:
            traversed.append(component)
            relative_name = "/".join(traversed)
            _emit(callback, "before-parent-open", relative_name)
            child = _open_directory_at(current, component)
            _close(current)
            current = child
            _emit(callback, "after-parent-open", relative_name)
        return current
    except BaseException:
        _close(current)
        raise


@contextmanager
def _open_relative_directory(
    root_fd: int,
    parts: Sequence[str],
    owned: Sequence[_OwnedPath] | None = None,
) -> Iterator[int]:
    current = os.dup(root_fd)
    traversed: list[str] = []
    try:
        for component in parts:
            traversed.append(component)
            child = _open_directory_at(current, component)
            if owned is not None:
                expected = _owned_directory_identity(owned, tuple(traversed))
                try:
                    opened = os.fstat(child)
                except BaseException:
                    _close(child)
                    raise
                if expected is None or not _same_identity(opened, expected):
                    _close(child)
                    raise SecureExtractionError(
                        f"cleanup path component is no longer owned: {_relative_name(traversed)}"
                    )
            _close(current)
            current = child
        yield current
    except BaseException:
        _close(current)
        raise
    else:
        _close(current)


def _relative_name(parts: Sequence[str]) -> str:
    return "/".join(parts) or "."


def _owned_directory_identity(
    owned: Sequence[_OwnedPath],
    parts: tuple[str, ...],
) -> _Identity | None:
    for entry in owned:
        if entry.is_directory and entry.parts == parts:
            return entry.identity
    return None


def _claim_directory(
    parent_fd: int,
    parts: tuple[str, ...],
    owned: list[_OwnedPath],
    callback: EventCallback | None,
) -> int:
    name = parts[-1]
    display_name = _relative_name(parts)
    try:
        os.mkdir(name, DIRECTORY_MODE, dir_fd=parent_fd)
    except FileExistsError:
        try:
            existing = _stat_at(parent_fd, name)
        except OSError as error:
            raise SecureExtractionError(
                f"extraction directory appeared before it could be opened: {display_name}"
            ) from error
        if stat.S_ISLNK(existing.st_mode):
            raise SecureExtractionError(f"extraction path contains a symlink: {display_name}")
        expected = _owned_directory_identity(owned, parts)
        if expected is None:
            raise SecureExtractionError(
                f"extraction directory appeared before it could be claimed: {display_name}"
            )
        if not _same_identity(existing, expected):
            raise SecureExtractionError(f"extraction directory changed during extraction: {display_name}")
        descriptor = _open_directory_at(parent_fd, name)
        try:
            opened = os.fstat(descriptor)
        except BaseException:
            _close(descriptor)
            raise
        if not _same_identity(opened, expected):
            _close(descriptor)
            raise SecureExtractionError(f"extraction directory changed during extraction: {display_name}")
        try:
            _emit(callback, "directory-opened", display_name)
        except BaseException:
            _close(descriptor)
            raise
        return descriptor
    except OSError as error:
        raise SecureExtractionError(f"could not create extraction directory: {display_name}") from error

    try:
        identity_stat = _stat_at(parent_fd, name)
    except OSError as error:
        raise SecureExtractionError(f"created extraction directory disappeared: {display_name}") from error
    if not stat.S_ISDIR(identity_stat.st_mode) or identity_stat.st_uid != os.geteuid():
        raise SecureExtractionError(f"created extraction path is not a directory: {display_name}")
    identity = _identity_from_stat(identity_stat)
    owned.append(_OwnedPath(parts=parts, identity=identity, is_directory=True))
    _emit(callback, "directory-claimed", display_name)

    descriptor: int | None = None
    try:
        descriptor = _open_directory_at(parent_fd, name)
        opened_stat = os.fstat(descriptor)
    except BaseException:
        _close(descriptor)
        raise
    if not _same_identity(opened_stat, identity):
        _close(descriptor)
        raise SecureExtractionError(f"extraction directory changed during claim: {display_name}")
    try:
        _emit(callback, "directory-opened", display_name)
    except BaseException:
        _close(descriptor)
        raise
    return descriptor


def _open_member_parent(
    root_fd: int,
    parent_parts: tuple[str, ...],
    owned: list[_OwnedPath],
    callback: EventCallback | None,
) -> int:
    current = os.dup(root_fd)
    traversed: list[str] = []
    try:
        for component in parent_parts:
            traversed.append(component)
            current_parts = tuple(traversed)
            child = _claim_directory(current, current_parts, owned, callback)
            _close(current)
            current = child
        return current
    except BaseException:
        _close(current)
        raise


def _validate_member_parts(name: str) -> tuple[str, ...]:
    parts = tuple(name.split("/"))
    if (
        not name
        or len(parts) > MAX_PATH_COMPONENTS
        or any(not part or part in {".", ".."} for part in parts)
    ):
        raise SecureExtractionError(f"archive member has an unsafe path: {name!r}")
    return parts


def _write_member(
    archive: zipfile.ZipFile,
    entry: ArchiveEntryLike,
    root_fd: int,
    owned: list[_OwnedPath],
    callback: EventCallback | None,
) -> None:
    parts = _validate_member_parts(entry.name)
    parent_fd = _open_member_parent(root_fd, parts[:-1], owned, callback)
    name = parts[-1]
    try:
        try:
            descriptor = os.open(
                name,
                os.O_WRONLY
                | os.O_CREAT
                | os.O_EXCL
                | os.O_NOFOLLOW
                | getattr(os, "O_CLOEXEC", 0),
                FILE_MODE,
                dir_fd=parent_fd,
            )
        except FileExistsError as error:
            raise SecureExtractionError(
                f"extraction destination entry already exists: {entry.name}"
            ) from error
        except OSError as error:
            if error.errno == errno.ELOOP:
                raise SecureExtractionError(f"extraction path contains a symlink: {entry.name}") from error
            raise SecureExtractionError(f"could not create extracted file: {entry.name}") from error

        try:
            identity = _identity_from_stat(os.fstat(descriptor))
            owned.append(
                _OwnedPath(parts=parts, identity=identity, is_directory=False)
            )
            _emit(callback, "file-created", entry.name)
            with os.fdopen(descriptor, "wb") as output:
                descriptor = -1
                try:
                    with archive.open(entry.info, "r") as source:
                        remaining = entry.info.file_size
                        while remaining:
                            chunk = source.read(min(1024 * 1024, remaining))
                            if not chunk:
                                raise SecureExtractionError(
                                    f"archive member ended before its declared size: {entry.name!r}"
                                )
                            output.write(chunk)
                            remaining -= len(chunk)
                        if source.read(1):
                            raise SecureExtractionError(
                                f"archive member exceeded its declared size: {entry.name!r}"
                            )
                except (OSError, RuntimeError, zipfile.BadZipFile) as error:
                    raise SecureExtractionError(
                        f"could not extract archive member: {entry.name!r}"
                    ) from error
        finally:
            if descriptor >= 0:
                _close(descriptor)
    finally:
        _close(parent_fd)


def _remove_owned_path(
    root_fd: int,
    entry: _OwnedPath,
    owned: Sequence[_OwnedPath],
) -> None:
    if not entry.parts:
        return
    parent_parts = entry.parts[:-1]
    name = entry.parts[-1]
    try:
        with _open_relative_directory(root_fd, parent_parts, owned) as parent_fd:
            current = _stat_at(parent_fd, name)
            if not _same_identity(current, entry.identity):
                return
            if entry.is_directory:
                os.rmdir(name, dir_fd=parent_fd)
            else:
                os.unlink(name, dir_fd=parent_fd)
    except (OSError, SecureExtractionError):
        return


def _remove_owned_root(parent_fd: int, name: str, identity: _Identity | None) -> None:
    if identity is None:
        return
    try:
        current = _stat_at(parent_fd, name)
        if _same_identity(current, identity):
            os.rmdir(name, dir_fd=parent_fd)
    except (OSError, SecureExtractionError):
        return


def _cleanup(
    root_fd: int | None,
    parent_fd: int | None,
    root_name: str,
    root_identity: _Identity | None,
    owned: list[_OwnedPath],
) -> None:
    if root_fd is not None:
        files = [entry for entry in owned if not entry.is_directory]
        directories = [entry for entry in owned if entry.is_directory]
        for entry in files:
            _remove_owned_path(root_fd, entry, owned)
        for entry in sorted(directories, key=lambda item: len(item.parts), reverse=True):
            _remove_owned_path(root_fd, entry, owned)
    if parent_fd is not None:
        _remove_owned_root(parent_fd, root_name, root_identity)


@dataclass(frozen=True)
class _ClaimedDestination:
    absolute: bool
    parent_parts: tuple[str, ...]
    parent_fd: int
    root_name: str
    root_fd: int
    identity: _Identity


def _verify_result(destination: _ClaimedDestination, owned: Sequence[_OwnedPath]) -> None:
    try:
        reopened = _open_destination_parent(destination.absolute, destination.parent_parts, None)
        try:
            if _identity_from_stat(os.fstat(reopened)) != _identity_from_stat(os.fstat(destination.parent_fd)):
                raise SecureExtractionError("extraction destination parent changed during extraction")
        finally:
            _close(reopened)
        if not _same_identity(_stat_at(destination.parent_fd, destination.root_name), destination.identity):
            raise SecureExtractionError("extraction destination changed during extraction")
        for entry in owned:
            with _open_relative_directory(destination.root_fd, entry.parts[:-1], owned) as directory:
                if not _same_identity(_stat_at(directory, entry.parts[-1]), entry.identity):
                    raise SecureExtractionError("an extracted entry changed during extraction")
    except OSError as error:
        raise SecureExtractionError("an extraction path disappeared or changed during extraction") from error


def extract_archive(
    archive: zipfile.ZipFile,
    entries: Sequence[ArchiveEntryLike],
    destination: Path,
    document: str,
    *,
    archive_display: str,
    destination_display: str | None = None,
    event_callback: EventCallback | None = None,
) -> dict[str, object]:
    """Extract validated entries into an atomically claimed destination."""

    _require_capabilities()
    displayed_destination = destination_display or str(destination)
    absolute, components = _path_components(destination)
    root_name = components[-1]
    parent_parts = components[:-1]
    parent_fd = _open_destination_parent(absolute, parent_parts, event_callback)
    root_fd: int | None = None
    root_identity: _Identity | None = None
    owned: list[_OwnedPath] = []
    try:
        try:
            os.mkdir(root_name, DIRECTORY_MODE, dir_fd=parent_fd)
        except FileExistsError as error:
            raise SecureExtractionError(
                f"extraction destination already exists: {destination}"
            ) from error
        except OSError as error:
            raise SecureExtractionError(
                f"could not claim extraction destination: {destination}"
            ) from error

        try:
            root_stat = _stat_at(parent_fd, root_name)
        except OSError as error:
            raise SecureExtractionError(
                f"claimed extraction destination disappeared: {destination}"
            ) from error
        if not stat.S_ISDIR(root_stat.st_mode) or root_stat.st_uid != os.geteuid():
            raise SecureExtractionError(f"claimed extraction destination is not a directory: {destination}")
        root_identity = _identity_from_stat(root_stat)
        _emit(event_callback, "root-claimed", str(destination))
        root_fd = _open_directory_at(parent_fd, root_name)
        if not _same_identity(os.fstat(root_fd), root_identity):
            raise SecureExtractionError(f"extraction destination changed during claim: {destination}")
        _emit(event_callback, "root-opened", str(destination))

        for entry in entries:
            _emit(event_callback, "member-start", entry.name)
            _write_member(archive, entry, root_fd, owned, event_callback)

        _emit(event_callback, "before-return", str(destination))
        _verify_result(
            _ClaimedDestination(
                absolute=absolute, parent_parts=tuple(parent_parts), parent_fd=parent_fd,
                root_name=root_name, root_fd=root_fd, identity=root_identity,
            ),
            owned,
        )

        return {
            "archive": archive_display,
            "destination": displayed_destination,
            "document": document,
            "entries": len(entries),
        }
    except BaseException:
        try:
            _emit(event_callback, "before-cleanup", str(destination))
        except BaseException:
            pass
        _cleanup(root_fd, parent_fd, root_name, root_identity, owned)
        raise
    finally:
        _close(root_fd)
        _close(parent_fd)
