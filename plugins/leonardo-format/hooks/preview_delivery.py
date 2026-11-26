"""Ask Codex to add missing preview links to a file delivery once per turn."""
from __future__ import annotations

import hashlib
import json
import os
import re
from pathlib import Path
import stat
import sys
from urllib.parse import unquote, urlsplit

# Codex links workspace artifacts using absolute Markdown link destinations.
# Accept angle-delimited destinations and filenames with balanced parentheses.
LINK = re.compile(r"(?<!!)\[([^\]\n]+)\]\((?:<([^>\n]+)>|((?:\\.|[^()\n]|\([^()\n]*\))+))\)")
FENCED_BLOCK = re.compile(r"(?ms)^ {0,3}(`{3,}|~{3,})[^\n]*\n.*?^ {0,3}\1[ \t]*(?:\n|$)")
DOCUMENT = re.compile(r"\.(mdlf|mdlr|mdlz)(?::\d+(?::\d+)?)?$", re.IGNORECASE)
PREVIEW_PATH = re.compile(r"^/[\w-]{32}/preview$")
DOCUMENT_FINGERPRINT = re.compile(r"^document=([0-9a-f]{64})$")
CONTINUATION = (
    "Complete the Leonardo file delivery before ending this turn. For each local "
    "MDLF, MDLR or MDLZ file you are delivering as a Markdown link and that lacks "
    "a preview, follow the Browser preview section of the installed Leonardo "
    "Format skill. Run its preview.py on the same machine as Codex, using the "
    "file path as a separate argument. Keep "
    "the original artifact links and include a clickable Markdown link labeled "
    "Vista previa de Leonardo beside each document, using the actual loopback "
    "URL printed by the helper. For this automatic delivery leave navigation "
    "to the user's click. If an authorized local preview cannot be registered, "
    "keep the original delivery and briefly explain why. Do not invent URLs."
)


def check_delivery(event: object) -> dict[str, str]:
    if not isinstance(event, dict) or event.get("stop_hook_active"):
        return {}
    message = event.get("last_assistant_message")
    if not isinstance(message, str):
        return {}
    cleaned = FENCED_BLOCK.sub(lambda match: "\n" * match.group(0).count("\n"), message)
    links = [
        (match.start(), match.end(), match.group(1).strip(), _target(match))
        for match in LINK.finditer(cleaned)
    ]
    local_documents = {
        document
        for _, _, _, target in links
        if (document := _local_document(target)) is not None
    }
    previews = {
        receipt
        for _, _, label, target in links
        if label == "Vista previa de Leonardo"
        and (receipt := _preview_fingerprint(target)) is not None
    }
    covered_documents = {
        document
        for document in local_documents
        if (fingerprint := _document_fingerprint(document)) is not None
        and fingerprint in previews
    }
    if local_documents - covered_documents:
        return {"decision": "block", "reason": CONTINUATION}
    return {}


def _target(match: re.Match[str]) -> str:
    _, angle, bare = match.groups()
    return unquote(re.sub(r"\\([()])", r"\1", (angle or bare).strip()))


def _local_document(target: str) -> str | None:
    if not (
        (target.startswith(("/", "./", "../")) and not target.startswith("//"))
        or re.match(r"^[A-Za-z]:[/\\]", target)
    ):
        return None
    if not DOCUMENT.search(target):
        return None
    return DOCUMENT.sub(lambda match: "." + match[1], target)


def _preview_fingerprint(target: str) -> str | None:
    try:
        parsed = urlsplit(target)
        if (
            parsed.scheme != "http"
            or parsed.hostname != "127.0.0.1"
            or parsed.username is not None
            or parsed.password is not None
            or parsed.query
            or parsed.port is None
            or not 1 <= parsed.port <= 65535
            or not PREVIEW_PATH.fullmatch(parsed.path)
        ):
            return None
    except ValueError:
        return None
    match = DOCUMENT_FINGERPRINT.fullmatch(parsed.fragment)
    return match.group(1) if match else None


def _document_fingerprint(document: str) -> str | None:
    # Keep this non-authoritative marker in sync with preview.py. It is only
    # a local association check; the helper URL remains the trust boundary.
    try:
        source = Path(document)
        source_info = source.lstat()
        if not stat.S_ISREG(source_info.st_mode):
            return None
        canonical = source.resolve(strict=True)
        canonical_info = canonical.lstat()
        if not stat.S_ISREG(canonical_info.st_mode):
            return None
    except OSError:
        return None
    return hashlib.sha256(os.fsencode(str(canonical))).hexdigest()


if __name__ == "__main__":
    try:
        event = json.load(sys.stdin)
    except (ValueError, RecursionError):
        event = None
    print(json.dumps(check_delivery(event)))
