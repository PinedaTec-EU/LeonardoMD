#!/usr/bin/env python3
"""Validate real app packaging and prepare disposable native QA copies."""
import argparse
import hashlib
import json
import os
import plistlib
from pathlib import Path
import shutil
import subprocess
import tempfile
import uuid


def inspect_bundle(bundle):
    with (bundle / 'Contents/Info.plist').open('rb') as stream:
        metadata = plistlib.load(stream)
    executable_name = metadata.get('CFBundleExecutable')
    if executable_name != 'LeonardoMD':
        raise ValueError('GUI QA requires the real LeonardoMD executable; run XCTest through swift test')
    executable = bundle / 'Contents/MacOS' / executable_name
    dependencies = subprocess.check_output(['/usr/bin/otool', '-L', str(executable)], text=True)
    if 'XCTest.framework/' in dependencies:
        raise ValueError('GUI executable links XCTest; use swift test instead of launching a test runner as an app')
    subprocess.run(['/usr/bin/codesign', '--verify', '--strict', str(bundle)], check=True)
    return metadata, dependencies


def verify_bundle(bundle):
    return inspect_bundle(bundle)[0]


def release_changes_report(bundle, source_root, checkout_sha):
    metadata, dependencies = inspect_bundle(bundle)
    source = (source_root / 'deploy/release-changes.json').read_bytes()
    packaged = (bundle / 'Contents/Resources/ReleaseChanges.json').read_bytes()
    version = (source_root / 'version.nfo').read_text(encoding='utf-8').strip()
    artifact = json.loads(source)
    if (source != packaged or artifact.get('schema_version') != 1
            or artifact.get('repository') != 'PinedaTec-EU/LeonardoMD'
            or artifact.get('version') != version or not isinstance(artifact.get('changes'), list)
            or metadata.get('CFBundleIdentifier') != 'eu.pinedatec.LeonardoMD'
            or metadata.get('CFBundleShortVersionString') != version
            or metadata.get('CFBundleVersion') != version.rsplit('.', 1)[-1]):
        raise ValueError('Packaged release changes and bundle identity must match the canonical source')
    return {
        'schema_version': 1, 'checkout_sha': checkout_sha,
        'bundle_identifier': metadata['CFBundleIdentifier'],
        'executable': metadata['CFBundleExecutable'], 'version': version,
        'dependencies': dependencies, 'xctest_dependency': False, 'codesign_verified': True,
        'changes_sha256': hashlib.sha256(packaged).hexdigest(), 'changes_bytes_identical': True,
        'change_count': len(artifact['changes']),
        'summary_count': sum('summary' in change for change in artifact['changes']),
        'fresh_process_launched': False,
    }


def prepare_bundle(source):
    metadata = verify_bundle(source)
    directory = Path(tempfile.mkdtemp(prefix='leonardo-native-qa-'))
    bundle = directory / 'LeonardoMDQA.app'
    try:
        subprocess.run(['/usr/bin/ditto', str(source), str(bundle)], check=True)
        metadata['CFBundleIdentifier'] = 'eu.pinedatec.LeonardoMD.qa.' + uuid.uuid4().hex
        metadata['CFBundleName'] = 'LeonardoMD QA'
        metadata['CFBundleDisplayName'] = 'LeonardoMD QA'
        with (bundle / 'Contents/Info.plist').open('wb') as stream:
            plistlib.dump(metadata, stream)
        subprocess.run(['/usr/bin/codesign', '--force', '--sign', '-', str(bundle)], check=True)
        verify_bundle(bundle)
        return bundle
    except BaseException:
        shutil.rmtree(directory)
        raise


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source', type=Path, help='Packaged LeonardoMD.app from scripts/build-app.sh')
    parser.add_argument('--verify-only', action='store_true')
    parser.add_argument('--report', type=Path, help='Write package inspection evidence; requires --verify-only')
    arguments = parser.parse_args()
    if arguments.report and not arguments.verify_only:
        parser.error('--report requires --verify-only')
    try:
        if arguments.report:
            root = Path(__file__).resolve().parents[1]
            head = subprocess.check_output(['git', '-C', str(root), 'rev-parse', 'HEAD'], text=True).strip()
            if os.environ.get('EVIDENCE_SHA', head) != head:
                raise ValueError('Evidence SHA does not match the checked-out source')
            report = release_changes_report(arguments.source, root, head)
            arguments.report.write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
            print(json.dumps(report, indent=2))
        elif arguments.verify_only:
            verify_bundle(arguments.source)
        else:
            print(prepare_bundle(arguments.source))
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        parser.exit(1, f'QA bundle rejected: {error}\n')


if __name__ == '__main__':
    main()
