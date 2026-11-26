"""Shared local-file policy for the Sync-owned Leonardo preview."""
from __future__ import annotations

import os
from pathlib import Path


MANAGED_STORAGE = Path("Library/Application Support/LeonardoMD")
MANAGED_SYNC_DIRECTORIES = ("DesktopPeers", "MobileSync")


class ManagedSyncPathError(ValueError):
    """A preview source or resource belongs to managed Sync storage."""


def managed_sync_roots(home: Path | None = None) -> tuple[Path, ...]:
    root = (home or Path.home()) / MANAGED_STORAGE
    return tuple((root / name).resolve(strict=False) for name in MANAGED_SYNC_DIRECTORIES)


def is_managed_sync_path(path: Path, roots: tuple[Path, ...] | None = None) -> bool:
    canonical = path.resolve(strict=False)
    protected = tuple(
        root.resolve(strict=False)
        for root in (managed_sync_roots() if roots is None else roots)
    )
    return any(_is_same_or_descendant(canonical, root) for root in protected)


def _is_same_or_descendant(path: Path, root: Path) -> bool:
    """Match lexical paths and filesystem identities on case-insensitive hosts."""
    if root == path or root in path.parents:
        return True

    # Path.resolve() preserves the caller's component spelling on macOS. Walk
    # existing ancestors and compare filesystem identities so an alternate
    # case cannot bypass the managed-storage boundary on a case-insensitive
    # volume. Missing descendants still reach an existing managed ancestor.
    probe = path
    while True:
        try:
            if os.path.samefile(probe, root):
                return True
        except PermissionError:
            # Fail closed if identity cannot be inspected safely.
            return True
        except OSError:
            pass
        parent = probe.parent
        if parent == probe:
            return False
        probe = parent
