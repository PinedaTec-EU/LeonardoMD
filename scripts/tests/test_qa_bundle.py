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

    def test_signed_qa_copies_share_identity_but_keep_separate_paths(self):
        self.write_metadata('LeonardoMD')
        info = self.bundle / 'Contents/Info.plist'
        original = info.read_bytes()
        with patch.object(qa_bundle, 'verify_bundle', side_effect=lambda bundle:
                          plistlib.loads((bundle / 'Contents/Info.plist').read_bytes())), \
                patch.object(qa_bundle.bundle_dependencies, 'sign_bundle') as sign:
            first = qa_bundle.prepare_bundle(self.bundle, 'Developer ID')
            self.addCleanup(shutil.rmtree, first.parent)
            second = qa_bundle.prepare_bundle(self.bundle, 'Developer ID')
            self.addCleanup(shutil.rmtree, second.parent)
        self.assertNotEqual(first, second)
        for bundle in (first, second):
            metadata = plistlib.loads((bundle / 'Contents/Info.plist').read_bytes())
            self.assertEqual(metadata['CFBundleIdentifier'], 'eu.pinedatec.LeonardoMD.qa')
            self.assertEqual(metadata['CFBundleExecutable'], 'LeonardoMD')
        self.assertEqual(info.read_bytes(), original)
        self.assertEqual([call.args for call in sign.call_args_list],
                         [(first, 'Developer ID'), (second, 'Developer ID')])

    def test_auto_selection_requires_one_distinct_developer_id(self):
        developer = '  1) ' + 'A' * 40 + ' "Developer ID Application: Owner (TEAM)"\n'
        distribution = '  2) ' + 'B' * 40 + ' "Apple Distribution: Owner (TEAM)"\n'
        second_developer = developer.replace('A' * 40, 'C' * 40)
        with patch.object(subprocess, 'run') as run:
            for output, selected in (
                (distribution, None),
                (developer + distribution + developer, 'A' * 40),
                (developer + second_developer, None),
            ):
                with self.subTest(output=output):
                    run.return_value = subprocess.CompletedProcess([], 0, stdout=output)
                    self.assertEqual(qa_bundle.local_developer_id(), selected)

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

    def helper_fixture(self):
        helper = self.bundle / 'Contents/MacOS/LeonardoSyncHelper'
        helper.write_bytes(b'fixture executable')
        helper.chmod(0o755)
        definition = self.bundle / 'Contents/Library/LaunchAgents/eu.pinedatec.LeonardoMD.sync-helper.plist'
        definition.parent.mkdir(parents=True)
        source = Path(__file__).parents[1] / definition.name
        shutil.copy2(source, definition)
        return helper, definition

    def test_packaged_helper_contract_is_verified_without_registration(self):
        helper, definition = self.helper_fixture()
        with patch.object(subprocess, 'check_output', return_value='system libraries'), \
                patch.object(qa_bundle.bundle_dependencies, 'signing_identifier', return_value=qa_bundle.bundle_dependencies.SYNC_HELPER_IDENTIFIER), \
                patch.object(subprocess, 'run') as run:
            qa_bundle.inspect_sync_helper(self.bundle)
            run.assert_called_once_with(['/usr/bin/codesign', '--verify', '--strict', str(helper)], check=True)
            metadata = plistlib.loads(definition.read_bytes())
            metadata['BundleProgram'] = '/tmp/other-helper'
            definition.write_bytes(plistlib.dumps(metadata))
            with self.assertRaisesRegex(ValueError, 'launch definition'):
                qa_bundle.inspect_sync_helper(self.bundle)

    def test_helper_cannot_be_an_xctest_runner(self):
        self.helper_fixture()
        with patch.object(subprocess, 'check_output', return_value='XCTest.framework/Versions/A/XCTest'):
            with self.assertRaisesRegex(ValueError, 'links XCTest'):
                qa_bundle.inspect_sync_helper(self.bundle)

    def test_developer_id_bundle_rejects_unresigned_framework(self):
        module = qa_bundle.bundle_dependencies
        framework = self.bundle / 'Contents/Frameworks/Sparkle.framework'
        helper = self.bundle / 'Contents/MacOS/LeonardoSyncHelper'
        framework.mkdir(parents=True)
        with patch.object(module.subprocess, 'run'), \
                patch.object(module, 'signing_components', return_value=[helper, framework]):
            with patch.object(module, 'signing_team', side_effect=['OWNER', 'OWNER', None]):
                with self.assertRaisesRegex(ValueError, 'signing team differs.*Sparkle'):
                    module.inspect_signing(self.bundle)
            with patch.object(module, 'signing_team', return_value='OWNER'):
                module.inspect_signing(self.bundle)

    def test_ad_hoc_bundle_does_not_claim_developer_id_team_validation(self):
        module = qa_bundle.bundle_dependencies
        with patch.object(module.subprocess, 'run'), patch.object(module, 'signing_team', return_value=None) as team:
            module.inspect_signing(self.bundle)
            team.assert_called_once_with(self.bundle)

    def test_helper_signing_identifier_must_match_service(self):
        self.helper_fixture()
        with patch.object(subprocess, 'check_output', return_value='system libraries'), \
                patch.object(subprocess, 'run'), \
                patch.object(qa_bundle.bundle_dependencies, 'signing_identifier', return_value='wrong.helper'):
            with self.assertRaisesRegex(ValueError, 'signing identifier'):
                qa_bundle.inspect_sync_helper(self.bundle)

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
