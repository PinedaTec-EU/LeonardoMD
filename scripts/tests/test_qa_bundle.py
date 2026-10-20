import importlib.util
import json
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
import unittest
from unittest.mock import patch

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

    def test_package_report_binds_version_and_exact_artifact_bytes(self):
        root = Path(self.directory.name)
        (root / 'deploy').mkdir()
        (root / 'version.nfo').write_text('0.1.3\n')
        content = json.dumps({'schema_version': 1, 'repository': 'PinedaTec-EU/LeonardoMD',
                              'version': '0.1.3', 'changes': []}).encode()
        (root / 'deploy/release-changes.json').write_bytes(content)
        resources = self.bundle / 'Contents/Resources'
        resources.mkdir()
        packaged = resources / 'ReleaseChanges.json'
        packaged.write_bytes(content)
        metadata = {'CFBundleExecutable': 'LeonardoMD', 'CFBundleIdentifier': 'eu.pinedatec.LeonardoMD',
                    'CFBundleShortVersionString': '0.1.3', 'CFBundleVersion': '3'}
        with patch.object(qa_bundle, 'inspect_bundle', return_value=(metadata, 'system dependencies')):
            report = qa_bundle.release_changes_report(self.bundle, root, 'a' * 40)
            self.assertTrue(report['changes_bytes_identical'])
            self.assertFalse(report['fresh_process_launched'])
            packaged.write_bytes(content + b'\n')
            with self.assertRaisesRegex(ValueError, 'canonical source'):
                qa_bundle.release_changes_report(self.bundle, root, 'a' * 40)
            packaged.write_bytes(content)
            metadata['CFBundleShortVersionString'] = '0.1.4'
            with self.assertRaisesRegex(ValueError, 'canonical source'):
                qa_bundle.release_changes_report(self.bundle, root, 'a' * 40)


if __name__ == '__main__':
    unittest.main()
