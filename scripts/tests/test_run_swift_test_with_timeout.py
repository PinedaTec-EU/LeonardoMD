from pathlib import Path
import os
import runpy
from shlex import quote
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch


SCRIPT = Path(__file__).resolve().parents[1] / "run-swift-test-with-timeout.py"


class SwiftTestTimeoutTests(unittest.TestCase):
    def run_fake_swift(self, directory, body, *wrapper_arguments):
        fake = directory / "swift"
        fake.write_text("#!/bin/sh\n" + body, encoding="utf-8")
        fake.chmod(0o700)
        env = dict(os.environ, PATH=f"{directory}{os.pathsep}{os.environ['PATH']}")
        return subprocess.run(
            [sys.executable, str(SCRIPT), "--seconds", "1",
             "--diagnostics", str(directory / "diagnostics"), *wrapper_arguments],
            env=env, capture_output=True, text=True, timeout=15,
        )

    def test_preserves_normal_failure_and_output(self):
        with tempfile.TemporaryDirectory() as tmp:
            directory = Path(tmp)
            result = self.run_fake_swift(directory, 'echo "$*"; exit 7\n')
            self.assertEqual(result.returncode, 7)
            self.assertEqual(result.stdout.strip(), "test --verbose")
            self.assertFalse((directory / "diagnostics").exists())

    def test_forwards_every_skip_pattern_as_a_separate_argument(self):
        with tempfile.TemporaryDirectory() as tmp:
            patterns = ("Module[.]FirstTests/", "Module[.]OtherTests/testExample$")
            result = self.run_fake_swift(
                Path(tmp), 'printf "%s\\n" "$@"\n',
                "--skip", patterns[0], "--skip", patterns[1],
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(
                result.stdout.splitlines(),
                ["test", "--verbose", "--skip", patterns[0], "--skip", patterns[1]],
            )

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

    def test_timeout_captures_and_stops_descendant_with_separate_group(self):
        with tempfile.TemporaryDirectory() as tmp:
            directory = Path(tmp)
            child = "import os, time; os.setsid(); print(os.getpid(), flush=True); time.sleep(60)"
            result = self.run_fake_swift(
                directory, f"{quote(sys.executable)} -c {quote(child)} & wait\n",
            )
            self.assertEqual(result.returncode, 124, result.stderr)
            child_pid = result.stdout.splitlines()[0]
            snapshot = (directory / "diagnostics" / "timeout-processes.txt").read_text()
            row = next(line.split() for line in snapshot.splitlines() if line.startswith(child_pid + " "))
            self.assertEqual(row[0], row[2])
            self.assertNotEqual(row[0], row[1])

    def test_exited_parent_cannot_bypass_deadline_while_child_holds_output(self):
        with tempfile.TemporaryDirectory() as tmp:
            directory = Path(tmp)
            result = self.run_fake_swift(
                directory, "echo 'parent completed'; sleep 60 & exit 0\n",
            )
            self.assertEqual(result.returncode, 124, result.stderr)
            self.assertIn("parent completed", result.stdout)
            self.assertIn("sleep", (directory / "diagnostics" / "timeout-processes.txt").read_text())

    def test_interrupted_sample_never_exposes_raw_report_for_upload(self):
        wrapper = runpy.run_path(str(SCRIPT))
        with tempfile.TemporaryDirectory() as tmp:
            diagnostics = Path(tmp)

            def interrupted_sample(command, **kwargs):
                raw = Path(command[-1])
                raw.write_text("Raw header\nBinary Images:\n/private/path\n", encoding="utf-8")
                self.assertNotEqual(raw.parent, diagnostics)
                self.assertEqual(list(diagnostics.glob("timeout-stack-*.txt")), [])
                raise KeyboardInterrupt

            process = wrapper["ProcessInfo"](123, 1, 123, "00:01", "S", "swift-test")
            with patch.object(Path, "exists", return_value=True), patch(
                "subprocess.run", side_effect=interrupted_sample,
            ), self.assertRaises(KeyboardInterrupt):
                wrapper["sample_test_processes"]([process], 123, diagnostics)
            self.assertEqual(list(diagnostics.glob("timeout-stack-*.txt")), [])

    def test_exited_parent_leaves_reparented_child_in_owned_session(self):
        with tempfile.TemporaryDirectory() as tmp:
            directory = Path(tmp)
            program = """import os, time
reader, writer = os.pipe()
if os.fork() == 0:
    os.close(reader)
    os.setpgid(0, 0)
    print(os.getpid(), flush=True)
    os.write(writer, b"1")
    os.close(writer)
    time.sleep(60)
else:
    os.close(writer)
    os.read(reader, 1)
"""
            result = self.run_fake_swift(directory, f"exec {quote(sys.executable)} -c {quote(program)}\n")
            self.assertEqual(result.returncode, 124, result.stderr)
            pid = result.stdout.splitlines()[0]
            snapshot = (directory / "diagnostics" / "timeout-processes.txt").read_text()
            row = next(line.split() for line in snapshot.splitlines() if line.startswith(pid + " "))
            self.assertEqual(row[2], pid)
            self.assertEqual(row[1], "1")
            state = subprocess.run(
                ["ps", "-p", pid, "-o", "stat="], capture_output=True, text=True, timeout=5,
            ).stdout.strip()
            self.assertTrue(not state or state.startswith("Z"), state)
