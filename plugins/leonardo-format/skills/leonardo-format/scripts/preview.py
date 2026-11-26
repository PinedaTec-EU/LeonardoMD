#!/usr/bin/env python3
"""Register a read-only Leonardo document with the persistent local helper."""
from __future__ import annotations

import argparse
import html
import json
import os
import re
from contextlib import ExitStack
from http.server import BaseHTTPRequestHandler
from pathlib import Path
import stat
from urllib.parse import unquote, urlsplit
from zipfile import ZipFile

from mdlz import (
    ArchiveError, Limits, MAX_MEMBER_BYTES, _assert_archive_file,
    _validate_zip_members, read_document_bytes,
)
from preview_policy import ManagedSyncPathError, is_managed_sync_path

RENDERER = Path(__file__).resolve().parent.parent / "references" / "renderer.zip"
STYLES = ("preview", "leonardo-forms", "table-resizing", "katex.min", "markdown-extras")
SCRIPTS = (
    "marked.umd", "dompurify.min", "highlight.min", "mermaid.min", "katex.min",
    "preview-editing", "table-layout", "table-pagination", "table-resizing", "leonardo-calendar",
    "leonardo-forms", "leonardo-layout", "leonardo-objects", "image-loading",
    "extension-engines", "vega-charts", "leonardo-citations", "markdown-extras",
    "extension-detection", "renderer-runtime",
)
IMAGE_TYPES = {
    ".png": "image/png", ".jpg": "image/jpeg", ".jpeg": "image/jpeg",
    ".gif": "image/gif", ".webp": "image/webp", ".svg": "image/svg+xml",
    ".bmp": "image/bmp", ".tif": "image/tiff", ".tiff": "image/tiff",
    ".avif": "image/avif", ".ico": "image/x-icon",
}
RESOURCE_TYPES = {
    ".js": "text/javascript", ".css": "text/css", ".woff": "font/woff",
    ".woff2": "font/woff2", ".ttf": "font/ttf",
}
LIFETIME_SECONDS = 60 * 60
CSP = (
    "default-src 'none'; script-src 'self'; style-src 'self' 'unsafe-inline'; "
    "connect-src 'self'; img-src 'self' data:; font-src 'self'; form-action 'none'; "
    "base-uri 'self'; frame-ancestors 'none'; sandbox allow-scripts allow-same-origin"
)
HEALTH_SCRIPT = b"""(() => {
    const indicator = document.getElementById("leonardo-http-status");
    const spanish = navigator.language.toLowerCase().startsWith("es");
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 3000);
    indicator.textContent = spanish ? "Comprobando HTTP..." : "Checking HTTP...";
    function show(healthy) {
        indicator.dataset.state = healthy ? "healthy" : "unavailable";
        indicator.textContent = healthy
            ? (spanish ? "HTTP operativo" : "HTTP available")
            : (spanish ? "HTTP no disponible" : "HTTP unavailable");
    }
    fetch("/health", {cache: "no-store", signal: controller.signal, redirect: "error"})
        .then(response => show(response.status === 200))
        .catch(() => show(false))
        .finally(() => clearTimeout(timeout));
})();"""


def safe_components(name: str) -> list[str]:
    parts = name.split("/")
    if len(name) > 2048 or len(parts) > 64 or any(
        part in {"", ".", ".."} or any(ord(char) < 32 or char in "\\:" for char in part)
        for part in parts
    ):
        raise ValueError("invalid asset path")
    return parts


def read_regular(fd: int) -> bytes:
    info = os.fstat(fd)
    if not stat.S_ISREG(info.st_mode) or info.st_size > MAX_MEMBER_BYTES:
        raise ValueError("asset is not a supported regular file")
    with os.fdopen(fd, "rb", closefd=False) as handle:
        data = handle.read(MAX_MEMBER_BYTES + 1)
    if len(data) > MAX_MEMBER_BYTES:
        raise ValueError("asset exceeds the size limit")
    return data


def read_local_image(root: Path, name: str) -> bytes:
    parts = safe_components(name)
    candidate = root.joinpath(*parts)
    try:
        canonical = candidate.resolve(strict=True)
    except OSError as error:
        raise ValueError("asset must be a regular file below the document folder") from error
    if is_managed_sync_path(canonical):
        raise ManagedSyncPathError("managed Sync content is not available to Codex preview")
    if os.open in os.supports_dir_fd and hasattr(os, "O_NOFOLLOW"):
        with ExitStack() as stack:
            directory_flags = os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW
            directory = os.open(root, directory_flags)
            stack.callback(os.close, directory)
            for part in parts[:-1]:
                directory = os.open(part, directory_flags, dir_fd=directory)
                stack.callback(os.close, directory)
            fd = os.open(parts[-1], os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK, dir_fd=directory)
            stack.callback(os.close, fd)
            return read_regular(fd)

    if canonical != candidate or not candidate.is_file():
        raise ValueError("asset must be a regular file below the document folder")
    with candidate.open("rb") as handle:
        return read_regular(handle.fileno())


def load_document(source: Path) -> tuple[dict, str, dict[str, bytes] | None]:
    if source.suffix.lower() == ".mdlz":
        limits = Limits()
        _assert_archive_file(source, limits)
        with ZipFile(source) as archive:
            entries, name = _validate_zip_members(archive, limits)
            metadata, body = read_document_bytes(Path(name), archive.read(name))
            images = {
                entry.name: archive.read(entry.info)
                for entry in entries
                if Path(entry.name).suffix.lower() in IMAGE_TYPES
            }
        return metadata, body, images

    if source.suffix.lower() not in {".mdlf", ".mdlr"} or not source.is_file():
        raise ArchiveError("select a local .mdlf, .mdlr or .mdlz file")
    if not hasattr(os, "O_NOFOLLOW"):
        raise ArchiveError("the host cannot safely open a local preview")
    fd = os.open(source, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    with os.fdopen(fd, "rb") as handle:
        metadata, body = read_document_bytes(source, read_regular(handle.fileno()))
    return metadata, body, None


def _asset_references(metadata: object, body: str) -> set[str]:
    """Return only relative image references declared by the document."""
    references: set[str] = set()

    def add(value: object) -> None:
        if not isinstance(value, str) or not value or "\x00" in value:
            return
        value = unquote(value).strip()
        if value.startswith(("http://", "https://", "data:", "#")):
            return
        if value.startswith("./"):
            value = value[2:]
        if "/" not in value and Path(value).suffix.lower() not in IMAGE_TYPES:
            return
        try:
            safe_components(value)
        except ValueError:
            return
        references.add(value)

    def walk(value: object, key: str | None = None) -> None:
        if isinstance(value, dict):
            for child_key, child in value.items():
                if child_key in {"source", "image"}:
                    add(child)
                walk(child, child_key)
        elif isinstance(value, list):
            for child in value:
                walk(child, key)

    walk(metadata)
    # Markdown inline image destinations. The renderer's parser accepts the
    # same ordinary relative paths; angle destinations preserve spaces.
    for match in re.finditer(
        r"!\[[^\]]*\]\(\s*(?:<([^>\r\n]+)>|([^\s)\r\n]+))", body
    ):
        add(match.group(1) or match.group(2))
    for match in re.finditer(
        r"<img\b[^>]*\bsrc\s*=\s*(?:\"([^\"]+)\"|'([^']+)'|([^\s>]+))",
        body,
        flags=re.IGNORECASE,
    ):
        add(match.group(1) or match.group(2) or match.group(3))
    # Reference-style image definitions are intentionally restricted to the
    # definition destination; an undeclared reference cannot reveal a file.
    definitions = re.finditer(
        r"(?m)^\s*\[[^\]]+\]:\s*(?:<([^>\r\n]+)>|([^\s]+))", body
    )
    for match in definitions:
        add(match.group(1) or match.group(2))
    return references


def make_page(source: Path, prefix: str, metadata: dict, body: str) -> bytes:
    fields = metadata.get("fields")
    guided_fields = sorted(
        field_id for field_id, field in (fields.items() if isinstance(fields, dict) else ())
        if isinstance(field, dict) and isinstance(field.get("signerPosition"), str)
    )
    payload = {
        "leonardo": metadata, "markdown": body, "source": "",
        "allowsEditing": False, "allowsFormFilling": False,
        "allowsLeonardoFormat": True,
        "allowsMermaid": True, "allowsMath": True, "allowsVegaLite": True,
        "allowsCitations": True, "allowsMarkdownExtensions": True,
        "frontMatter": {}, "showFrontMatter": False, "tags": [],
        "guidedSigningFieldIDs": guided_fields,
        "guidedSigningRubricOverlays": {},
    }
    data = json.dumps(payload, ensure_ascii=False).replace("<", r"\u003c")
    css = "\n".join(f'<link rel="stylesheet" href="{prefix}renderer/{name}.css">' for name in STYLES)
    js = "\n".join(f'<script src="{prefix}renderer/{name}.js"></script>' for name in SCRIPTS)
    return f"""<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{html.escape(source.name)} · Leonardo</title>
<base href="{prefix}images/">
{css}
<style>
#leonardo-http-status {{ margin: 1rem 1rem 0; font: .875rem system-ui; }}
#leonardo-http-status::before {{
    content: ""; display: inline-block; width: .65em; height: .65em;
    border-radius: 50%; background: currentColor; margin-inline-end: .5em;
}}
#leonardo-http-status[data-state="healthy"]::before {{ background: #24a148; }}
#leonardo-http-status[data-state="unavailable"]::before {{ background: #da1e28; }}
</style>
</head>
<body>
<p id="leonardo-http-status" role="status">Checking HTTP...</p>
<script src="{prefix}health-status.js"></script>
<main id="leonardo-markdown" class="markdown-body"></main>
<script id="leonardo-payload" type="application/json">{data}</script>
{js}
</body>
</html>
""".encode()


class PreviewRequest(BaseHTTPRequestHandler):
    timeout = 5

    def do_GET(self) -> None:
        try:
            parsed = urlsplit(self.path)
            path = unquote(parsed.path, errors="strict")
            if self.headers.get("Host") != f"127.0.0.1:{self.server.server_port}":
                raise ValueError("unexpected host")
            if path == "/health":
                route = "health"
                content, content_type = b"ok\n", "text/plain; charset=utf-8"
            else:
                self.preview = self.select_preview(path)
                route = path.removeprefix(self.preview.prefix)
                content, content_type = self.resource(route)
        except (KeyError, OSError, UnicodeDecodeError, ValueError):
            self.send_error(404, "Preview or resource unavailable. Open the document again.")
            return

        self.send_response(200)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(content)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("Referrer-Policy", "no-referrer")
        self.send_header("Cross-Origin-Resource-Policy", "same-origin")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("Content-Security-Policy", CSP if route == "preview" else "sandbox; default-src 'none'")
        self.end_headers()
        self.wfile.write(content)

    def resource(self, route: str) -> tuple[bytes, str]:
        if route == "preview":
            return self.preview.page, "text/html; charset=utf-8"
        if route == "health-status.js":
            return HEALTH_SCRIPT, "text/javascript"
        kind, _, name = route.partition("/")
        safe_components(name)
        suffix = Path(name).suffix.lower()
        if kind == "renderer":
            content = self.server.resources[name]
            if name == "extension-engines.js":
                content = content.replace(
                    b"leonardo-resource://bundle/", (self.preview.prefix + "renderer/").encode()
                )
            return content, RESOURCE_TYPES[suffix]
        if kind == "images":
            mime = IMAGE_TYPES[suffix]
            if name not in self.preview.allowed_images:
                raise KeyError(name)
            if self.preview.images is not None:
                return self.preview.images[name], mime
            return read_local_image(self.preview.root, name), mime
        raise KeyError(route)

    def log_message(self, *_args: object) -> None:
        # Request paths contain the private preview URL and document assets.
        pass


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("document", type=Path)
    arguments = parser.parse_args()
    from urllib.error import HTTPError
    from preview_service import PreviewUnavailable, register

    try:
        print(register(arguments.document), flush=True)
    except HTTPError as error:
        parser.exit(1, f"Leonardo preview: {error.reason}\n")
    except PreviewUnavailable:
        parser.exit(
            1,
            "Leonardo preview unavailable. Enable Leonardo Sync. If it remains unavailable, install a supported "
            "Python 3.9+ interpreter from a trusted source (for example Homebrew or "
            "python.org); macOS /usr/bin/python3 is not used. Restart Leonardo Sync "
            "and retry.\n",
        )
    except (ArchiveError, OSError, ValueError, KeyError):
        parser.exit(1, "Leonardo preview rejected this file. Use a local .mdlf, .mdlr or .mdlz with supported resources.\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
