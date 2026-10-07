import base64
import importlib.util
import plistlib
import tempfile
import unittest
import subprocess
import sys
import os
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

    def test_beta_metadata_through_script_preserves_unrelated_fields(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "Info.plist"
            original = (ROOT / "scripts/Info.plist").read_bytes()
            path.write_bytes(original)
            environment = {k: v for k, v in os.environ.items()
                           if not k.startswith(("LEONARDO_", "SPARKLE_"))}
            environment.update(LEONARDO_CHANNEL="beta", LEONARDO_VERSION="0.1.1-beta.1",
                               LEONARDO_BUILD="2")
            subprocess.run([sys.executable, str(ROOT / "scripts/configure-update-bundle.py"),
                            str(path)], env=environment, check=True)
            metadata = plistlib.loads(path.read_bytes())
            self.assertEqual(metadata["CFBundleShortVersionString"], "0.1.1-beta.1")
            self.assertEqual(metadata["LeonardoUpdateChannel"], "beta")
            self.assertIn("/beta/appcast.xml", metadata["SUFeedURL"])
            self.assertEqual(metadata["UTImportedTypeDeclarations"],
                             plistlib.loads(original)["UTImportedTypeDeclarations"])
            for version, channel, feed in (("0.1.1-beta.1", "stable", "https://example.com/feed"),
                                           ("0.1.1", "beta", "https://example.com/feed"),
                                           ("0.1.1-beta.1", "beta", "http://example.com/feed")):
                path.write_bytes(original)
                environment.update(LEONARDO_VERSION=version, LEONARDO_CHANNEL=channel,
                                   LEONARDO_FEED_URL=feed)
                result = subprocess.run([sys.executable, str(ROOT / "scripts/configure-update-bundle.py"),
                                         str(path)], env=environment, capture_output=True)
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(path.read_bytes(), original)

    def test_beta_appcast_cannot_enter_stable_channel(self):
        verify = load("verify-release-appcast").verify
        signature = base64.b64encode(bytes(64)).decode()
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "appcast.xml"
            path.write_text(f'<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel><item><sparkle:channel>beta</sparkle:channel><sparkle:version>2</sparkle:version><enclosure url="https://github.com/PinedaTec-EU/LeonardoMD/releases/download/v0.1.1-beta.1/LeonardoMD.zip" length="100" sparkle:edSignature="{signature}"/></item></channel></rss>')
            verify(path, "beta")
            with self.assertRaises(ValueError):
                verify(path, "stable")
            path.write_text(path.read_text().replace('<sparkle:channel>beta</sparkle:channel>', ''))
            with self.assertRaises(ValueError):
                verify(path, "stable")

    def test_channel_mismatches_leave_bundle_untouched(self):
        configure = load("configure-update-bundle").configure
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "Info.plist"
            original = (ROOT / "scripts/Info.plist").read_bytes()
            for channel, version, url in (
                ("beta", "1.2.3-beta.1", "https://github.com/PinedaTec-EU/LeonardoMD/releases/latest/download/appcast.xml"),
                ("stable", "1.2.3", "https://raw.githubusercontent.com/PinedaTec-EU/LeonardoMD/update-feeds/beta/appcast.xml"),
            ):
                path.write_bytes(original)
                with self.assertRaises(ValueError):
                    configure(path, {"LEONARDO_CHANNEL": channel, "LEONARDO_VERSION": version,
                                     "LEONARDO_FEED_URL": url})
                self.assertEqual(path.read_bytes(), original)

    def test_explicit_stable_channel_is_rejected(self):
        verify = load("verify-release-appcast").verify
        signature = base64.b64encode(bytes(64)).decode()
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "appcast.xml"
            path.write_text(f'<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel><item><sparkle:channel>stable</sparkle:channel><sparkle:version>2</sparkle:version><enclosure url="https://github.com/PinedaTec-EU/LeonardoMD/releases/download/v1.2.3/update.zip" length="100" sparkle:edSignature="{signature}"/></item></channel></rss>')
            with self.assertRaises(ValueError):
                verify(path)

    def test_appcast_generation_on_system_bash_handles_both_channels(self):
        with tempfile.TemporaryDirectory() as directory:
            tool = Path(directory) / "generate_appcast"
            tool.write_text('#!/bin/bash\nprintf "%s\\n" "$@"\n')
            tool.chmod(0o755)
            script = str(ROOT / "scripts/generate-release-appcast.sh")
            for channel, version in (("stable", "1.2.3"), ("beta", "1.2.3-beta.1")):
                result = subprocess.run(['/bin/bash', script, str(tool), directory, channel,
                                         version, 'fixture-account'], check=True,
                                        capture_output=True, text=True)
                arguments = result.stdout.splitlines()
                self.assertEqual(arguments[-1], directory)
                self.assertIn('fixture-account', arguments)
                self.assertIn('https://github.com/PinedaTec-EU/LeonardoMD/releases/download/v' + version + '/', arguments)
                self.assertEqual('--channel' in arguments, channel == 'beta')
                if channel == 'beta':
                    self.assertEqual(arguments[arguments.index('--channel') + 1], 'beta')
            invalid = subprocess.run(['/bin/bash', script, str(tool), directory, 'nightly',
                                      '1.2.3', 'fixture-account'], capture_output=True)
            self.assertNotEqual(invalid.returncode, 0)
            self.assertEqual(invalid.stdout, b'')

    def test_stable_release_cannot_skip_notarization(self):
        environment = {k: v for k, v in os.environ.items()
                       if not k.startswith(("LEONARDO_", "SPARKLE_", "NOTARY_"))}
        environment.update(LEONARDO_VERSION="1.2.3", LEONARDO_BUILD="4", LEONARDO_NOTARIZE="0",
                           SPARKLE_PUBLIC_KEY=base64.b64encode(bytes(32)).decode(),
                           DEVELOPER_ID_APPLICATION="fixture", RELEASE_NOTES_FILE=str(ROOT / "README.md"))
        result = subprocess.run(['/bin/bash', str(ROOT / "scripts/prepare-release.sh")],
                                env=environment, capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Only beta candidates can skip notarization', result.stderr)
        self.assertNotIn('Build complete', result.stdout)

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
