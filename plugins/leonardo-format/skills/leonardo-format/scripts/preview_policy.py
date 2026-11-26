"""Shared local-file policy for the Sync-owned Leonardo preview."""
from __future__ import annotations

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
    protected = managed_sync_roots() if roots is None else roots
    return any(root == canonical or root in canonical.parents for root in protected)
