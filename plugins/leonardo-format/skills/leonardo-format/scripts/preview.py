#!/usr/bin/env python3
"""Serve a read-only Leonardo document to a local browser."""
from __future__ import annotations

import argparse
import html
import json
import os
from contextlib import ExitStack
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path
import secrets
import stat
import time
from urllib.parse import unquote, urlsplit
from zipfile import BadZipFile, ZipFile

from mdlz import (
    ArchiveError, Limits, MAX_MEMBER_BYTES, _assert_archive_file,
    _validate_zip_members, read_document_bytes,
)

RENDERER = Path(__file__).resolve().parent.parent / "references" / "renderer.zip"
STYLES = ("preview", "leonardo-forms", "table-resizing", "katex.min", "markdown-extras")
SCRIPTS = (
    "marked.umd", "dompurify.min", "highlight.min", "mermaid.min", "katex.min",
    "preview-editing", "table-layout", "table-resizing", "leonardo-calendar",
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
    "img-src 'self' data:; font-src 'self'; form-action 'none'; "
    "base-uri 'self'; frame-ancestors 'none'; sandbox allow-scripts allow-same-origin"
)


def safe_components(name: str) -> list[str]:
    parts = name.split("/")
    if len(parts) > 64 or any(
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

    candidate = root.joinpath(*parts)
    if candidate.resolve(strict=True) != candidate or not candidate.is_file():
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
    with source.open("rb") as handle:
        metadata, body = read_document_bytes(source, read_regular(handle.fileno()))
    return metadata, body, None


def make_page(source: Path, prefix: str, metadata: dict, body: str) -> bytes:
    payload = {
        "leonardo": metadata, "markdown": body, "source": "",
        "allowsEditing": False, "allowsFormFilling": False,
        "allowsMermaid": True, "allowsMath": True, "allowsVegaLite": True,
        "allowsCitations": True, "allowsMarkdownExtensions": True,
        "frontMatter": {}, "tags": [],
    }
    data = json.dumps(payload).replace("<", r"\u003c")
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
</head>
<body>
<main id="leonardo-markdown" class="markdown-body"></main>
<script id="leonardo-payload" type="application/json">{data}</script>
{js}
</body>
</html>
""".encode()


class PreviewServer(HTTPServer):
    timeout = 0.5

    def __init__(self, source: Path):
        self.root = source.parent
        self.prefix = f"/{secrets.token_urlsafe(24)}/"
        self.page_path = self.prefix + "preview"
        metadata, body, self.images = load_document(source)
        self.page = make_page(source, self.prefix, metadata, body)
        with ZipFile(RENDERER) as archive:
            self.resources = {
                name: archive.read(name)
                for name in archive.namelist()
                if Path(name).suffix in RESOURCE_TYPES
            }
        self.resources["extension-engines.js"] = self.resources["extension-engines.js"].replace(
            b"leonardo-resource://bundle/", (self.prefix + "renderer/").encode()
        )
        super().__init__(("127.0.0.1", 0), PreviewRequest)

    @property
    def url(self) -> str:
        return f"http://127.0.0.1:{self.server_port}{self.page_path}"


class PreviewRequest(BaseHTTPRequestHandler):
    server: PreviewServer
    timeout = 5

    def do_GET(self) -> None:
        try:
            path = unquote(urlsplit(self.path).path, errors="strict")
            if self.headers.get("Host") != f"127.0.0.1:{self.server.server_port}":
                raise ValueError("unexpected host")
            if not path.startswith(self.server.prefix):
                raise ValueError("unknown preview")
            route = path.removeprefix(self.server.prefix)
            content, content_type = self.resource(route)
        except (KeyError, OSError, ValueError):
            self.send_error(404)
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
            return self.server.page, "text/html; charset=utf-8"
        kind, _, name = route.partition("/")
        safe_components(name)
        suffix = Path(name).suffix.lower()
        if kind == "renderer":
            return self.server.resources[name], RESOURCE_TYPES[suffix]
        if kind == "images":
            mime = IMAGE_TYPES[suffix]
            if self.server.images is not None:
                return self.server.images[name], mime
            return read_local_image(self.server.root, name), mime
        raise KeyError(route)

    def log_message(self, *_args: object) -> None:
        # Request paths contain the private preview URL or document asset names.
        pass


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("document", type=Path)
    arguments = parser.parse_args()
    try:
        with PreviewServer(arguments.document.resolve(strict=True)) as server:
            print(server.url, flush=True)
            deadline = time.monotonic() + LIFETIME_SECONDS
            while time.monotonic() < deadline:
                server.handle_request()
    except KeyboardInterrupt:
        return 0
    except (ArchiveError, OSError, ValueError, BadZipFile, RuntimeError) as error:
        parser.exit(1, f"Leonardo preview: {error}\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
