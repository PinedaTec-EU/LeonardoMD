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
from unittest.mock import patch
from zipfile import ZipFile

REPO = Path(__file__).resolve().parents[3]
PLUGIN = REPO / "plugins/leonardo-format"
sys.path.insert(0, str(PLUGIN / "skills/leonardo-format/scripts"))

from mdlz import ArchiveError
from preview import RENDERER
from preview_service import Preview, Service, _is_managed_source, _managed_roots

EXAMPLES = REPO / "doc/format/examples"
GUIDE = next((REPO / "Sources/LeonardoApp/Resources").glob("Guide-v*-es.mdlz"))


class PreviewTests(unittest.TestCase):
    def start(self, source: Path):
        server = Service()
        preview = Preview(source.absolute())
        server.add_preview(preview)
        worker = threading.Thread(target=server.serve_forever, kwargs={"poll_interval": 0.02})
        worker.start()
        self.addCleanup(server.server_close)
        self.addCleanup(worker.join)
        self.addCleanup(server.shutdown)
        return server, preview

    def get(self, server: Service, path: str, **headers: str):
        connection = http.client.HTTPConnection("127.0.0.1", server.server_port, timeout=3)
        try:
            connection.request("GET", path, headers=headers)
            response = connection.getresponse()
            return response.status, dict(response.getheaders()), response.read()
        finally:
            connection.close()

    def register(self, server: Service, source: Path):
        connection = http.client.HTTPConnection("127.0.0.1", server.server_port, timeout=3)
        try:
            data = json.dumps({"document": str(source.absolute())}).encode()
            connection.request(
                "POST", "/register", body=data,
                headers={
                    "Host": f"127.0.0.1:{server.server_port}",
                    "Authorization": "Bearer " + server.token,
                    "Content-Type": "application/json",
                },
            )
            response = connection.getresponse()
            return response.status, response.read()
        finally:
            connection.close()

    def test_renderer_is_the_canonical_offline_bundle(self):
        root = REPO / "Sources/LeonardoRender/Resources"
        files = {
            path.relative_to(root).as_posix(): path for path in root.rglob("*")
            if path.is_file() and not path.name.startswith(".")
        }
        core = REPO / "Sources/LeonardoCore/Resources"
        files.update({
            "marked.umd.js": core / "marked.umd.js",
            "licenses/marked-15.0.7.txt": core / "marked-15.0.7.txt",
        })
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
            (GUIDE, "Tu guía de Leonardo"),
        )
        for source, marker in fixtures:
            with self.subTest(source=source.suffix):
                before = source.read_bytes()
                server, preview = self.start(source)
                status, headers, page = self.get(server, preview.prefix + "preview")
                self.assertEqual(status, 200)
                self.assertIn(marker.encode(), page)
                self.assertIn(b'"allowsFormFilling": false', page)
                self.assertIn(b'"allowsLeonardoFormat": true', page)
                self.assertIn("default-src 'none'", headers["Content-Security-Policy"])
                self.assertEqual(headers["Cache-Control"], "no-store")
                self.assertEqual(source.read_bytes(), before)
                self.assertEqual(self.get(server, preview.prefix + "renderer/renderer-runtime.js")[0], 200)
                if preview.images:
                    name = next(iter(preview.images))
                    self.assertEqual(self.get(server, preview.prefix + "images/" + quote(name))[0], 200)

    def test_v2_uses_the_versioned_schema_and_read_only_payload(self):
        source = EXAMPLES / "guided-signing.mdlf"
        server, preview = self.start(source)
        status, _, page = self.get(server, preview.prefix + "preview")
        self.assertEqual(status, 200)
        self.assertIn(b'"formatVersion": 2', page)
        self.assertIn(b'"allowsEditing": false', page)
        self.assertIn(b'"allowsFormFilling": false', page)

    def test_registration_and_expiry(self):
        source = EXAMPLES / "invoice/invoice.mdlf"
        server, preview = self.start(source)
        status, _ = self.register(server, source)
        self.assertEqual(status, 201)
        registered = next(item for item in server.previews.values() if item is not preview)
        registered.deadline = 0
        self.assertEqual(self.get(server, registered.prefix + "preview")[0], 404)
        self.assertEqual(self.get(server, "/health")[0], 200)

    def test_local_asset_routes_confine_requests(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            folder = root / "invoice"
            shutil.copytree(EXAMPLES / "invoice", folder)
            (root / "outside.svg").write_text("<svg/>")
            (folder / "linked.svg").symlink_to(root / "outside.svg")
            (folder / "unrelated.svg").write_text("<svg/>")
            source = folder / "invoice.mdlf"
            source.write_text(source.read_text() + "\n![Link](linked.svg)\n")
            server, preview = self.start(source)
            images = preview.prefix + "images/"
            status, headers, _ = self.get(server, images + "assets/letterhead.svg")
            self.assertEqual(status, 200)
            self.assertEqual(headers["Content-Type"], "image/svg+xml")
            self.assertIn("sandbox", headers["Content-Security-Policy"])
            for path in ("/", "/wrong/preview", images + "invoice.mdlf", images + "linked.svg",
                         images + "unrelated.svg", images + "%2e%2e/outside.svg",
                         images + "..%5coutside.svg"):
                self.assertEqual(self.get(server, path)[0], 404, path)
            self.assertEqual(self.get(server, preview.prefix + "preview", Host="example.org")[0], 404)

    def test_rejects_invalid_version_and_package_traversal_before_registration(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            document = root / "bad.mdlf"
            document.write_text('---\n{"format":"mdlf","formatVersion":99}\n---\n')
            with self.assertRaisesRegex(ArchiveError, "unsupported Leonardo formatVersion"):
                Preview(document)
            package = root / "bad.mdlz"
            with ZipFile(package, "w") as archive:
                archive.write(document, "bad.mdlf")
                archive.writestr("assets/../escape.svg", "<svg/>")
            with self.assertRaises(ArchiveError):
                Preview(package)

    def test_rejects_managed_sync_content_even_when_the_path_is_local(self):
        with tempfile.TemporaryDirectory() as tmp:
            home = Path(tmp) / "home"
            managed = home / "Library/Application Support/LeonardoMD/DesktopPeers"
            managed.mkdir(parents=True)
            source = managed / "Downloads" / "invoice.mdlf"
            source.parent.mkdir()
            shutil.copyfile(EXAMPLES / "invoice/invoice.mdlf", source)
            roots = _managed_roots(home)
            self.assertTrue(_is_managed_source(source, roots))
            with patch("preview_service._managed_roots", return_value=roots):
                with self.assertRaisesRegex(ValueError, "managed Sync"):
                    Preview(source)


if __name__ == "__main__":
    unittest.main()
