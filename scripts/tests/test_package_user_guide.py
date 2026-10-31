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
            subprocess.run([sys.executable, str(ROOT / 'scripts/package-user-guide.py'), '--output', str(output)], check=True)
            for language in ('en', 'es'):
                name = f'Guide-v4-{language}.mdlz'
                self.assertEqual((output / name).read_bytes(), (ROOT / 'Sources/LeonardoApp/Resources' / name).read_bytes())
                with zipfile.ZipFile(output / name) as archive:
                    self.assertEqual(len(archive.namelist()), 7)
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
