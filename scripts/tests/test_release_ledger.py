"""Consumer contract exercised against the pinned shared engine, when available."""
import json
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
ENGINE = os.environ.get("LEDGER_ENGINE_ROOT")


@unittest.skipUnless(ENGINE, "Set LEDGER_ENGINE_ROOT to exercise the pinned shared engine")
class ReleaseLedgerTests(unittest.TestCase):
    def setUp(self):
        scratch = tempfile.TemporaryDirectory()
        self.addCleanup(scratch.cleanup)
        self.root = Path(scratch.name)
        for relative in ["deploy/version/release-ledger.json", "deploy/version/version.yaml",
                         "version.nfo", "scripts/release-ledger.sh"]:
            destination = self.root / relative
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(ROOT / relative, destination)
        (self.root / "Sources").mkdir()
        self.git("init", "-b", "main")
        self.git("config", "user.name", "Ledger fixture")
        self.git("config", "user.email", "fixture@example.invalid")
        self.base = self.commit("Seed fixture")

    def git(self, *arguments):
        return subprocess.check_output(["git", *arguments], cwd=self.root, text=True).strip()

    def commit(self, title):
        self.git("add", ".")
        self.git("commit", "-m", title)
        return self.git("rev-parse", "HEAD")

    def engine(self, command, **parameters):
        env = dict(os.environ, LEDGER_ENGINE_ROOT=ENGINE, **parameters)
        return subprocess.run(["bash", "scripts/release-ledger.sh", command],
                              cwd=self.root, env=env, text=True, capture_output=True)

    def source_change(self, entry=True, delta=None):
        (self.root / "Sources/fixture.swift").write_text("// Consumer fixture\n")
        if entry:
            directory = self.root / "deploy/version/entries"
            directory.mkdir()
            (directory / "101.yaml").write_text(json.dumps(delta or {"build": 1}))
        return self.commit("#38 Added: source fixture")

    def validate_source(self, head):
        return self.engine("validate-pr", LEDGER_BASE_SHA=self.base,
                           LEDGER_HEAD_SHA=head, LEDGER_PULL_REQUEST_NUMBER="101",
                           LEDGER_PULL_REQUEST_TITLE="#38 Added: source fixture")

    def test_eligible_source_requires_its_own_delta(self):
        result = self.validate_source(self.source_change(entry=False))
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("no pending release entry", result.stderr)

    def test_source_cannot_change_resolved_version(self):
        self.source_change()
        (self.root / "version.nfo").write_text("0.1.57\n")
        head = self.commit("#38 Bumped: invalid source version")
        result = self.validate_source(head)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Version output drift", result.stderr)

    def test_materialization_consumes_once_and_advances_to_57(self):
        head = self.source_change()
        result = self.validate_source(head)
        self.assertEqual(result.returncode, 0, result.stderr)
        order = self.root / "order.json"
        order.write_text(json.dumps({"schema_version": 1,
                                    "pull_requests": [{"number": 101, "merge_sha": head}]}))
        result = self.engine("materialize", LEDGER_INTEGRATION_ORDER_PATH=str(order))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((self.root / "version.nfo").read_text().strip(), "0.1.57")
        self.assertFalse((self.root / "deploy/version/entries/101.yaml").exists())
        state = json.loads((self.root / "deploy/version/version.yaml").read_text())
        self.assertEqual(state["applied"][0]["pr"], 101)
        order.write_text('{"schema_version":1,"pull_requests":[]}')
        result = self.engine("materialize", LEDGER_INTEGRATION_ORDER_PATH=str(order))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("changed=false", result.stdout)
        self.assertEqual((self.root / "version.nfo").read_text().strip(), "0.1.57")
        self.assertFalse((self.root / "deploy/release-notes.md").exists())

    def test_legacy_patch_delta_is_rejected(self):
        result = self.validate_source(self.source_change(delta={"patch": 1}))
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("unknown", result.stderr.lower())

    def test_wrong_pr_entry_is_rejected(self):
        self.source_change()
        (self.root / "deploy/version/entries/101.yaml").rename(
            self.root / "deploy/version/entries/102.yaml")
        result = self.validate_source(self.commit("#38 Added: mismatched delta"))
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("no pending release entry", result.stderr)


if __name__ == "__main__":
    unittest.main()
