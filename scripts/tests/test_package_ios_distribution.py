import importlib.util
import os
from pathlib import Path
import plistlib
import tempfile
import unittest


SCRIPT = Path(__file__).parents[1] / "package-ios-distribution.py"
SPEC = importlib.util.spec_from_file_location("package_ios_distribution", SCRIPT)
MODULE = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(MODULE)


class IOSDistributionTests(unittest.TestCase):
    def test_canonical_version_projects_to_marketing_and_build(self):
        with tempfile.TemporaryDirectory() as directory:
            version = Path(directory) / "version.nfo"
            version.write_text("0.3.1000\n", encoding="utf-8")
            self.assertEqual(MODULE.canonical_version(version), ("0.3.1000", 1000))

    def test_export_options_are_owner_internal_and_never_auto_incremented(self):
        with tempfile.TemporaryDirectory() as directory:
            options = Path(directory) / "ExportOptions.plist"
            MODULE.export_options(options)
            payload = plistlib.loads(options.read_bytes())
            self.assertEqual(payload["destination"], "export")
            self.assertEqual(payload["method"], "app-store-connect")
            self.assertEqual(payload["signingCertificate"], MODULE.CERTIFICATE_SHA1)
            self.assertEqual(payload["teamID"], MODULE.TEAM_IDENTIFIER)
            self.assertFalse(payload["manageAppVersionAndBuildNumber"])
            self.assertTrue(payload["testFlightInternalTestingOnly"])
            self.assertEqual(
                payload["provisioningProfiles"][MODULE.BUNDLE_IDENTIFIER], MODULE.PROFILE_UUID
            )

    def test_profile_validation_rejects_device_profile(self):
        profile = {
            "UUID": MODULE.PROFILE_UUID,
            "Name": MODULE.PROFILE_NAME,
            "TeamIdentifier": [MODULE.TEAM_IDENTIFIER],
            "Entitlements": {
                "application-identifier": f"{MODULE.TEAM_IDENTIFIER}.{MODULE.BUNDLE_IDENTIFIER}",
                "get-task-allow": False,
            },
            "ProvisionedDevices": ["synthetic-device"],
            "DeveloperCertificates": [bytes.fromhex("00")],
        }
        with self.assertRaisesRegex(MODULE.DistributionError, "provisioned devices"):
            MODULE.validate_profile(profile)

    def test_signing_keychain_setting_is_explicit(self):
        keychain = Path("/Users/example/Library/Keychains/login.keychain-db")
        self.assertEqual(
            MODULE.signing_keychain_build_setting(keychain),
            "--keychain /Users/example/Library/Keychains/login.keychain-db",
        )

    def test_publisher_guard_rejects_wrong_source_sha(self):
        repository = Path(MODULE.__file__).parents[1]
        with self.assertRaisesRegex(ValueError, "HEAD does not match"):
            MODULE.publisher_source_guard(repository, "0" * 40)

    def test_archive_binding_rejects_stale_archive_hash(self):
        with tempfile.TemporaryDirectory() as directory:
            profile = Path(directory) / "profile.mobileprovision"
            profile.write_bytes(b"approved-profile")
            provenance = {
                "source_sha": "a" * 40,
                "source_inputs_sha256": "b" * 64,
                "version": "0.3.1000",
                "build": 1000,
                "profile_sha256": MODULE.sha256(profile),
                "producer": {
                    "source_sha": "a" * 40,
                    "source_inputs_sha256": "b" * 64,
                    "archive_sha256": "old-archive",
                    "app_bundle_sha256": "same-app",
                },
                "stages": {
                    "archive": {
                        "artifact": {
                            "archive_sha256": "old-archive",
                            "app_bundle_sha256": "same-app",
                        }
                    }
                },
            }
            artifact = {"archive_sha256": "new-archive", "app_bundle_sha256": "same-app"}
            with self.assertRaisesRegex(ValueError, "recorded producer artifact"):
                MODULE.validate_archive_binding(
                    provenance, artifact, profile, "0.3.1000", 1000,
                    expected_source="a" * 40, expected_inputs="b" * 64,
                )

    def test_export_signing_scope_does_not_mutate_process_environment(self):
        keychain = Path("/Users/example/Library/Keychains/login.keychain-db")
        original = os.environ.get("OTHER_CODE_SIGN_FLAGS")
        environment = MODULE.export_signing_environment(keychain)
        self.assertEqual(
            environment["OTHER_CODE_SIGN_FLAGS"],
            "--keychain /Users/example/Library/Keychains/login.keychain-db",
        )
        self.assertEqual(os.environ.get("OTHER_CODE_SIGN_FLAGS"), original)

    def test_package_script_never_mutates_user_keychain_search_list(self):
        script = SCRIPT.read_text(encoding="utf-8")
        self.assertNotIn("list-keychains", script)
        self.assertNotIn("constrained_keychain_search", script)

if __name__ == "__main__":
    unittest.main()
