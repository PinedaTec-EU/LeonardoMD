"""Exercise the real metadata generator without compiling the app."""
import plistlib
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


class PackageVersionTests(unittest.TestCase):
    def run_generator(self, version, template=None):
        scratch = tempfile.TemporaryDirectory()
        self.addCleanup(scratch.cleanup)
        root = Path(scratch.name)
        (root / "version.nfo").write_text(version)
        metadata = {"CFBundleIdentifier": "test.example", "Other": ["untouched", 7]}
        if template:
            metadata.update(template)
        (root / "Info.plist").write_bytes(plistlib.dumps(metadata))
        output = root / "generated.plist"
        result = subprocess.run(
            [sys.executable, str(ROOT / "scripts/package-version.py"),
             str(root / "version.nfo"), str(root / "Info.plist"), str(output)],
            text=True, capture_output=True,
        )
        return result, output

    def test_canonical_version_and_unrelated_metadata(self):
        for version, build in [("0.1.56", "56"), ("0.1.57", "57"), ("0.2.57", "57")]:
            with self.subTest(version=version):
                result, output = self.run_generator(version + "\n")
                self.assertEqual(result.returncode, 0, result.stderr)
                metadata = plistlib.loads(output.read_bytes())
                self.assertEqual(metadata["CFBundleShortVersionString"], version)
                self.assertEqual(metadata["CFBundleVersion"], build)
                self.assertEqual(metadata["Other"], ["untouched", 7])
                self.assertEqual(metadata["CFBundleIdentifier"], "test.example")

    def test_invalid_version_does_not_write_output(self):
        for version in ["0.1", "0.1.56.1", "0.01.56", "0.1.0", "0.1.10000", "0.1.56\n0.1.57"]:
            with self.subTest(version=version):
                result, output = self.run_generator(version)
                self.assertNotEqual(result.returncode, 0)
                self.assertFalse(output.exists())

    def test_template_cannot_hide_a_second_version_source(self):
        result, output = self.run_generator("0.1.56", {"CFBundleVersion": "1"})
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(output.exists())


if __name__ == "__main__":
    unittest.main()
