#!/usr/bin/env python3
"""Derive macOS bundle metadata from the canonical release version."""
import argparse
import plistlib
import re
from pathlib import Path


def package_version(version_path: Path, template_path: Path, output_path: Path) -> None:
    version = version_path.read_text(encoding="utf-8").strip()
    if not re.fullmatch(r"(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)", version):
        raise ValueError("version.nfo must contain release.feature.build with non-negative integers")
    build = int(version.split(".")[2])
    if not 1 <= build <= 9999:
        raise ValueError("build must be between 1 and 9999 for the macOS build number")
    with template_path.open("rb") as handle:
        metadata = plistlib.load(handle)
    if "CFBundleShortVersionString" in metadata or "CFBundleVersion" in metadata:
        raise ValueError("The plist template must not maintain independent version fields")
    metadata["CFBundleShortVersionString"] = version
    metadata["CFBundleVersion"] = str(build)
    with output_path.open("wb") as handle:
        plistlib.dump(metadata, handle, sort_keys=False)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("version", type=Path)
    parser.add_argument("template", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    try:
        package_version(args.version, args.template, args.output)
    except (ValueError, OSError, plistlib.InvalidFileException) as error:
        parser.exit(1, f"package-version: {error}\n")


if __name__ == "__main__":
    main()
