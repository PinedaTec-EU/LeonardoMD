#!/usr/bin/env python3
"""Copy the central generated changes into the bundle, checking package identity."""
import argparse
import json
from pathlib import Path
import shutil


def package_changes(source: Path, version_file: Path, destination: Path) -> None:
    artifact = json.loads(source.read_text(encoding="utf-8"))
    version = version_file.read_text(encoding="utf-8").strip()
    if (artifact.get("schema_version") != 1 or artifact.get("version") != version
            or artifact.get("repository") != "PinedaTec-EU/LeonardoMD"
            or not isinstance(artifact.get("changes"), list)):
        raise ValueError("Central release changes must match the canonical packaged version and repository")
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(source, destination)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("version", type=Path)
    parser.add_argument("destination", type=Path)
    args = parser.parse_args()
    try:
        package_changes(args.source, args.version, args.destination)
    except (OSError, ValueError) as error:
        parser.exit(1, f"package-release-changes: {error}\n")


if __name__ == "__main__":
    main()
