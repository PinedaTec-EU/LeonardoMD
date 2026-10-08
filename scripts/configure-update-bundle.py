#!/usr/bin/env python3
"""Apply public release metadata only; never reads or stores a private signing key."""
import base64
import os
import plistlib
import re
import sys
from urllib.parse import unquote, urlparse
import posixpath
from pathlib import Path


def configure(path, environment):
    with path.open("rb") as source:
        metadata = plistlib.load(source)
    canonical = metadata.get("CFBundleShortVersionString")
    canonical_build = metadata.get("CFBundleVersion")
    ledger_version = (Path(__file__).resolve().parent.parent / "version.nfo").read_text().strip()
    version = environment.get("LEONARDO_VERSION", canonical or ledger_version)
    build = environment.get("LEONARDO_BUILD", canonical_build or ledger_version.split(".")[2])
    channel = environment.get("LEONARDO_CHANNEL", "stable")
    if channel not in ("stable", "beta"):
        raise ValueError("LEONARDO_CHANNEL must be stable or beta")
    if canonical is not None:
        expected = canonical if channel == "stable" else canonical + "-beta."
        if (build != canonical_build
                or (channel == "stable" and version != expected)
                or (channel == "beta" and not version.startswith(expected))):
            raise ValueError("Release metadata must match the canonical packaged ledger version/build")
    key = environment.get("SPARKLE_PUBLIC_KEY", "")
    pattern = r"[0-9]+\.[0-9]+\.[0-9]+" + (r"-beta\.[1-9][0-9]*" if channel == "beta" else "")
    if not re.fullmatch(pattern, version):
        raise ValueError("Version must match the selected channel (release.feature.build or release.feature.build-beta.N)")
    feed = environment.get("LEONARDO_FEED_URL",
        "https://raw.githubusercontent.com/PinedaTec-EU/LeonardoMD/update-feeds/beta/appcast.xml" if channel == "beta"
        else "https://github.com/PinedaTec-EU/LeonardoMD/releases/latest/download/appcast.xml")
    parsed = urlparse(feed)
    # Reject alternate URL spellings rather than relying on server/client normalization.
    if (unquote(parsed.path) != parsed.path or posixpath.normpath(parsed.path) != parsed.path
            or parsed.path.startswith("//") or "%" in (parsed.hostname or "")
            or "\\" in feed or any(character.isspace() for character in feed)):
        raise ValueError("Update feed must use a canonical, unescaped path")
    stable_feed = ("github.com", "/PinedaTec-EU/LeonardoMD/releases/latest/download/appcast.xml")
    beta_feed = ("raw.githubusercontent.com", "/PinedaTec-EU/LeonardoMD/update-feeds/beta/appcast.xml")
    forbidden_feed = stable_feed if channel == "beta" else beta_feed
    host = (parsed.hostname or "").rstrip(".")
    host = {"www.github.com": "github.com", "raw.github.com": "raw.githubusercontent.com"}.get(host, host)
    if (host, parsed.path.casefold()) == (forbidden_feed[0], forbidden_feed[1].casefold()):
        raise ValueError("Known release feed belongs to the opposite channel")
    if parsed.scheme != "https" or not parsed.hostname or parsed.username or parsed.password or parsed.fragment:
        raise ValueError("Update feed must be an HTTPS URL without credentials or fragments")
    if not re.fullmatch(r"[1-9][0-9]*", build):
        raise ValueError("LEONARDO_BUILD must be a positive, monotonically increasing integer")
    if key and len(base64.b64decode(key, validate=True)) != 32:
        raise ValueError("SPARKLE_PUBLIC_KEY must encode a 32-byte Ed25519 public key")
    if environment.get("LEONARDO_DISTRIBUTION") == "1" and not key:
        raise ValueError("Distribution requires SPARKLE_PUBLIC_KEY")
    metadata["SUFeedURL"] = feed
    metadata["LeonardoUpdateChannel"] = channel
    metadata["CFBundleVersion"] = build
    metadata["CFBundleShortVersionString"] = version
    metadata.pop("SUPublicEDKey", None)
    if key:
        metadata["SUPublicEDKey"] = key
    with path.open("wb") as target:
        plistlib.dump(metadata, target)


if __name__ == "__main__":
    configure(Path(sys.argv[1]), os.environ)
