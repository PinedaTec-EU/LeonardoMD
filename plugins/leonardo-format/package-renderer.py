#!/usr/bin/env python3
"""Refresh the self-contained Leonardo Format plugin renderer bundle."""
import argparse
from pathlib import Path
from zipfile import ZIP_DEFLATED, ZipFile, ZipInfo

PLUGIN = Path(__file__).resolve().parent
SOURCE = PLUGIN.parents[1] / "Sources/LeonardoRender/Resources"
CORE_SOURCE = PLUGIN.parents[1] / "Sources/LeonardoCore/Resources"
OUTPUT = PLUGIN / "skills/leonardo-format/references/renderer.zip"

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--output", type=Path, default=OUTPUT)
arguments = parser.parse_args()

with ZipFile(arguments.output, "w", compression=ZIP_DEFLATED) as archive:
    for path in sorted(SOURCE.rglob("*")):
        if path.is_file() and not path.name.startswith("."):
            entry = ZipInfo(path.relative_to(SOURCE).as_posix())
            archive.writestr(entry, path.read_bytes(), compress_type=ZIP_DEFLATED)
    for source, destination in (
        (CORE_SOURCE / "marked.umd.js", Path("marked.umd.js")),
        (CORE_SOURCE / "marked-15.0.7.txt", Path("licenses/marked-15.0.7.txt")),
    ):
        entry = ZipInfo(destination.as_posix())
        archive.writestr(entry, source.read_bytes(), compress_type=ZIP_DEFLATED)
