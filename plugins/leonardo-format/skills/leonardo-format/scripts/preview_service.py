"""Persistent loopback preview service owned by the Leonardo Sync helper."""
from __future__ import annotations

from collections import OrderedDict
import hmac
import json
import os
from pathlib import Path
import secrets
import stat
import sys
import threading
import time
from http.server import HTTPServer
from urllib.parse import urlsplit
from urllib.error import HTTPError
from urllib.request import build_opener, ProxyHandler, Request
from zipfile import BadZipFile, ZipFile

from preview import (
    ArchiveError,
    LIFETIME_SECONDS,
    PreviewRequest,
    RESOURCE_TYPES,
    RENDERER,
    _asset_references,
    load_document,
    make_page,
    read_local_image,
)

ENDPOINT = Path.home() / "Library/Application Support/LeonardoMD/preview-endpoint.json"
MAX_PREVIEWS = 4
MAX_REQUEST = 16 * 1024
MAX_ENDPOINT_BYTES = 4 * 1024
MAX_DOCUMENT_PATH = 4 * 1024
MAX_PREVIEW_BYTES = 32 * 1024 * 1024
MANAGED_STORAGE = Path("Library/Application Support/LeonardoMD")
MANAGED_SYNC_DIRECTORIES = ("DesktopPeers", "MobileSync")


class PreviewUnavailable(RuntimeError):
    """The optional Sync-owned preview service is not reachable."""


def _unique_pairs(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError("duplicate registration key")
        result[key] = value
    return result


def _regular_source(path: Path) -> Path:
    if not path.is_absolute() or len(str(path)) > MAX_DOCUMENT_PATH:
        raise ValueError("expected an absolute document path")
    try:
        mode = path.lstat().st_mode
    except OSError as error:
        raise ValueError("document is not available") from error
    if stat.S_ISLNK(mode) or not stat.S_ISREG(mode):
        raise ValueError("document must be a regular file and not a symlink")
    canonical = path.resolve(strict=True)
    mode = canonical.lstat().st_mode
    if stat.S_ISLNK(mode) or not stat.S_ISREG(mode):
        raise ValueError("document must be a regular file and not a symlink")
    if _is_managed_source(canonical):
        raise ValueError("managed Sync content is not available to Codex preview")
    return canonical


def _managed_roots(home: Path | None = None) -> tuple[Path, ...]:
    root = (home or Path.home()) / MANAGED_STORAGE
    return tuple((root / name).resolve(strict=False) for name in MANAGED_SYNC_DIRECTORIES)


def _is_managed_source(path: Path, roots: tuple[Path, ...] | None = None) -> bool:
    canonical = path.resolve(strict=False)
    protected = _managed_roots() if roots is None else roots
    return any(root == canonical or root in canonical.parents for root in protected)


class Preview:
    def __init__(self, source: Path):
        self.source = _regular_source(source)
        self.root = self.source.parent
        self.prefix = f"/{secrets.token_urlsafe(24)}/"
        metadata, body, packaged_images = load_document(self.source)
        self.allowed_images = _asset_references(metadata, body)
        self.images: dict[str, bytes] = {}
        if packaged_images is not None:
            self.images = {
                name: data for name, data in packaged_images.items()
                if name in self.allowed_images
            }
        else:
            total = 0
            for name in sorted(self.allowed_images):
                try:
                    data = read_local_image(self.root, name)
                except (OSError, ValueError):
                    continue
                total += len(data)
                if total > MAX_PREVIEW_BYTES:
                    raise ArchiveError("preview resources exceed the size limit")
                self.images[name] = data
        self.page = make_page(self.source, self.prefix, metadata, body)
        self.deadline = time.monotonic() + LIFETIME_SECONDS


class Service(HTTPServer):
    allow_reuse_address = True

    def __init__(self):
        self.token = secrets.token_urlsafe(32)
        self.previews: OrderedDict[str, Preview] = OrderedDict()
        with ZipFile(RENDERER) as archive:
            self.resources = {
                name: archive.read(name) for name in archive.namelist()
                if Path(name).suffix.lower() in RESOURCE_TYPES
            }
        if "extension-engines.js" not in self.resources:
            raise ArchiveError("the bundled renderer is incomplete")
        super().__init__(("127.0.0.1", 0), ServiceRequest)

    def service_actions(self):
        now = time.monotonic()
        for prefix, preview in list(self.previews.items()):
            if now >= preview.deadline:
                del self.previews[prefix]

    def add_preview(self, preview: Preview) -> None:
        while len(self.previews) >= MAX_PREVIEWS:
            self.previews.popitem(last=False)
        self.previews[preview.prefix] = preview


class ServiceRequest(PreviewRequest):
    def do_POST(self) -> None:
        parsed = urlsplit(self.path)
        if (
            parsed.path != "/register"
            or parsed.query
            or self.headers.get("Host") != f"127.0.0.1:{self.server.server_port}"
            or not hmac.compare_digest(
                self.headers.get("Authorization", "").encode(),
                ("Bearer " + self.server.token).encode(),
            )
            or self.headers.get("Origin") is not None
        ):
            self.send_error(403)
            return
        try:
            size = int(self.headers.get("Content-Length", "0"))
            if not 0 < size <= MAX_REQUEST:
                raise ValueError("invalid registration size")
            payload = json.loads(self.rfile.read(size), object_pairs_hook=_unique_pairs)
            if set(payload) != {"document"} or not isinstance(payload["document"], str):
                raise ValueError("invalid registration payload")
            preview = Preview(Path(payload["document"]))
        except (ArchiveError, BadZipFile, KeyError, OSError, ValueError, TypeError, RuntimeError):
            self.send_error(422, "Cannot preview this document. Check its format and local access.")
            return

        self.server.add_preview(preview)
        body = f"http://127.0.0.1:{self.server.server_port}{preview.prefix}preview".encode()
        self.send_response(201)
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.end_headers()
        self.wfile.write(body)

    def select_preview(self, path: str) -> Preview:
        parts = path.split("/")
        if len(parts) < 3 or parts[0] != "" or not parts[1]:
            raise ValueError("unknown preview")
        prefix = f"/{parts[1]}/"
        preview = self.server.previews.get(prefix)
        if preview is None or time.monotonic() >= preview.deadline:
            self.server.previews.pop(prefix, None)
            raise ValueError("preview expired or unavailable")
        return preview


def _read_endpoint(endpoint: Path = ENDPOINT) -> dict[str, object]:
    if not hasattr(os, "O_NOFOLLOW"):
        raise ValueError("the host cannot safely open the preview endpoint")
    fd = os.open(endpoint, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    try:
        info = os.fstat(fd)
        if (
            not stat.S_ISREG(info.st_mode)
            or info.st_uid != os.getuid()
            or info.st_mode & 0o077
            or info.st_size > MAX_ENDPOINT_BYTES
        ):
            raise ValueError("invalid Leonardo Sync endpoint permissions")
        with os.fdopen(fd, "r") as handle:
            fd = -1
            config = json.load(handle, object_pairs_hook=_unique_pairs)
    finally:
        if fd >= 0:
            os.close(fd)
    if not isinstance(config, dict) or (
        set(config) != {"port", "token"}
        or not isinstance(config["port"], int)
        or isinstance(config["port"], bool)
        or not 1 <= config["port"] <= 65535
        or not isinstance(config["token"], str)
        or not 32 <= len(config["token"]) <= 128
    ):
        raise ValueError("invalid Leonardo Sync endpoint")
    return config


def register(source: Path, endpoint: Path = ENDPOINT) -> str:
    document = Path(source)
    if not document.is_absolute():
        document = Path(os.path.abspath(document))
    try:
        config = _read_endpoint(endpoint)
    except (OSError, TypeError, ValueError) as error:
        raise PreviewUnavailable("Leonardo Sync preview endpoint is unavailable") from error
    port = config["port"]
    request = Request(
        f"http://127.0.0.1:{port}/register",
        data=json.dumps({"document": str(document)}, separators=(",", ":")).encode(),
        headers={
            "Authorization": "Bearer " + config["token"],
            "Content-Type": "application/json",
        },
        method="POST",
    )
    try:
        with build_opener(ProxyHandler({})).open(request, timeout=10) as response:
            value = response.read(1024).decode("utf-8")
    except HTTPError:
        raise
    except (OSError, ValueError) as error:
        raise PreviewUnavailable("Leonardo Sync preview service is unavailable") from error
    if not value.startswith(f"http://127.0.0.1:{port}/"):
        raise ValueError("helper returned an invalid preview URL")
    return value


def _ensure_endpoint_parent(endpoint: Path) -> None:
    parent = endpoint.parent
    parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    info = parent.lstat()
    if not stat.S_ISDIR(info.st_mode) or info.st_uid != os.getuid() or info.st_mode & 0o077:
        raise ValueError("invalid Leonardo Sync endpoint directory permissions")


def _endpoint_token(endpoint: Path) -> str | None:
    try:
        config = _read_endpoint(endpoint)
    except (OSError, ValueError, TypeError, json.JSONDecodeError):
        return None
    return config["token"]


def serve(endpoint: Path = ENDPOINT) -> None:
    if not hasattr(os, "O_NOFOLLOW"):
        raise ValueError("the host cannot safely publish the preview endpoint")
    with Service() as server:
        _ensure_endpoint_parent(endpoint)
        temporary = endpoint.with_name(endpoint.name + "." + secrets.token_hex(8))
        fd = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
        try:
            with os.fdopen(fd, "w") as handle:
                fd = -1
                json.dump({"port": server.server_port, "token": server.token}, handle)
                handle.flush()
                os.fsync(handle.fileno())
            os.replace(temporary, endpoint)
        finally:
            if fd >= 0:
                os.close(fd)
            try:
                temporary.unlink()
            except FileNotFoundError:
                pass

        def stop_when_helper_exits() -> None:
            sys.stdin.buffer.read(1)
            server.shutdown()

        threading.Thread(target=stop_when_helper_exits, daemon=True).start()
        try:
            server.serve_forever()
        finally:
            if _endpoint_token(endpoint) == server.token:
                try:
                    endpoint.unlink()
                except FileNotFoundError:
                    pass


if __name__ == "__main__":
    serve()
