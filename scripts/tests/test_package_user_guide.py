import json
import re
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
import zipfile

ROOT = Path(__file__).resolve().parents[2]


class PackageUserGuideTests(unittest.TestCase):
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
                for diagram in (output / 'guide/illustrations').glob(language + '-*.svg'):
                    self.assertEqual(diagram.read_bytes(), (ROOT / 'doc/guide/illustrations' / diagram.name).read_bytes())
                web_source = (output / web_name).read_text()
                body = (ROOT / 'doc/guide' / language / 'body.md').read_text()
                # Copyable MDLF source and its package-path vocabulary must
                # survive adapting the web edition's illustration links.
                for sample in re.findall(r'^```text\n(.*?)^```$', body, re.M | re.S):
                    self.assertIn(sample, web_source)
                self.assertIn('`assets/`', web_source)
                name = f'Guide-v4-{language}.mdlz'
                self.assertEqual((output / name).read_bytes(), (ROOT / 'Sources/LeonardoApp/Resources' / name).read_bytes())
                with zipfile.ZipFile(output / name) as archive:
                    self.assertEqual(len(archive.namelist()), 12)
                    source = archive.read('guide.mdlf').decode('utf-8')
                    metadata = json.loads(source.split('---\n')[1])
                    self.assertEqual(metadata['formatVersion'], 1)
                    self.assertEqual(metadata['document']['revision'], 4)
                    self.assertIn('assets/cover.png', source)
                    self.assertTrue(archive.read('assets/cover.png').startswith(b'\x89PNG'))
                    self.assertIn('```mermaid\n', source)
                    self.assertIn('```vega-lite\n', source)
                    self.assertIn('$$\\bar{x}', source)
                    self.assertEqual(metadata['document']['kind'], 'form')
                    self.assertEqual(set(metadata['fields']), set(metadata['values']))
                    self.assertFalse(any(name.endswith('.json') for name in archive.namelist()))
                    references = set(re.findall(r'assets/[A-Za-z0-9_-]+\.(?:png|svg)', source))
                    self.assertEqual(references, set(archive.namelist()) - {'guide.mdlf'})
                    for asset in archive.namelist():
                        if asset.startswith('assets/') and asset.endswith('.svg'):
                            self.assertIn(asset, source)
                            self.assertIn(b'<svg ', archive.read(asset))
            self.assertEqual(unrelated.read_bytes(), b'preserve this file')
            self.assertEqual((output / 'other.md').read_text(), 'Keep this documentation')
