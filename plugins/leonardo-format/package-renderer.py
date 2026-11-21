#!/usr/bin/env python3
"""Refresh the self-contained Leonardo Format plugin renderer bundle."""
from pathlib import Path
from zipfile import ZIP_DEFLATED, ZipFile, ZipInfo

PLUGIN = Path(__file__).resolve().parent
SOURCE = PLUGIN.parents[1] / "Sources/LeonardoRender/Resources"
OUTPUT = PLUGIN / "skills/leonardo-format/references/renderer.zip"

with ZipFile(OUTPUT, "w", compression=ZIP_DEFLATED) as archive:
    for path in sorted(SOURCE.rglob("*")):
        if path.is_file() and not path.name.startswith("."):
            entry = ZipInfo(path.relative_to(SOURCE).as_posix())
            archive.writestr(entry, path.read_bytes(), compress_type=ZIP_DEFLATED)
