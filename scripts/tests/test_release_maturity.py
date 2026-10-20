import base64
import json
import shutil
import sys
from unittest.mock import patch
import importlib.util
import hashlib
import plistlib
import tempfile
import unittest
import zipfile
from pathlib import Path

SPEC = importlib.util.spec_from_file_location("release_maturity", Path(__file__).parents[1] / "publish-release-maturity.py")
maturity = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(maturity)


class ReleaseMaturityTests(unittest.TestCase):
    trusted = plistlib.loads((maturity.ROOT / "scripts/Info.plist").read_bytes())["LeonardoUpdatePublicKey"]
    def archive(self, directory, **overrides):
        info = {"CFBundleShortVersionString": "0.1.601", "CFBundleVersion": "601",
                "CFBundleExecutable": "LeonardoMD", "LeonardoUpdateChannel": "beta",
                "SUPublicEDKey": self.trusted, "LeonardoUpdatePublicKey": self.trusted}
        info.update(overrides)
        archive = Path(directory) / "candidate.zip"
        with zipfile.ZipFile(archive, "w") as package:
            package.writestr("LeonardoMD.app/Contents/Info.plist", plistlib.dumps(info))
            package.writestr("LeonardoMD.app/Contents/MacOS/LeonardoMD", b"signed executable fixture")
            package.writestr("LeonardoMD.app/Contents/_CodeSignature/CodeResources", b"signed resources fixture")
        return archive

    def exercise_entrypoint(self, *, prerelease=False, account_key=None, changed=False):
        with tempfile.TemporaryDirectory() as directory:
            directory = Path(directory)
            archive = self.archive(directory)
            output = directory / "proof.json"
            commands = []
            uploads = []
            release = {"id": 12, "draft": False, "prerelease": prerelease, "tag_name": "v0.1.601", "assets": []}
            api_reads = 0

            def command(*args):
                nonlocal api_reads
                commands.append(args)
                if args[:2] == ("gh", "api"):
                    api_reads += 1
                    return json.dumps(dict(release, prerelease=prerelease or (changed and api_reads > 1)))
                if args[:3] == ("gh", "release", "download"):
                    name = args[args.index("--pattern") + 1]
                    target = Path(args[args.index("--dir") + 1]) / name
                    if name.endswith(".zip"):
                        shutil.copyfile(archive, target)
                    elif name == "appcast.xml":
                        target.write_text(f'''<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel><item><sparkle:version>601</sparkle:version><enclosure url="https://github.com/PinedaTec-EU/LeonardoMD/releases/download/v0.1.601/LeonardoMD-0.1.601.zip" length="{archive.stat().st_size}" sparkle:edSignature="fixture" /></item></channel></rss>''')
                    else:
                        target.write_bytes(uploads[0])
                    return ""
                if args[:3] == ("gh", "release", "upload"):
                    uploads.append(Path(args[4]).read_bytes())
                    return ""
                if str(args[0]).endswith("generate_keys"):
                    return account_key or self.trusted
                if str(args[0]).endswith("sign_update") and "-p" in args:
                    return base64.b64encode(bytes(64)).decode()
                return ""

            arguments = ["publish-release-maturity.py", "--tag", "v0.1.601", "--output", str(output), "--publish"]
            with patch.object(sys, "argv", arguments), patch.object(maturity, "run", side_effect=command):
                if prerelease or account_key or changed:
                    with self.assertRaises(ValueError):
                        maturity.main()
                    self.assertFalse(uploads)
                else:
                    maturity.main()
                    self.assertEqual(uploads, [output.read_bytes()])
                    self.assertFalse(any("--clobber" in args for args in commands))
                    self.assertTrue(any("--verify" in args for args in commands))
                    self.assertEqual(len(json.loads(output.read_text())["signature"]), 88)

    def test_real_entrypoint_publishes_and_reads_back_proof(self):
        self.exercise_entrypoint()

    def test_real_entrypoint_refuses_beta_release_wrong_key_and_release_race(self):
        self.exercise_entrypoint(prerelease=True)
        self.exercise_entrypoint(account_key="untrusted")
        self.exercise_entrypoint(changed=True)

    def test_identity_binds_exact_executable_archive_version_and_build_without_modifying_zip(self):
        with tempfile.TemporaryDirectory() as directory:
            archive = self.archive(directory)
            before = archive.read_bytes()
            result, info = maturity.publication(archive, "0.1.601")
            self.assertEqual(result["channel"], "stable")
            self.assertEqual(info["LeonardoUpdateChannel"], "beta")
            self.assertEqual(result["executableSHA256"], hashlib.sha256(b"signed executable fixture").hexdigest())
            self.assertEqual(result["archiveSHA256"], hashlib.sha256(before).hexdigest())
            self.assertEqual(result["resourceSealSHA256"], hashlib.sha256(b"signed resources fixture").hexdigest())
            self.assertEqual(archive.read_bytes(), before)

    def test_rejects_wrong_version_build_executable_and_development_package(self):
        for overrides in ({"CFBundleShortVersionString": "0.1.600"}, {"CFBundleVersion": "600"},
                          {"CFBundleExecutable": "../LeonardoMD"}, {"LeonardoUpdateChannel": "development"}):
            with self.subTest(overrides=overrides), tempfile.TemporaryDirectory() as directory:
                with self.assertRaises(ValueError):
                    maturity.publication(self.archive(directory, **overrides), "0.1.601")

    def test_rejects_duplicate_executable(self):
        with tempfile.TemporaryDirectory() as directory:
            archive = self.archive(directory)
            with zipfile.ZipFile(archive, "a") as package:
                package.writestr("LeonardoMD.app/Contents/MacOS/LeonardoMD", b"other")
            with self.assertRaises(ValueError):
                maturity.publication(archive, "0.1.601")


if __name__ == "__main__":
    unittest.main()
