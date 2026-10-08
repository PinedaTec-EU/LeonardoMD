#!/usr/bin/env python3
"""Validate real app packaging and prepare disposable native QA copies."""
import argparse
import plistlib
from pathlib import Path
import shutil
import subprocess
import tempfile
import uuid


def verify_bundle(bundle):
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
    return metadata


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
    arguments = parser.parse_args()
    try:
        if arguments.verify_only:
            verify_bundle(arguments.source)
        else:
            print(prepare_bundle(arguments.source))
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        parser.exit(1, f'QA bundle rejected: {error}\n')


if __name__ == '__main__':
    main()
