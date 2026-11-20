import io
import os
import subprocess
import sys
import textwrap
import unittest
from pathlib import Path
from unittest.mock import Mock

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import ci_plan


class CIPlanTests(unittest.TestCase):
    def select(self, files, labels=(), **live_overrides):
        revisions = {"base": {"sha": "base"}, "head": {"sha": "head"}}
        event = {"number": 7, "pull_request": revisions}
        live = dict(revisions, labels=[{"name": label} for label in labels], changed_files=len(files))
        live.update(live_overrides)
        comparison = {"base_commit": {"sha": "base"}, "status": "diverged", "files": files}
        request = Mock(side_effect=[live, comparison])
        return ci_plan.plan("pull_request", event, "owner/repo", request)

    def test_product_and_documentation_paths(self):
        examples = {
            "Mobile/LittleLeonardo/Reader.swift": {"ios"},
            "Mobile/LittleLeonardo/Legal/LICENSE.txt": {"ios", "package"},
            "doc/validation/git-retirement/fixtures/archive.json": {"ios"},
            "Sources/LeonardoApp/Window.swift": {"macos", "package"},
            "Sources/LeonardoRender/Resources/engine.js": {"macos", "ios", "package"},
            "Sources/LeonardoSyncTransport/Request.swift": {"macos", "ios", "package"},
            "Tests/Packaging/test_package.py": {"package"},
            "plugins/leonardo-format/tests/test_mdlz.py": {"plugin"},
            "plugins/leonardo-format/skills/leonardo-format/scripts/mdlz.py": {"macos", "package", "plugin"},
            "plugins/leonardo-format/skills/leonardo-format/references/mdlf-v1.schema.json": {"macos", "package", "plugin"},
            "doc/guide/en/body.md": {"macos", "package"},
            "README.md": set(),
            "deploy/version/entries/7.yaml": set(),
            "Package.swift": ci_plan.SUITES,
            "doc/format/mdlf-v1.schema.json": ci_plan.SUITES,
            "Tests/FormatContractFixtures/contract.json": ci_plan.SUITES,
            "new-surface/file": ci_plan.SUITES,
        }
        for path, expected in examples.items():
            with self.subTest(path=path):
                selected, decisions, _, _ = self.select([{"filename": path, "status": "modified"}])
                self.assertEqual(selected, expected)
                self.assertEqual(decisions, {path: expected})

    def test_rename_removal_addition_and_labels_are_additive(self):
        files = [
            {"status": "renamed", "previous_filename": "Mobile/Old.swift", "filename": "README.md"},
            {"status": "removed", "filename": "Tests/LeonardoAppTests/Old.swift"},
            {"status": "added", "filename": "doc/adr/decision.md"},
        ]
        suites, paths, labels, _ = self.select(files, ["bug", "ci:plugin"])
        self.assertEqual(suites, {"ios", "macos", "plugin"})
        self.assertEqual(len(paths), 4)
        self.assertEqual(labels, ["ci:plugin"])
        self.assertEqual(self.select(files, ["ci:full"])[0], ci_plan.SUITES)

    def test_failed_or_incomplete_diff_uses_full_coverage(self):
        docs = [{"filename": "README.md", "status": "modified"}]
        for files, metadata in (
            ([], {}),
            (docs, {"changed_files": 2}),
            (docs, {"changed_files": True}),
            (docs * ci_plan.COMPARE_FILE_LIMIT, {}),
            (docs, {"head": {"sha": "other"}}),
            (docs, {"base": {"sha": "other"}}),
            ([{"filename": "README.md", "status": "renamed"}], {}),
            ([{"filename": "README.md", "status": "indeterminate"}], {}),
        ):
            with self.subTest(count=len(files), metadata=metadata):
                self.assertEqual(self.select(files, **metadata)[0], ci_plan.SUITES)
        event = {"number": 7, "pull_request": {"base": {"sha": "base"}, "head": {"sha": "head"}}}
        request = Mock(side_effect=subprocess.CalledProcessError(1, "gh"))
        self.assertEqual(ci_plan.plan("pull_request", event, "owner/repo", request)[0], ci_plan.SUITES)

    def test_main_uses_full_coverage_without_api(self):
        request = Mock()
        self.assertEqual(ci_plan.plan("push", {}, "owner/repo", request)[0], ci_plan.SUITES)
        request.assert_not_called()

    def test_summary_escapes_paths_without_changing_outputs(self):
        path = "Mobile/<script>\nmacos=true|"
        result = self.select([{"filename": path, "status": "added"}])
        outputs, summary = io.StringIO(), io.StringIO()
        ci_plan.write_plan(*result, outputs, summary)
        self.assertEqual(outputs.getvalue().splitlines(), ["ios=true", "macos=false", "package=false", "plugin=false"])
        self.assertIn("&lt;script&gt;", summary.getvalue())
        self.assertIn(r"\nmacos=true", summary.getvalue())

    def test_aggregate_requires_success_only_for_selected_suites(self):
        workflow = (Path(__file__).resolve().parents[2] / ".github/workflows/ci.yml").read_text()
        step = workflow.split("name: Require the planned validation results", 1)[1]
        gate = textwrap.dedent(step.split("run: |\n", 1)[1])
        docs_only = dict(PLAN_RESULT="success")
        for suite in ("MACOS", "IOS", "PACKAGE", "PLUGIN"):
            docs_only.update({f"{suite}_SELECTED": "false", f"{suite}_RESULT": "skipped"})
        for updates, expected in (
            ({}, 0),
            ({"IOS_SELECTED": "true", "IOS_RESULT": "success"}, 0),
            ({"IOS_SELECTED": "true"}, 1),
            ({"IOS_SELECTED": "true", "IOS_RESULT": "failure"}, 1),
            ({"IOS_SELECTED": "true", "IOS_RESULT": "cancelled"}, 1),
            ({"IOS_RESULT": "failure"}, 1),
            ({"IOS_SELECTED": ""}, 1),
            ({"PLAN_RESULT": "failure"}, 1),
        ):
            with self.subTest(updates=updates):
                result = subprocess.run(
                    ["bash", "-c", gate], env=os.environ | docs_only | updates, capture_output=True,
                )
                self.assertEqual(result.returncode, expected, result.stdout)


if __name__ == "__main__":
    unittest.main()
