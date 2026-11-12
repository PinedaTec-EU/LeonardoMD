"""Packaging copies the central artifact exactly and rejects a mismatched package."""
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / 'package-release-changes.py'


class PackageReleaseChangesTests(unittest.TestCase):
    def test_real_entrypoint_preserves_bytes_and_rejects_wrong_version_or_repository(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source, version, destination = root / 'changes.json', root / 'version.nfo', root / 'bundle/ReleaseChanges.json'
            artifact = {'schema_version': 1, 'repository': 'PinedaTec-EU/LeonardoMD', 'version': '0.1.2',
                        'changes': [{'pr': 42, 'summary': 'Document metadata is preserved.'}]}
            source.write_text(json.dumps(artifact, indent=2) + '\n')
            version.write_text('0.1.2\n')
            result = subprocess.run([sys.executable, str(SCRIPT), str(source), str(version), str(destination)], capture_output=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(source.read_bytes(), destination.read_bytes())
            original = destination.read_bytes()
            for key, value in [('version', '0.1.3'), ('repository', 'other/repo')]:
                invalid = dict(artifact, **{key: value})
                source.write_text(json.dumps(invalid))
                result = subprocess.run([sys.executable, str(SCRIPT), str(source), str(version), str(destination)], capture_output=True)
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(original, destination.read_bytes())
