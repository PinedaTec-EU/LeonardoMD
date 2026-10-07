#!/usr/bin/env python3
"""Reject incomplete or unsigned release appcasts before publication."""
import base64
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

SPARKLE = "{http://www.andymatuschak.org/xml-namespaces/sparkle}"
PREFIX = "https://github.com/PinedaTec-EU/LeonardoMD/releases/download/"


def verify(path):
    items = ET.parse(path).findall("./channel/item")
    if not items:
        raise ValueError("Appcast contains no releases")
    for item in items:
        enclosure = item.find("enclosure")
        if enclosure is None:
            raise ValueError("Missing update enclosure")
        signature = enclosure.get(SPARKLE + "edSignature", "")
        if len(base64.b64decode(signature, validate=True)) != 64:
            raise ValueError("Missing or malformed EdDSA signature")
        if not enclosure.get("url", "").startswith(PREFIX):
            raise ValueError("Update must reference this repository's HTTPS release assets")
        if int(enclosure.get("length", "0")) <= 0:
            raise ValueError("Empty update archive")
        version = item.find(SPARKLE + "version")
        if version is None or not (version.text or "").isdigit():
            raise ValueError("Missing numeric build version")


if __name__ == "__main__":
    verify(Path(sys.argv[1]))
