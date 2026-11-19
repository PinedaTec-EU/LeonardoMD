from pathlib import Path
import os
import subprocess
import sys
import tempfile
import unittest


SCRIPT = Path(__file__).resolve().parents[1] / "run-swift-test-with-timeout.py"


class SwiftTestTimeoutTests(unittest.TestCase):
    def run_fake_swift(self, directory, body):
        fake = directory / "swift"
        fake.write_text("#!/bin/sh\n" + body, encoding="utf-8")
        fake.chmod(0o700)
        env = dict(os.environ, PATH=f"{directory}{os.pathsep}{os.environ['PATH']}")
        return subprocess.run(
            [sys.executable, str(SCRIPT), "--seconds", "1",
             "--diagnostics", str(directory / "diagnostics")],
            env=env, capture_output=True, text=True, timeout=15,
        )

    def test_preserves_normal_failure_and_output(self):
        with tempfile.TemporaryDirectory() as tmp:
            directory = Path(tmp)
            result = self.run_fake_swift(directory, 'echo "$*"; exit 7\n')
            self.assertEqual(result.returncode, 7)
            self.assertEqual(result.stdout.strip(), "test --verbose")
            self.assertFalse((directory / "diagnostics").exists())

    def test_timeout_captures_group_and_reaps_child_holding_output_open(self):
        with tempfile.TemporaryDirectory() as tmp:
            directory = Path(tmp)
            result = self.run_fake_swift(
                directory, "echo 'last test output'; sleep 60 & wait\n",
            )
            self.assertEqual(result.returncode, 124, result.stderr)
            self.assertIn("last test output", result.stdout)
            self.assertIn("::error::Swift test exceeded", result.stdout)
            snapshot = (directory / "diagnostics" / "timeout-processes.txt").read_text()
            self.assertIn("PID PPID PGID ELAPSED STAT COMMAND", snapshot)
            self.assertIn("sleep", snapshot)
            self.assertNotIn(str(directory), snapshot)
