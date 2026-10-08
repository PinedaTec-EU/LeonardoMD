#!/usr/bin/env python3
"""Verify real archive bytes against the generated appcast using Sparkle."""
import subprocess
import sys
import xml.etree.ElementTree as ET
from pathlib import Path
from urllib.parse import unquote, urlparse

SPARKLE = "{http://www.andymatuschak.org/xml-namespaces/sparkle}"


def verify(feed, directory, tool, account):
    for item in ET.parse(feed).findall('./channel/item'):
        enclosure = item.find('enclosure')
        archive = directory / Path(unquote(urlparse(enclosure.attrib['url']).path)).name
        if archive.stat().st_size != int(enclosure.attrib['length']):
            raise ValueError('Archive length does not match appcast')
        subprocess.run([str(tool), '--account', account, '--verify', str(archive),
                        enclosure.attrib[SPARKLE + 'edSignature']], check=True)


if __name__ == '__main__':
    verify(Path(sys.argv[1]), Path(sys.argv[2]), Path(sys.argv[3]), sys.argv[4])
