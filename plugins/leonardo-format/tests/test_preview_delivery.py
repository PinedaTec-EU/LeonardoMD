import json
import hashlib
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


PLUGIN = Path(__file__).resolve().parents[1]
HOOK = PLUGIN / "hooks/preview_delivery.py"
PREVIEW = "[Vista previa de Leonardo](http://127.0.0.1:12345/" + "a" * 32 + "/preview)"


def preview_for(document: Path) -> str:
    fingerprint = hashlib.sha256(
        os.fsencode(str(document.resolve(strict=True)))
    ).hexdigest()
    return (
        "[Vista previa de Leonardo](http://127.0.0.1:12345/"
        + "a" * 32
        + "/preview#document="
        + fingerprint
        + ")"
    )


class PreviewDeliveryTests(unittest.TestCase):
    def run_hook(self, message, *, active=False):
        result = subprocess.run(
            [sys.executable, str(HOOK)],
            input=json.dumps({"last_assistant_message": message, "stop_hook_active": active}),
            text=True, capture_output=True, check=True,
        )
        return json.loads(result.stdout)

    def test_prompts_once_for_local_document_delivery(self):
        for link in (
            "[Form](/tmp/form.MDLF:12)",
            "[Reply](</tmp/form reply.mdlr>)",
            "[Bundle](/tmp/form%20(copy).mdlz)",
            "[Bundle](C:\\Users\\A\\form.mdlz)",
        ):
            with self.subTest(link=link):
                result = self.run_hook(link)
                self.assertEqual(result["decision"], "block")
                self.assertIn("Vista previa de Leonardo", result["reason"])
                self.assertEqual(self.run_hook(link, active=True), {})

    def test_only_requests_missing_preview_links(self):
        with tempfile.TemporaryDirectory() as tmp:
            document = Path(tmp) / "a.mdlz"
            document.touch()
            delivery = f"[Bundle]({document})\n" + preview_for(document)
            self.assertEqual(self.run_hook(delivery), {})
            self.assertEqual(self.run_hook(delivery + f"\n[Bundle again]({document}:1)"), {})
            other = Path(tmp) / "b.mdlf"
            other.touch()
            self.assertEqual(self.run_hook(delivery + f"\n[Form]({other})")["decision"], "block")

    def test_unrelated_preview_does_not_cover_another_document(self):
        with tempfile.TemporaryDirectory() as tmp:
            first = Path(tmp) / "a.mdlf"
            second = Path(tmp) / "b.mdlf"
            first.touch()
            second.touch()
            self.assertEqual(
                self.run_hook(f"[Form]({first}) — {preview_for(first)}"),
                {},
            )
            self.assertEqual(
                self.run_hook(f"[Form]({second}) — {preview_for(first)}")["decision"],
                "block",
            )

    def test_preview_label_and_fingerprint_are_required(self):
        with tempfile.TemporaryDirectory() as tmp:
            document = Path(tmp) / "form.mdlf"
            document.touch()
            url = preview_for(document).split("](", 1)[1][:-1]
            self.assertEqual(
                self.run_hook(f"[Other resource]({url})\n[Form]({document})")["decision"],
                "block",
            )
            self.assertEqual(
                self.run_hook(f"[Form]({document})\n{PREVIEW}")["decision"],
                "block",
            )

    def test_unrelated_messages_pass_through(self):
        for message in (
            None, "It supports .mdlz", "[ZIP](/tmp/file.zip)",
            "[Download](https://example.org/file.mdlz)", "![Image](/tmp/file.mdlz)",
            "```md\n[Example](/tmp/file.mdlz)\n```\n",
        ):
            with self.subTest(message=message):
                self.assertEqual(self.run_hook(message), {})

    def test_codex_manifests_declare_the_same_stop_hook(self):
        portable = json.loads((PLUGIN / "plugin.json").read_text())
        overlay = json.loads((PLUGIN / ".codex-plugin/plugin.json").read_text())
        hook_path = portable["extensions"]["com.openai"]["hooks"]
        self.assertEqual(hook_path, overlay["hooks"])
        config = json.loads((PLUGIN / hook_path).read_text())
        self.assertEqual(set(config["hooks"]), {"Stop"})
        self.assertIn("hooks/preview_delivery.py", config["hooks"]["Stop"][0]["hooks"][0]["command"])
