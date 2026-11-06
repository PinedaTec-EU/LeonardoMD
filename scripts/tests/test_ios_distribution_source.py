import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest import mock


SOURCE_SCRIPT = Path(__file__).parents[1] / "ios_distribution_source.py"
SOURCE_SPEC = importlib.util.spec_from_file_location("ios_distribution_source_tests", SOURCE_SCRIPT)
SOURCE = importlib.util.module_from_spec(SOURCE_SPEC)
assert SOURCE_SPEC.loader is not None
SOURCE_SPEC.loader.exec_module(SOURCE)

PACKAGE_SCRIPT = Path(__file__).parents[1] / "package-ios-distribution.py"
PACKAGE_SPEC = importlib.util.spec_from_file_location("package_ios_distribution_guard_tests", PACKAGE_SCRIPT)
PACKAGE = importlib.util.module_from_spec(PACKAGE_SPEC)
assert PACKAGE_SPEC.loader is not None
PACKAGE_SPEC.loader.exec_module(PACKAGE)


def git(root: Path, *arguments: str) -> str:
    result = subprocess.run(
        ["git", *arguments], cwd=root, check=True, capture_output=True, text=True
    )
    return result.stdout.strip()


def initialize_repository(root: Path, *, own_entry: bool = True) -> str:
    subprocess.run(["git", "init", "--quiet", "-b", "main"], cwd=root, check=True)
    git(root, "config", "user.name", "Distribution Guard Test")
    git(root, "config", "user.email", "distribution-guard@example.invalid")

    files = {
        "Mobile/LittleLeonardo.xcodeproj/project.pbxproj": "project source\n",
        "version.nfo": "0.3.1000\n",
        "deploy/version/version.yaml": json.dumps({
            "current_version": "0.3.1000",
            "applied": [{"to_version": "0.3.1000"}],
        }) + "\n",
    }
    if own_entry:
        files["deploy/version/entries/371.yaml"] = '{"build": 5}\n'
    for relative, content in files.items():
        path = root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content, encoding="utf-8")

    git(root, "add", "--all")
    git(root, "commit", "--quiet", "-m", "fixture")
    source_sha = git(root, "rev-parse", "HEAD")
    git(root, "update-ref", "refs/remotes/origin/main", source_sha)
    return source_sha


class IOSDistributionSourceTests(unittest.TestCase):
    def assert_archive_rejected_before_build(self, root: Path) -> None:
        args = type("Args", (), {"pr_number": 371})()
        with mock.patch.object(PACKAGE, "run_archive_build") as build:
            with self.assertRaisesRegex(PACKAGE.SourceGuardError, "Author archive source checkout"):
                PACKAGE.run_archive(args, root)
            build.assert_not_called()

    def test_author_archive_rejects_dirty_tracked_source_before_build(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            initialize_repository(root)
            source = root / "Mobile/LittleLeonardo.xcodeproj/project.pbxproj"
            source.write_text("modified project source\n", encoding="utf-8")

            self.assert_archive_rejected_before_build(root)

    def test_author_archive_rejects_untracked_source_before_build(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            initialize_repository(root)
            source = root / "Mobile/LittleLeonardo/Unexpected.swift"
            source.parent.mkdir(parents=True, exist_ok=True)
            source.write_text("untracked source\n", encoding="utf-8")

            self.assert_archive_rejected_before_build(root)

    def test_author_archive_rejects_other_version_metadata_before_build(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            initialize_repository(root)
            other_entry = root / "deploy/version/entries/372.yaml"
            other_entry.write_text('{"build": 1}\n', encoding="utf-8")

            self.assert_archive_rejected_before_build(root)

    def test_author_archive_allows_only_its_own_ledger_entry_change(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source_sha = initialize_repository(root)
            entry = root / "deploy/version/entries/371.yaml"
            entry.write_text('{"build": 6}\n', encoding="utf-8")
            expected_inputs = SOURCE.source_inputs_sha256(root)
            args = type("Args", (), {"pr_number": 371})()

            with mock.patch.object(PACKAGE, "run_archive_build") as build:
                PACKAGE.run_archive(args, root)

            build.assert_called_once_with(args, root, source_sha, expected_inputs, 371)

    def test_publisher_guard_accepts_a_detached_accepted_checkpoint(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source_sha = initialize_repository(root, own_entry=False)
            git(root, "checkout", "--quiet", "--detach", source_sha)

            guarded_sha, inputs_sha = SOURCE.publisher_source_guard(root, source_sha)

            self.assertEqual(guarded_sha, source_sha)
            self.assertEqual(inputs_sha, SOURCE.source_inputs_sha256(root))

    def test_publisher_guard_still_rejects_own_ledger_changes(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source_sha = initialize_repository(root, own_entry=False)
            entry = root / "deploy/version/entries/371.yaml"
            entry.parent.mkdir(parents=True, exist_ok=True)
            entry.write_text('{"build": 6}\n', encoding="utf-8")

            with self.assertRaisesRegex(SOURCE.SourceGuardError, "Publisher source checkout must be clean"):
                SOURCE.publisher_source_guard(root, source_sha)


if __name__ == "__main__":
    unittest.main()
