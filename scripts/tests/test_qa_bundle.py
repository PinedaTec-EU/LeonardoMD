import importlib.util
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
import unittest

SPEC = importlib.util.spec_from_file_location('qa_bundle', Path(__file__).parents[1] / 'qa-bundle.py')
qa_bundle = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(qa_bundle)


class QABundleTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.bundle = Path(self.directory.name) / 'QA.app'
        (self.bundle / 'Contents/MacOS').mkdir(parents=True)

    def write_metadata(self, executable):
        (self.bundle / 'Contents/Info.plist').write_bytes(plistlib.dumps({
            'CFBundleExecutable': executable, 'CFBundlePackageType': 'APPL',
        }))

    def test_original_test_runner_packaging_is_rejected(self):
        self.write_metadata('RecentsQA')
        with self.assertRaisesRegex(ValueError, 'real LeonardoMD'):
            qa_bundle.prepare_bundle(self.bundle)

    def test_renaming_xctest_does_not_bypass_dependency_check(self):
        runner = subprocess.check_output(['xcrun', '--find', 'xctest'], text=True).strip()
        shutil.copy2(runner, self.bundle / 'Contents/MacOS/LeonardoMD')
        self.write_metadata('LeonardoMD')
        with self.assertRaisesRegex(ValueError, 'links XCTest'):
            qa_bundle.prepare_bundle(self.bundle)

    def test_missing_executable_is_rejected(self):
        self.write_metadata('LeonardoMD')
        with self.assertRaises(subprocess.CalledProcessError):
            qa_bundle.verify_bundle(self.bundle)


if __name__ == '__main__':
    unittest.main()
