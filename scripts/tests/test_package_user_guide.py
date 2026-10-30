import json
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
                name = f'Guide-v1-{language}.mdlz'
                self.assertEqual((output / name).read_bytes(), (ROOT / 'Sources/LeonardoApp/Resources' / name).read_bytes())
                with zipfile.ZipFile(output / name) as archive:
                    self.assertEqual(len(archive.namelist()), 4)
                    source = archive.read('guide.mdlf').decode('utf-8')
                    metadata = json.loads(source.split('---\n')[1])
                    self.assertEqual(metadata['formatVersion'], 1)
                    self.assertEqual(metadata['document']['kind'], 'form')
                    self.assertEqual(set(metadata['fields']), set(metadata['values']))
                    for asset in archive.namelist():
                        if asset.startswith('assets/'):
                            self.assertIn(asset, source)
                            self.assertIn(b'<svg ', archive.read(asset))
            self.assertEqual(unrelated.read_bytes(), b'preserve this file')
