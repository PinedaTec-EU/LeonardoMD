"""Exercise public metadata and atomic mixed-feed preparation through real CLIs."""
import base64
import os
from pathlib import Path
import plistlib
import subprocess
import sys
import tempfile
import unittest
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[2]
SPARKLE = '{http://www.andymatuschak.org/xml-namespaces/sparkle}'
LEONARDO = '{https://pinedatec.eu/xml-namespaces/leonardo}'


class UpdateChannelPackagingTests(unittest.TestCase):
    def test_both_distribution_channels_use_stable_trust_root_and_default_subscription(self):
        template = (ROOT / 'scripts/Info.plist').read_bytes()
        key = plistlib.loads(template)['LeonardoUpdatePublicKey']
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'Info.plist'
            for channel in ['stable', 'beta']:
                with self.subTest(channel=channel):
                    path.write_bytes(template)
                    result = self.configure(path, channel, key)
                    self.assertEqual(result.returncode, 0, result.stderr)
                    value = plistlib.loads(path.read_bytes())
                    self.assertEqual(value['SUPublicEDKey'], key)
                    self.assertEqual(value['LeonardoUpdateChannel'], channel)
                    self.assertEqual(value['SUFeedURL'], value['LeonardoStableFeedURL'])
                    self.assertNotEqual(value['LeonardoStableFeedURL'], value['LeonardoBetaFeedURL'])
                    self.assertFalse(value['SUEnableAutomaticChecks'])
                    self.assertFalse(value['SUAllowsAutomaticUpdates'])
                    self.assertFalse(value['SUAutomaticallyUpdate'])
                    self.assertEqual(value['CFBundleDocumentTypes'], plistlib.loads(template)['CFBundleDocumentTypes'])
                    path.write_bytes(template)
                    result = self.configure(path, channel, base64.b64encode(bytes(32)).decode())
                    self.assertNotEqual(result.returncode, 0)
                    self.assertIn('existing stable update public key', result.stderr)
                    self.assertEqual(path.read_bytes(), template)

    def test_compose_preserves_signed_entries_and_sorts_all_channels(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            stable, beta, output = root / 'stable.xml', root / 'beta.xml', root / 'combined.xml'
            stable.write_text(self.feed('stable', [410, 400]))
            beta.write_text(self.feed('beta', [415, 405]))
            before = stable.read_bytes(), beta.read_bytes()
            result = self.compose(stable, beta, output)
            self.assertEqual(result.returncode, 0, result.stderr)
            items = ET.parse(output).findall('./channel/item')
            self.assertEqual([i.find(SPARKLE + 'version').text for i in items], ['415', '410', '405', '400'])
            originals = ET.parse(stable).findall('./channel/item') + ET.parse(beta).findall('./channel/item')
            for item in items:
                original = next(i for i in originals if i.find(SPARKLE + 'version').text == item.find(SPARKLE + 'version').text)
                self.assertEqual(ET.tostring(item), ET.tostring(original))
                self.assertEqual(item.get(LEONARDO + 'channel') == 'beta', item.find(SPARKLE + 'channel') is not None)
            self.assertEqual((stable.read_bytes(), beta.read_bytes()), before)

    def test_rejected_feeds_leave_previous_publication_untouched(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            stable, beta, output = root / 'stable.xml', root / 'beta.xml', root / 'combined.xml'
            stable.write_text(self.feed('stable', [410]))
            cases = [self.feed('beta', [410]), self.feed('stable', [415]), '<rss><channel/></rss>', '<invalid',
                     self.feed('beta', [415]).replace('sparkle:edSignature=', 'invalidSignature='),
                     self.feed('beta', [415]).replace('leonardo:channel="beta"', '')]
            for rejected in cases:
                beta.write_text(rejected)
                output.write_bytes(b'previous feed')
                result = self.compose(stable, beta, output)
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(output.read_bytes(), b'previous feed')
            beta.write_text(self.feed('beta', [415]))
            original = stable.read_bytes()
            result = self.compose(stable, beta, stable)
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(stable.read_bytes(), original)
            result = self.compose(stable, root / 'absent.xml', output)
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(output.read_bytes(), b'previous feed')

    def test_encoded_duplicate_tags_and_noncanonical_paths_are_rejected_atomically(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            stable, beta, output = root / 'stable.xml', root / 'beta.xml', root / 'combined.xml'
            stable.write_text(self.feed('stable', [400]))
            for alias in ['%76%30.%31.%34%30%30', 'v0%2e1%2e400', 'v0.1.400/../v0.1.415']:
                beta.write_text(self.feed('beta', [415]).replace('/v0.1.415/', '/' + alias + '/')
                                .replace('<sparkle:shortVersionString>0.1.415</sparkle:shortVersionString>',
                                         '<sparkle:shortVersionString>0.1.400</sparkle:shortVersionString>'))
                before = stable.read_bytes(), beta.read_bytes()
                output.write_bytes(b'previous subscription')
                result = self.compose(stable, beta, output)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn('canonical, unescaped', result.stderr)
                self.assertEqual(output.read_bytes(), b'previous subscription')
                self.assertEqual((stable.read_bytes(), beta.read_bytes()), before)
            # A direct duplicate tag with a different build must also fail.
            beta.write_text(self.feed('beta', [415]).replace('/v0.1.415/', '/v0.1.400/')
                            .replace('>0.1.415<', '>0.1.400<'))
            result = self.compose(stable, beta, output)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('distinct increasing builds and tags', result.stderr)
            self.assertEqual(output.read_bytes(), b'previous subscription')

    def configure(self, path, channel, key):
        environment = {k: v for k, v in os.environ.items() if not k.startswith(('LEONARDO_', 'SPARKLE_'))}
        environment.update(LEONARDO_DISTRIBUTION='1', LEONARDO_CHANNEL=channel, SPARKLE_PUBLIC_KEY=key)
        return subprocess.run([sys.executable, str(ROOT / 'scripts/configure-update-bundle.py'), str(path)],
                              env=environment, capture_output=True, text=True)

    def compose(self, stable, beta, output):
        return subprocess.run([sys.executable, str(ROOT / 'scripts/compose-beta-appcast.py'),
                               '--stable', str(stable), '--beta', str(beta), '--output', str(output)],
                              capture_output=True, text=True)

    def feed(self, channel, builds):
        signature = base64.b64encode(bytes(64)).decode()
        marker = '<sparkle:channel>beta</sparkle:channel>' if channel == 'beta' else ''
        items = ''.join(f'<item leonardo:channel="{channel}">{marker}<sparkle:version>{b}</sparkle:version>'
                        f'<sparkle:shortVersionString>0.1.{b}</sparkle:shortVersionString>'
                        f'<description>Release {b}</description><enclosure '
                        f'url="https://github.com/PinedaTec-EU/LeonardoMD/releases/download/v0.1.{b}/LeonardoMD-{b}.zip" '
                        f'length="100" sparkle:edSignature="{signature}"/></item>' for b in builds)
        return '<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" xmlns:leonardo="https://pinedatec.eu/xml-namespaces/leonardo"><channel><title>LeonardoMD</title>' + items + '</channel></rss>'
