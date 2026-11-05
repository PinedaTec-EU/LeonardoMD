"""Exercise the real launcher: a broken final artifact must never reach open."""
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
import os

SCRIPTS = Path(__file__).parents[1]


class LaunchPreflightTests(unittest.TestCase):
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
            result = subprocess.run(['bash', str(root / 'launch.sh')], capture_output=True, text=True, env=environment)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('QA bundle rejected', result.stderr)
            self.assertFalse(marker.exists(), 'open must not run after final preflight rejects the app')


if __name__ == '__main__':
    unittest.main()
