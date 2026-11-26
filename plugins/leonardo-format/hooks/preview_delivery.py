"""Ask Codex to add missing preview links to a file delivery once per turn."""
from __future__ import annotations

import json
import re
import sys
from urllib.parse import unquote

# Codex links workspace artifacts using absolute Markdown link destinations.
# Accept angle-delimited destinations and filenames with balanced parentheses.
LINK = re.compile(r"(?<!!)\[[^\]\n]+\]\((?:<([^>\n]+)>|((?:\\.|[^()\n]|\([^()\n]*\))+))\)")
FENCED_BLOCK = re.compile(r"(?ms)^ {0,3}(`{3,}|~{3,})[^\n]*\n.*?^ {0,3}\1[ \t]*(?:\n|$)")
DOCUMENT = re.compile(r"\.(mdlf|mdlr|mdlz)(?::\d+(?::\d+)?)?$", re.IGNORECASE)
PREVIEW = re.compile(r"http://127\.0\.0\.1:\d{1,5}/[\w-]{32}/preview")
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
    targets = {
        unquote(re.sub(r"\\([()])", r"\1", (angle or bare).strip()))
        for angle, bare in LINK.findall(FENCED_BLOCK.sub("", message))
    }
    local_documents = {
        DOCUMENT.sub(lambda match: "." + match[1], target)
        for target in targets
        if (target.startswith(("/", "./", "../")) and not target.startswith("//")
            or re.match(r"^[A-Za-z]:[/\\]", target))
        and DOCUMENT.search(target)
    }
    previews = {target for target in targets if PREVIEW.fullmatch(target)}
    if len(local_documents) > len(previews):
        return {"decision": "block", "reason": CONTINUATION}
    return {}


if __name__ == "__main__":
    try:
        event = json.load(sys.stdin)
    except (ValueError, RecursionError):
        event = None
    print(json.dumps(check_delivery(event)))
