from __future__ import annotations

import http.client
import json
import shutil
import sys
import tempfile
import threading
import unittest
from pathlib import Path
from urllib.parse import quote
from zipfile import ZipFile

REPO = Path(__file__).resolve().parents[3]
PLUGIN = REPO / "plugins/leonardo-format"
sys.path.insert(0, str(PLUGIN / "skills/leonardo-format/scripts"))

from mdlz import ArchiveError
from preview import PreviewServer, RENDERER

EXAMPLES = REPO / "doc/format/examples"
GUIDE = next((REPO / "Sources/LeonardoApp/Resources").glob("Guide-v*-es.mdlz"))


class PreviewTests(unittest.TestCase):
    def start(self, source: Path) -> PreviewServer:
        server = PreviewServer(source.resolve())
        worker = threading.Thread(target=server.serve_forever, kwargs={"poll_interval": 0.02})
        worker.start()
        self.addCleanup(server.server_close)
        self.addCleanup(worker.join)
        self.addCleanup(server.shutdown)
        return server

    def get(self, server: PreviewServer, path: str, **headers: str):
        connection = http.client.HTTPConnection("127.0.0.1", server.server_port, timeout=3)
        try:
            connection.request("GET", path, headers=headers)
            response = connection.getresponse()
            return response.status, dict(response.getheaders()), response.read()
        finally:
            connection.close()

    def test_renderer_is_the_canonical_offline_bundle(self):
        root = REPO / "Sources/LeonardoRender/Resources"
        files = {
            path.relative_to(root).as_posix(): path for path in root.rglob("*")
            if path.is_file() and not path.name.startswith(".")
        }
        with ZipFile(RENDERER) as archive:
            self.assertEqual(set(archive.namelist()), set(files))
            for name, source in files.items():
                self.assertEqual(archive.read(name), source.read_bytes(), name)
        manifest = json.loads((REPO / ".agents/plugins/marketplace.json").read_text())
        self.assertEqual((REPO / manifest["plugins"][0]["source"]["path"]).resolve(), PLUGIN)

    def test_all_extensions_render_without_writing_the_source(self):
        fixtures = (
            (EXAMPLES / "invoice/invoice.mdlf", "FACTURA"),
            (EXAMPLES / "form-showcase/service-request.mdlr", "Ada Lovelace"),
            (GUIDE, "Tu gu\\u00eda de Leonardo"),
        )
        for source, marker in fixtures:
            with self.subTest(source=source.suffix):
                before = source.read_bytes()
                server = self.start(source)
                status, headers, page = self.get(server, server.page_path)
                self.assertEqual(status, 200)
                self.assertIn(marker.encode(), page)
                self.assertIn(b'"allowsFormFilling": false', page)
                self.assertIn("default-src 'none'", headers["Content-Security-Policy"])
                self.assertEqual(headers["Cache-Control"], "no-store")
                self.assertEqual(source.read_bytes(), before)
                self.assertEqual(self.get(server, server.prefix + "renderer/renderer-runtime.js")[0], 200)
                if source == GUIDE:
                    name = next(iter(server.images))
                    self.assertEqual(self.get(server, server.prefix + "images/" + quote(name))[0], 200)

    def test_local_asset_routes_confine_requests(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            folder = root / "invoice"
            shutil.copytree(EXAMPLES / "invoice", folder)
            (root / "outside.svg").write_text("<svg/>")
            (folder / "linked.svg").symlink_to(root / "outside.svg")
            source = folder / "invoice.mdlf"
            server = self.start(source)
            images = server.prefix + "images/"
            status, headers, _ = self.get(server, images + "assets/letterhead.svg")
            self.assertEqual(status, 200)
            self.assertEqual(headers["Content-Type"], "image/svg+xml")
            self.assertIn("sandbox", headers["Content-Security-Policy"])
            for path in ("/", "/wrong/preview", images + "invoice.mdlf", images + "linked.svg",
                         images + "%2e%2e/outside.svg", images + "..%5coutside.svg"):
                self.assertEqual(self.get(server, path)[0], 404, path)
            self.assertEqual(self.get(server, server.page_path, Host="example.org")[0], 404)

    def test_rejects_invalid_version_and_package_traversal_before_listening(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            document = root / "bad.mdlf"
            document.write_text('---\n{"format":"mdlf","formatVersion":99}\n---\n')
            with self.assertRaisesRegex(ArchiveError, "unsupported Leonardo formatVersion"):
                PreviewServer(document)
            package = root / "bad.mdlz"
            with ZipFile(package, "w") as archive:
                archive.write(document, "bad.mdlf")
                archive.writestr("assets/../escape.svg", "<svg/>")
            with self.assertRaises(ArchiveError):
                PreviewServer(package)
