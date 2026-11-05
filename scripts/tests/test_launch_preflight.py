"""Exercise the real launcher: a broken final artifact must never reach open."""
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
import os
import plistlib

SCRIPTS = Path(__file__).parents[1]


class LaunchPreflightTests(unittest.TestCase):
    def test_valid_qa_copy_is_the_artifact_opened(self):
        with tempfile.TemporaryDirectory(prefix='launch success ') as directory:
            root = Path(directory)
            scripts = root / 'scripts'
            scripts.mkdir()
            for name in ('qa-bundle.py', 'bundle-dependencies.py'):
                shutil.copy2(SCRIPTS / name, scripts / name)
            shutil.copy2(SCRIPTS.parent / 'launch.sh', root / 'launch.sh')
            build = scripts / 'build-app.sh'
            build.write_text('#!/bin/bash\nexit 0\n')
            build.chmod(0o755)
            bundle = root / 'output/LeonardoMD.app'
            executable = bundle / 'Contents/MacOS/LeonardoMD'
            executable.parent.mkdir(parents=True)
            shutil.copyfile('/usr/bin/true', executable)
            executable.chmod(0o755)
            (bundle / 'Contents/Info.plist').write_bytes(plistlib.dumps({
                'CFBundleExecutable': 'LeonardoMD', 'CFBundleIdentifier': 'eu.pinedatec.test',
                'CFBundlePackageType': 'APPL'}))
            subprocess.run(['/usr/bin/codesign', '--force', '--sign', '-', str(bundle)],
                           check=True, capture_output=True)
            fake_bin = root / 'bin'
            fake_bin.mkdir()
            marker = root / 'opened'
            opener = fake_bin / 'open'
            opener.write_text('#!/bin/bash\nprintf "%s" "$2" > "$LAUNCH_MARKER"\n')
            opener.chmod(0o755)
            environment = dict(os.environ, PATH=str(fake_bin) + ':' + os.environ['PATH'], LAUNCH_MARKER=str(marker))
            environment.pop('LEONARDO_QA_SIGN_IDENTITY', None)
            result = subprocess.run(['/bin/bash', str(root / 'launch.sh'), '--qa'],
                                    capture_output=True, text=True, env=environment)
            self.assertEqual(result.returncode, 0, result.stderr)
            selected = Path(marker.read_text())
            self.addCleanup(shutil.rmtree, selected.parent)
            self.assertEqual(selected.name, 'LeonardoMDQA.app')
            self.assertNotEqual(selected, bundle)
            self.assertTrue((selected / 'Contents/MacOS/LeonardoMD').is_file())

    def test_invalid_final_bundle_stops_launch(self):
        with tempfile.TemporaryDirectory(prefix='launch preflight ') as directory:
            root = Path(directory)
            scripts = root / 'scripts'
            scripts.mkdir()
            for name in ('qa-bundle.py', 'bundle-dependencies.py'):
                shutil.copy2(SCRIPTS / name, scripts / name)
            shutil.copy2(SCRIPTS.parent / 'launch.sh', root / 'launch.sh')
            # Successful packaging command does not imply a usable final artifact.
            build = scripts / 'build-app.sh'
            build.write_text('#!/bin/bash\nexit 0\n')
            build.chmod(0o755)
            fake_bin = root / 'bin'
            fake_bin.mkdir()
            marker = root / 'opened'
            opener = fake_bin / 'open'
            opener.write_text('#!/bin/bash\ntouch "$LAUNCH_MARKER"\n')
            opener.chmod(0o755)
            environment = dict(os.environ, PATH=str(fake_bin) + ':' + os.environ['PATH'], LAUNCH_MARKER=str(marker))
            result = subprocess.run(['/bin/bash', str(root / 'launch.sh')], capture_output=True, text=True, env=environment)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('QA bundle rejected', result.stderr)
            self.assertFalse(marker.exists(), 'open must not run after final preflight rejects the app')


if __name__ == '__main__':
    unittest.main()
