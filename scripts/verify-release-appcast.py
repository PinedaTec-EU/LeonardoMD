#!/usr/bin/env python3
"""Reject incomplete or unsigned release appcasts before publication."""
import base64
import sys
import re
from urllib.parse import urlparse, unquote
import xml.etree.ElementTree as ET
from pathlib import Path

SPARKLE = "{http://www.andymatuschak.org/xml-namespaces/sparkle}"
LEONARDO = "{https://pinedatec.eu/xml-namespaces/leonardo}"
ET.register_namespace("sparkle", SPARKLE[1:-1])
ET.register_namespace("leonardo", LEONARDO[1:-1])
PREFIX = "https://github.com/PinedaTec-EU/LeonardoMD/releases/download/"


def validate_sparkle_channel(item, channel):
    markers = item.findall(SPARKLE + "channel")
    expected = [] if channel == "stable" else ["beta"]
    if [marker.text for marker in markers] != expected:
        raise ValueError("Appcast channel does not match selected release channel")


def bind_channel(path, channel):
    """Bind generated publication metadata without changing Sparkle semantics."""
    if channel not in ("stable", "beta"):
        raise ValueError("Unknown release channel")
    tree = ET.parse(path)
    items = tree.findall("./channel/item")
    if not items:
        raise ValueError("Appcast contains no releases")
    for item in items:
        validate_sparkle_channel(item, channel)
        existing = item.get(LEONARDO + "channel")
        if existing is not None and existing != channel:
            raise ValueError("Cannot relabel an existing publication channel")
        item.set(LEONARDO + "channel", channel)
    tree.write(path, encoding="utf-8", xml_declaration=True)


def verify(path, channel="stable"):
    if channel not in ("stable", "beta"):
        raise ValueError("Unknown release channel")
    items = ET.parse(path).findall("./channel/item")
    if not items:
        raise ValueError("Appcast contains no releases")
    for item in items:
        if item.get(LEONARDO + "channel") != channel:
            raise ValueError("Missing or mismatched publication channel binding")
        validate_sparkle_channel(item, channel)
        enclosure = item.find("enclosure")
        if enclosure is None:
            raise ValueError("Missing update enclosure")
        signature = enclosure.get(SPARKLE + "edSignature", "")
        if len(base64.b64decode(signature, validate=True)) != 64:
            raise ValueError("Missing or malformed EdDSA signature")
        if not enclosure.get("url", "").startswith(PREFIX):
            raise ValueError("Update must reference this repository's HTTPS release assets")
        release_path = unquote(urlparse(enclosure.get("url")).path)
        release_tag = release_path.split("/download/", 1)[1].split("/", 1)[0]
        pattern = r"v[0-9]+\.[0-9]+\.[0-9]+"
        if not re.fullmatch(pattern, release_tag):
            raise ValueError("Release tag must use the numeric canonical version")
        displayed_version = item.find(SPARKLE + "shortVersionString")
        if displayed_version is not None and displayed_version.text != release_tag[1:]:
            raise ValueError("Displayed update version must match the numeric release tag")
        if int(enclosure.get("length", "0")) <= 0:
            raise ValueError("Empty update archive")
        version = item.find(SPARKLE + "version")
        if version is None or not re.fullmatch(r"[1-9][0-9]*", version.text or ""):
            raise ValueError("Missing numeric build version")


if __name__ == "__main__":
    path = Path(sys.argv[1])
    channel = sys.argv[2] if len(sys.argv) > 2 else "stable"
    if len(sys.argv) == 4 and sys.argv[3] == "--bind":
        bind_channel(path, channel)
    else:
        verify(path, channel)
