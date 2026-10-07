import base64
import importlib.util
import plistlib
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def load(name):
    spec = importlib.util.spec_from_file_location(name, ROOT / "scripts" / (name + ".py"))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class UpdateMetadataTests(unittest.TestCase):
    def test_release_metadata_preserves_document_types(self):
        configure = load("configure-update-bundle").configure
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "Info.plist"
            path.write_bytes((ROOT / "scripts/Info.plist").read_bytes())
            before = plistlib.loads(path.read_bytes())
            key = base64.b64encode(bytes(32)).decode()
            configure(path, {"LEONARDO_DISTRIBUTION": "1", "SPARKLE_PUBLIC_KEY": key,
                             "LEONARDO_VERSION": "1.2.3", "LEONARDO_BUILD": "42"})
            after = plistlib.loads(path.read_bytes())
            self.assertEqual(after["CFBundleDocumentTypes"], before["CFBundleDocumentTypes"])
            self.assertEqual(after["CFBundleVersion"], "42")
            self.assertEqual(after["SUPublicEDKey"], key)
            self.assertTrue(after["SUVerifyUpdateBeforeExtraction"])
            configure(path, {})
            self.assertNotIn("SUPublicEDKey", plistlib.loads(path.read_bytes()))

    def test_invalid_release_metadata_leaves_original_untouched(self):
        configure = load("configure-update-bundle").configure
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "Info.plist"
            original = (ROOT / "scripts/Info.plist").read_bytes()
            for environment in ({"LEONARDO_DISTRIBUTION": "1"}, {"SPARKLE_PUBLIC_KEY": "bad"},
                                {"LEONARDO_BUILD": "0"}, {"LEONARDO_VERSION": "1.0.0-beta"}):
                path.write_bytes(original)
                with self.assertRaises(ValueError):
                    configure(path, environment)
                self.assertEqual(path.read_bytes(), original)

    def test_unsigned_or_foreign_appcast_is_rejected(self):
        verify = load("verify-release-appcast").verify
        signature = base64.b64encode(bytes(64)).decode()
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "appcast.xml"
            def feed(url, sig):
                path.write_text(f'<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel><item><sparkle:version>42</sparkle:version><enclosure url="{url}" length="100" sparkle:edSignature="{sig}"/></item></channel></rss>')
            url = "https://github.com/PinedaTec-EU/LeonardoMD/releases/download/v1.0.0/app.zip"
            feed(url, signature)
            verify(path)
            for bad_url, bad_signature in ((url, ""), ("https://example.com/app.zip", signature)):
                feed(bad_url, bad_signature)
                with self.assertRaises(ValueError):
                    verify(path)


if __name__ == "__main__":
    unittest.main()
