"""Success/failure/concurrency regressions for the Swift compilation recorder."""
import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


class CompileAndRecordTests(unittest.TestCase):
    def setUp(self):
        scratch = tempfile.TemporaryDirectory()
        self.addCleanup(scratch.cleanup)
        self.root = Path(scratch.name)
        binary = self.root / "bin"
        binary.mkdir()
        swift = binary / "swift"
        swift.write_text('#!/bin/sh\nexit "${SWIFT_FIXTURE_EXIT:-0}"\n')
        swift.chmod(0o755)
        self.env = dict(os.environ, PATH=str(binary) + os.pathsep + os.environ["PATH"])
        self.entry = self.root / "deploy/version/entries/42.yaml"

    def arguments(self, command=None):
        return [sys.executable, str(ROOT / "scripts/compile-and-record.py"),
                "--root", str(self.root), "--pr-number", "42", "--", *(command or ["swift", "build"])]

    def record(self, command=None, failed=False):
        env = dict(self.env, SWIFT_FIXTURE_EXIT="1" if failed else "0")
        return subprocess.run(self.arguments(command), env=env, text=True, capture_output=True)

    def test_successful_commands_accumulate_and_preserve_other_deltas(self):
        self.entry.parent.mkdir(parents=True)
        self.entry.write_text('{"release":2,"feature":1,"build":3}')
        for command in [["swift", "build", "-c", "release"], ["swift", "test"]]:
            result = self.record(command)
            self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(self.entry.read_text()), {"release":2,"feature":1,"build":5})

    def test_failed_command_does_not_create_or_change_entry(self):
        self.assertNotEqual(self.record(failed=True).returncode, 0)
        self.assertFalse(self.entry.exists())
        self.entry.parent.mkdir(parents=True)
        original = '{"build":7}'
        self.entry.write_text(original)
        self.assertNotEqual(self.record(failed=True).returncode, 0)
        self.assertEqual(self.entry.read_text(), original)

    def test_metadata_queries_and_skip_build_are_not_compilations(self):
        for command in [["swift", "build", "--show-bin-path"],
                        ["swift", "test", "--skip-build"], ["swift", "package", "resolve"]]:
            with self.subTest(command=command):
                self.assertNotEqual(self.record(command).returncode, 0)
                self.assertFalse(self.entry.exists())

    def test_parallel_commands_do_not_lose_build_increments(self):
        processes = [subprocess.Popen(self.arguments(), env=self.env,
                                      stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
                     for _ in range(4)]
        for process in processes:
            output, error = process.communicate(timeout=10)
            self.assertEqual(process.returncode, 0, error)
        self.assertEqual(json.loads(self.entry.read_text()), {"build":4})

    def test_invalid_existing_entry_is_preserved(self):
        self.entry.parent.mkdir(parents=True)
        self.entry.write_text('{"build":true}')
        self.assertNotEqual(self.record().returncode, 0)
        self.assertEqual(self.entry.read_text(), '{"build":true}')


if __name__ == "__main__":
    unittest.main()
