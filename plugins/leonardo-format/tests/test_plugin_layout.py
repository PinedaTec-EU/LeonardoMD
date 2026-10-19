from __future__ import annotations

import json
import unittest
from pathlib import Path


PLUGIN_ROOT = Path(__file__).parents[1]


class PluginLayoutTests(unittest.TestCase):
    def read_json(self, relative: str) -> dict[str, object]:
        return json.loads((PLUGIN_ROOT / relative).read_text(encoding="utf-8"))

    def test_portable_manifest_points_to_the_shared_skill(self) -> None:
        manifest = self.read_json("plugin.json")
        self.assertEqual(manifest["name"], "leonardo-format")
        self.assertRegex(manifest["version"], r"^\d+\.\d+\.\d+$")
        self.assertTrue(manifest["description"])
        self.assertIn("https://agent-plugins.org/schemas/1.0.0/plugin.schema.json", manifest["$schema"])
        openai = manifest["extensions"]["com.openai"]
        onboarding = PLUGIN_ROOT / openai["onboardingSkill"][2:]
        self.assertTrue(onboarding.is_file())
        self.assertEqual(openai["interface"]["developerName"], "PinedaTec")

    def test_host_compatibility_manifests_keep_identity_aligned(self) -> None:
        portable = self.read_json("plugin.json")
        claude = self.read_json(".claude-plugin/plugin.json")
        codex = self.read_json(".codex-plugin/plugin.json")
        for manifest in (claude, codex):
            self.assertEqual(manifest["name"], portable["name"])
            self.assertEqual(manifest["version"], portable["version"])
            self.assertEqual(manifest["description"], portable["description"])
        self.assertEqual(codex["skills"], "./skills/")

    def test_skill_declares_provider_neutral_format_workflow(self) -> None:
        skill = (PLUGIN_ROOT / "skills/leonardo-format/SKILL.md").read_text(encoding="utf-8")
        self.assertTrue(skill.startswith("---\n"))
        front_matter = skill.split("---\n", 2)[1]
        self.assertRegex(front_matter, r"(?m)^name:\s*leonardo-format\s*$")
        self.assertRegex(front_matter, r"(?m)^description:\s+\S")
        self.assertIn(".mdlf", skill)
        self.assertIn(".mdlr", skill)
        self.assertIn(".mdlz", skill)
        self.assertIn("mdlz.py", skill)
        self.assertIn("doc/format/", skill)
        self.assertIn("cat > ./request.mdlf", skill)
        self.assertIn("source_ref = \"images/logo.png\"", skill)
        self.assertIn("pack ./request-package ./request.mdlz", skill)

    def test_bundled_schema_matches_canonical_contract(self) -> None:
        canonical = PLUGIN_ROOT.parents[1] / "doc/format/mdlf-v1.schema.json"
        bundled = PLUGIN_ROOT / "skills/leonardo-format/references/mdlf-v1.schema.json"
        self.assertTrue(canonical.is_file())
        self.assertEqual(bundled.read_bytes(), canonical.read_bytes())


if __name__ == "__main__":
    unittest.main()
