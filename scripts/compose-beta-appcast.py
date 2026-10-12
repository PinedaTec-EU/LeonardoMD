#!/usr/bin/env python3
"""Atomically prepare a beta subscription feed; never publish or relabel releases."""
import argparse
import copy
import importlib.util
import os
from pathlib import Path
import tempfile
import xml.etree.ElementTree as ET

_spec = importlib.util.spec_from_file_location("release_appcast", Path(__file__).with_name("verify-release-appcast.py"))
release_appcast = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(release_appcast)


def compose(stable, beta, output):
    release_appcast.verify(stable, "stable")
    release_appcast.verify(beta, "beta")
    stable_tree = ET.parse(stable)
    beta_tree = ET.parse(beta)
    tree = copy.deepcopy(stable_tree)
    channel = tree.find("channel")
    for item in channel.findall("item"):
        channel.remove(item)
    items = stable_tree.findall("./channel/item") + beta_tree.findall("./channel/item")
    builds = set()
    releases = set()
    for item in items:
        build = int(item.find(release_appcast.SPARKLE + "version").text)
        # One numeric build/tag identifies one immutable package, not two channels.
        url = item.find("enclosure").get("url")
        release = release_appcast.release_tag(url)
        if build in builds or release in releases:
            raise ValueError("Stable and beta releases must have distinct increasing builds and tags")
        builds.add(build)
        releases.add(release)
    for item in sorted(items, key=lambda i: int(i.find(release_appcast.SPARKLE + "version").text), reverse=True):
        channel.append(copy.deepcopy(item))
    # Validation above must complete before replacing any existing publication artifact.
    output.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary = tempfile.mkstemp(prefix=".beta-appcast-", dir=output.parent)
    try:
        with os.fdopen(descriptor, "wb") as target:
            tree.write(target, encoding="utf-8", xml_declaration=True)
            target.flush()
            os.fsync(target.fileno())
        os.replace(temporary, output)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--stable", type=Path, required=True, help="Validated stable-only appcast")
    parser.add_argument("--beta", type=Path, required=True, help="Validated beta-only appcast")
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    try:
        if args.output.resolve() in (args.stable.resolve(), args.beta.resolve()):
            raise ValueError("Output must not overwrite an input release appcast")
        compose(args.stable, args.beta, args.output)
    except (OSError, ValueError, ET.ParseError) as error:
        parser.exit(1, f"Beta feed rejected: {error}\n")
