import json
import hashlib
import re
from pathlib import Path
import subprocess
import struct
import sys
import tempfile
import unittest
import zipfile

ROOT = Path(__file__).resolve().parents[2]


def image_dimensions(data):
    if data.startswith(b'\x89PNG\r\n\x1a\n'):
        return struct.unpack('>II', data[16:24])
    if data.startswith(b'\xff\xd8'):
        position = 2
        frame_markers = {0xC0, 0xC1, 0xC2, 0xC3, 0xC5, 0xC6, 0xC7,
                         0xC9, 0xCA, 0xCB, 0xCD, 0xCE, 0xCF}
        while position < len(data):
            if data[position] != 0xFF:
                raise AssertionError('Invalid JPEG segment')
            while position < len(data) and data[position] == 0xFF:
                position += 1
            marker = data[position]
            position += 1
            if marker in {0xD9, 0xDA}:
                break
            if marker == 0x01 or 0xD0 <= marker <= 0xD7:
                continue
            size = int.from_bytes(data[position:position + 2], 'big')
            if marker in frame_markers:
                height, width = struct.unpack('>HH', data[position + 3:position + 7])
                return width, height
            position += size
    raise AssertionError('Unsupported or invalid guide image')


class PackageUserGuideTests(unittest.TestCase):
    def test_instructional_image_inventory_resolves_both_locales(self):
        inventory = (ROOT / 'doc/guide/screenshots.md').read_text()
        captures = re.findall(r'`(en/es|en)/assets/([^`]+\.(?:png|jpg))`', inventory)
        names = [(locale, name) for locale, name in captures]
        self.assertGreaterEqual(len(names), 7)
        for locale, name in names:
            languages = ('en', 'es') if locale == 'en/es' else ('en',)
            for language in languages:
                with self.subTest(language=language, image=name):
                    image = ROOT / 'doc/guide' / language / 'assets' / name
                    self.assertTrue(image.is_file(), f'Stale instructional inventory: {image}')
                    metadata = json.loads(image.with_suffix('.metadata.json').read_text())
                    self.assertEqual(metadata['image']['sha256'], hashlib.sha256(image.read_bytes()).hexdigest())
                    self.assertTrue(image.with_suffix('.context.json').is_file())

    def test_historical_sync_evidence_links_preserve_the_accepted_originals(self):
        directory = ROOT / 'doc/validation/sync-helper'
        source = (directory / 'README.md').read_text()
        links = re.findall(r'\]\((accepted-component-capture/[^)]+\.png)\)', source)
        self.assertEqual(len(links), 4)
        for link in links:
            image = directory / link
            self.assertTrue(image.is_file(), f'Broken historical capture link: {link}')
            metadata = json.loads(image.with_suffix('.metadata.json').read_text())
            context = json.loads(image.with_suffix('.context.json').read_text())
            self.assertEqual(metadata['image']['sha256'], hashlib.sha256(image.read_bytes()).hexdigest())
            self.assertEqual(context['source_sha'], '0c46b98e85092f5ef169fa6823935f04db200c2c')

    def test_generated_guides_match_bundled_artifacts_and_keep_unrelated_files(self):
        with tempfile.TemporaryDirectory() as temporary:
            output = Path(temporary)
            unrelated = output / 'unrelated.mdlz'
            unrelated.write_bytes(b'preserve this file')
            (output / 'other.md').write_text('Keep this documentation')
            subprocess.run([sys.executable, str(ROOT / 'scripts/package-user-guide.py'), '--output', str(output), '--web-output', str(output)], check=True)
            for language in ('en', 'es'):
                web_name = 'user-guide-es.md' if language == 'es' else 'user-guide.md'
                self.assertEqual((output / web_name).read_bytes(), (ROOT / 'doc' / web_name).read_bytes())
                web_source = (output / web_name).read_text()
                body = (ROOT / 'doc/guide' / language / 'body.md').read_text()
                # Copyable MDLF source and its package-path vocabulary must
                # survive adapting the web edition's illustration links.
                for sample in re.findall(r'^```text\n(.*?)^```$', body, re.M | re.S):
                    self.assertIn(sample, web_source)
                self.assertIn('`assets/`', web_source)
                artwork = ('journey', 'package', 'import', 'export') if language == 'en' else ('recorrido', 'paquete', 'importar', 'exportar')
                for illustration in artwork:
                    asset = ROOT / 'doc/guide' / language / 'assets' / (illustration + '.png')
                    width, height = struct.unpack('>II', asset.read_bytes()[16:24])
                    self.assertEqual((width, height), (1200, 400))
                    self.assertIn(f'guide/{language}/assets/{illustration}.png', web_source)
                practice_name = f'Practice-v1-{language}.mdlr'
                practice = (output / practice_name).read_bytes()
                self.assertEqual(practice, (ROOT / 'Sources/LeonardoApp/Resources' / practice_name).read_bytes())
                self.assertEqual(practice, (output / 'guide' / language / 'practice.mdlr').read_bytes())
                self.assertEqual(practice, (ROOT / 'doc/guide' / language / 'practice.mdlr').read_bytes())
                form = json.loads(practice.decode().split('---\n')[1])
                self.assertEqual(form['document']['kind'], 'form')
                self.assertEqual(set(form['fields']), set(form['values']))
                self.assertEqual(len(form['fields']), 3)
                self.assertIn(f'/doc/guide/{language}/practice.mdlr', web_source)
                guides = sorted(output.glob(f'Guide-v*-{language}.mdlz'))
                self.assertEqual(len(guides), 1, f'Expected one generated guide package for {language}')
                guide = guides[0]
                match = re.fullmatch(rf'Guide-v(\d+)-{language}\.mdlz', guide.name)
                self.assertIsNotNone(match, f'Unexpected guide package name: {guide.name}')
                revision = int(match.group(1))
                self.assertEqual(guide.read_bytes(), (ROOT / 'Sources/LeonardoApp/Resources' / guide.name).read_bytes())
                with zipfile.ZipFile(guide) as archive:
                    expected_images = 22
                    self.assertEqual(len(archive.namelist()), expected_images + 1)
                    # Conservative 16-bit RGBA source envelope catches image
                    # budget regressions before the native all-images check.
                    image_bytes = 0
                    for asset in archive.namelist():
                        if asset.endswith(('.png', '.jpg')):
                            content = archive.read(asset)
                            width, height = image_dimensions(content)
                            image_bytes += len(content) + width * height * 8
                    self.assertLessEqual(image_bytes, 128 * 1024 * 1024)
                    source = archive.read('guide.mdlf').decode('utf-8')
                    metadata = json.loads(source.split('---\n')[1])
                    self.assertEqual(metadata['formatVersion'], 1)
                    self.assertEqual(metadata['document']['revision'], revision)
                    maintenance = (ROOT / 'doc/guide/README.md').read_text()
                    self.assertIn(guide.name, maintenance)
                    self.assertIn(f"User Guides/v{metadata['document']['revision']}/", maintenance)

                    self.assertIn('assets/cover.png', source)
                    self.assertTrue(archive.read('assets/cover.png').startswith(b'\x89PNG'))
                    self.assertIn('```mermaid\n', source)
                    self.assertIn('```vega-lite\n', source)
                    self.assertIn('$$\\bar{x}', source)
                    self.assertEqual(metadata['document']['kind'], 'document')
                    self.assertNotIn('fields', metadata)
                    self.assertNotIn('values', metadata)
                    self.assertNotIn('{{field:practice', source)
                    self.assertFalse(any(name.endswith('.json') for name in archive.namelist()))
                    references = set(re.findall(r'assets/[A-Za-z0-9_-]+\.(?:png|jpg|svg)', source))
                    self.assertEqual(references, set(archive.namelist()) - {'guide.mdlf'})
                    for asset in archive.namelist():
                        if asset.startswith('assets/'):
                            self.assertIn(asset, source)
                            content = archive.read(asset)
                            if asset.endswith('.png'):
                                self.assertTrue(content.startswith(b'\x89PNG'))
                            else:
                                self.assertTrue(content.startswith(b'\xff\xd8'))
                import_name = f'AgentImport-v3-{language}.mdlz'
                self.assertIn(import_name, maintenance)
                self.assertIn('Agent Import Guides/v3/', maintenance)
                self.assertEqual((output / import_name).read_bytes(),
                                 (ROOT / 'Sources/LeonardoApp/Resources' / import_name).read_bytes())
                with zipfile.ZipFile(output / import_name) as archive:
                    source = archive.read('guide.mdlf').decode('utf-8')
                    header = json.loads(source.split('---\n')[1])
                    self.assertEqual(header['document']['kind'], 'document')
                    self.assertEqual(header['document']['revision'], 3)
                    self.assertEqual(len(archive.namelist()), 2)
                    chapter = body.split('<!-- agent-import:begin -->\n')[1].split('<!-- agent-import:end -->')[0]
                    self.assertTrue(source.endswith(chapter.replace('### ', '# ', 1).replace('\n#### ', '\n## ')))
                    self.assertIn('leonardo-format', source)
                    self.assertIn('.mdlf', source)
                    self.assertIn('.mdlz', source)
                    self.assertIn('```text', source)
                    for asset in archive.namelist():
                        if asset != 'guide.mdlf':
                            self.assertIn(asset, source)
                            self.assertTrue(archive.read(asset).startswith(b'\x89PNG'))
            self.assertEqual(unrelated.read_bytes(), b'preserve this file')
            self.assertEqual((output / 'other.md').read_text(), 'Keep this documentation')
