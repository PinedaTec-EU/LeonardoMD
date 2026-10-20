#!/usr/bin/env python3
"""Authenticate installed stable maturity after successful exact-artifact promotion.

Runs on the maintainer Mac; Sparkle reads the existing signing key from Keychain.
No package bytes, update subscriptions, tags or release classification are changed.
"""
import argparse
import base64
import hashlib
import json
import plistlib
import re
import subprocess
import tempfile
import xml.etree.ElementTree as ET
import zipfile
from pathlib import Path

REPOSITORY = "PinedaTec-EU/LeonardoMD"
SPARKLE = "{http://www.andymatuschak.org/xml-namespaces/sparkle}"
ROOT = Path(__file__).resolve().parent.parent


def publication(archive, version):
    """Bind the signed assertion to the exact executable in the published ZIP."""
    with zipfile.ZipFile(archive) as package:
        plist_name = "LeonardoMD.app/Contents/Info.plist"
        names = package.namelist()
        if names.count(plist_name) != 1:
            raise ValueError("Expected exactly one application plist")
        info = plistlib.loads(package.read(plist_name))
        executable = info.get("CFBundleExecutable")
        if not isinstance(executable, str) or not re.fullmatch(r"[A-Za-z0-9_-]+", executable):
            raise ValueError("Invalid application executable")
        executable_name = f"LeonardoMD.app/Contents/MacOS/{executable}"
        if names.count(executable_name) != 1:
            raise ValueError("Expected exactly one application executable")
        if (info.get("CFBundleShortVersionString") != version
                or info.get("CFBundleVersion") != version.split(".")[-1]
                or info.get("LeonardoUpdateChannel") not in {"beta", "stable"}):
            raise ValueError("Package identity does not match release")
        with Path(archive).open("rb") as source:
            archive_digest = hashlib.file_digest(source, "sha256").hexdigest()
        payload = {"schema": 1, "repository": REPOSITORY, "version": version,
                   "build": info["CFBundleVersion"], "channel": "stable",
                   "archiveSHA256": archive_digest,
                   "executableSHA256": hashlib.sha256(package.read(executable_name)).hexdigest()}
    return payload, info


def run(*args):
    return subprocess.check_output(args, text=True).strip()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--tag", required=True)
    parser.add_argument("--account", default="LeonardoMD-stable")
    parser.add_argument("--publish", action="store_true", help="Upload the verified proof to the already stable release")
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if not re.fullmatch(r"v(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.[1-9][0-9]*", args.tag):
        parser.error("An exact numeric tag is required")
    if args.output.exists():
        parser.error("Output already exists; preserve the previous evidence")
    version = args.tag[1:]
    endpoint = f"repos/{REPOSITORY}/releases/tags/{args.tag}"
    release = json.loads(run("gh", "api", endpoint))
    if release["draft"] or release["prerelease"] or release["tag_name"] != args.tag:
        raise ValueError("Only an already published stable release can be authenticated")
    tools = ROOT / ".build/artifacts/sparkle/Sparkle/bin"
    with tempfile.TemporaryDirectory(prefix="leonardo-maturity-") as directory:
        directory = Path(directory)
        archive_name = f"LeonardoMD-{version}.zip"
        for name in (archive_name, "appcast.xml"):
            run("gh", "release", "download", args.tag, "--repo", REPOSITORY,
                "--pattern", name, "--dir", str(directory))
        payload, info = publication(directory / archive_name, version)
        trusted = plistlib.loads((ROOT / "scripts/Info.plist").read_bytes())["LeonardoUpdatePublicKey"]
        if (info.get("SUPublicEDKey") != trusted or info.get("LeonardoUpdatePublicKey") != trusted
                or run(str(tools / "generate_keys"), "--account", args.account, "-p") != trusted):
            raise ValueError("Signing account/package does not match pinned trust root")
        run("python3", str(ROOT / "scripts/verify-release-appcast.py"), str(directory / "appcast.xml"), "stable")
        items = ET.parse(directory / "appcast.xml").findall("./channel/item")
        matching = [item for item in items if item.findtext(SPARKLE + "version") == payload["build"]]
        if len(matching) != 1:
            raise ValueError("Expected one stable appcast item for this package")
        item = matching[0]
        enclosure = item.find("enclosure")
        expected_url = f"https://github.com/{REPOSITORY}/releases/download/{args.tag}/{archive_name}"
        if (item.find(SPARKLE + "channel") is not None or enclosure is None
                or enclosure.get("url") != expected_url
                or int(enclosure.get("length", "-1")) != (directory / archive_name).stat().st_size):
            raise ValueError("Stable appcast does not bind the expected archive")
        run(str(tools / "sign_update"), "--account", args.account, "--verify",
            str(directory / archive_name), enclosure.attrib[SPARKLE + "edSignature"])
        raw = json.dumps(payload, sort_keys=True, separators=(",", ":")).encode()
        payload_path = directory / "publication.bin"
        payload_path.write_bytes(raw)
        signature = run(str(tools / "sign_update"), "--account", args.account, "-p", str(payload_path))
        if len(base64.b64decode(signature, validate=True)) != 64:
            raise ValueError("Invalid signature output")
        run(str(tools / "sign_update"), "--account", args.account, "--verify", str(payload_path), signature)
        proof = json.dumps({"payload": base64.b64encode(raw).decode(), "signature": signature}, indent=2) + "\n"
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(proof)
        if args.publish:
            # Recheck before the external write; do not replace an existing immutable assertion.
            current = json.loads(run("gh", "api", endpoint))
            expected_assets = {a["name"]: (a["id"], a.get("digest"), a["size"]) for a in release["assets"]
                               if a["name"] in {archive_name, "appcast.xml"}}
            current_assets = {a["name"]: (a["id"], a.get("digest"), a["size"]) for a in current["assets"]
                              if a["name"] in {archive_name, "appcast.xml"}}
            if (current["id"] != release["id"] or current["draft"] or current["prerelease"]
                    or current_assets != expected_assets):
                raise ValueError("Release changed while preparing proof")
            asset = directory / "release-maturity.json"
            asset.write_text(proof)
            run("gh", "release", "upload", args.tag, str(asset), "--repo", REPOSITORY)
            verified = directory / "readback"
            verified.mkdir()
            run("gh", "release", "download", args.tag, "--repo", REPOSITORY,
                "--pattern", asset.name, "--dir", str(verified))
            if (verified / asset.name).read_bytes() != asset.read_bytes():
                raise ValueError("Published proof differs from signed proof")
        print(f"Verified stable maturity for {version}; published={args.publish}; output={args.output}")


if __name__ == "__main__":
    main()
