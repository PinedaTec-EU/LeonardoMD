import importlib.util
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


if __name__ == "__main__":
    unittest.main()
