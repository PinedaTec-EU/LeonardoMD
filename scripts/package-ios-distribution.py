#!/usr/bin/env python3
"""Build and verify a manually signed Little Leonardo distribution artifact.

The script is deliberately scoped to the repository's owner-only TestFlight
target. Archive output, export options, logs and provenance must live outside
the checkout. It never uploads an artifact or changes App Store Connect state.
"""

from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import subprocess
import sys
import tempfile
import zipfile


BUNDLE_IDENTIFIER = "eu.pinedatec.LittleLeonardo"
TEAM_IDENTIFIER = "AU2Z3P42U7"
PROFILE_UUID = "df1e793d-b217-420f-80ab-3baca818f7cd"
PROFILE_NAME = "Little Leonardo App Store"
CERTIFICATE_SHA1 = "AB2AD322CF8EB045929230D9C92B920BFB2B1EBB"
PRIVACY_REASONS = {
    "NSPrivacyAccessedAPICategoryUserDefaults": {"CA92.1"},
    "NSPrivacyAccessedAPICategoryFileTimestamp": {"C617.1"},
}


class DistributionError(ValueError):
    """Raised when a distribution input or artifact fails closed validation."""


def repository_root() -> Path:
    return Path(__file__).resolve().parents[1]


def ensure_external(path: Path, root: Path) -> Path:
    resolved = path.expanduser().resolve()
    try:
        common = Path(os.path.commonpath((str(resolved), str(root.resolve()))))
    except ValueError as error:
        raise DistributionError(f"Cannot compare output path {resolved}") from error
    if common == root.resolve():
        raise DistributionError(f"Distribution output must be outside checkout: {resolved}")
    return resolved


def canonical_version(version_path: Path) -> tuple[str, int]:
    value = version_path.read_text(encoding="utf-8").strip()
    if not re.fullmatch(r"(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)", value):
        raise DistributionError(f"Invalid canonical version.nfo: {value!r}")
    build = int(value.rsplit(".", 1)[1])
    if not 1 <= build <= 9999:
        raise DistributionError(f"iOS CFBundleVersion is outside 1–9999: {build}")
    return value, build


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def decode_profile(path: Path) -> dict:
    try:
        result = subprocess.run(
            ["security", "cms", "-D", "-i", str(path)],
            check=True,
            capture_output=True,
        )
        value = plistlib.loads(result.stdout)
    except (OSError, subprocess.CalledProcessError, plistlib.InvalidFileException) as error:
        raise DistributionError(f"Cannot decode provisioning profile: {path}") from error
    if not isinstance(value, dict):
        raise DistributionError("Provisioning profile payload is not a dictionary")
    return value


def certificate_fingerprints(profile: dict) -> set[str]:
    return {
        hashlib.sha1(bytes(certificate)).hexdigest().upper()
        for certificate in profile.get("DeveloperCertificates", [])
        if isinstance(certificate, (bytes, bytearray))
    }


def validate_profile(profile: dict) -> dict:
    entitlements = profile.get("Entitlements")
    team_ids = profile.get("TeamIdentifier")
    if profile.get("UUID") != PROFILE_UUID:
        raise DistributionError("Provisioning profile UUID does not match the approved profile")
    if profile.get("Name") != PROFILE_NAME:
        raise DistributionError("Provisioning profile name does not match the approved profile")
    if not isinstance(team_ids, list) or TEAM_IDENTIFIER not in team_ids:
        raise DistributionError("Provisioning profile team does not match the app team")
    if not isinstance(entitlements, dict):
        raise DistributionError("Provisioning profile has no entitlements")
    expected_app_id = f"{TEAM_IDENTIFIER}.{BUNDLE_IDENTIFIER}"
    if entitlements.get("application-identifier") != expected_app_id:
        raise DistributionError("Provisioning profile application identifier is incorrect")
    if entitlements.get("get-task-allow") is not False:
        raise DistributionError("Distribution profile must disable get-task-allow")
    if "ProvisionedDevices" in profile:
        raise DistributionError("App Store profile must not contain provisioned devices")
    expiration = profile.get("ExpirationDate")
    if isinstance(expiration, dt.datetime) and expiration <= dt.datetime.now():
        raise DistributionError("Provisioning profile is expired")
    fingerprints = certificate_fingerprints(profile)
    if CERTIFICATE_SHA1 not in fingerprints:
        raise DistributionError("Provisioning profile does not contain the approved certificate")
    return {
        "uuid": profile["UUID"],
        "name": profile["Name"],
        "team_id": TEAM_IDENTIFIER,
        "application_identifier": expected_app_id,
        "certificate_sha1": CERTIFICATE_SHA1,
        "expires": expiration.isoformat() if isinstance(expiration, dt.datetime) else None,
    }


def validate_profile_path(path: Path) -> dict:
    return validate_profile(decode_profile(path))


def read_plist(path: Path) -> dict:
    try:
        with path.open("rb") as stream:
            value = plistlib.load(stream)
    except (OSError, plistlib.InvalidFileException) as error:
        raise DistributionError(f"Cannot read plist: {path}") from error
    if not isinstance(value, dict):
        raise DistributionError(f"Plist is not a dictionary: {path}")
    return value


def privacy_manifest(app: Path) -> tuple[Path, dict]:
    manifests = sorted(app.rglob("PrivacyInfo.xcprivacy"))
    if not manifests:
        raise DistributionError("Archive does not contain PrivacyInfo.xcprivacy")
    own = app / "PrivacyInfo.xcprivacy"
    path = own if own in manifests else manifests[0]
    manifest = read_plist(path)
    entries = manifest.get("NSPrivacyAccessedAPITypes")
    if not isinstance(entries, list):
        raise DistributionError("Privacy manifest has no NSPrivacyAccessedAPITypes array")
    observed: dict[str, set[str]] = {}
    for entry in entries:
        if not isinstance(entry, dict):
            raise DistributionError("Privacy manifest contains a non-dictionary API entry")
        api_type = entry.get("NSPrivacyAccessedAPIType")
        reasons = entry.get("NSPrivacyAccessedAPITypeReasons")
        if not isinstance(api_type, str) or not isinstance(reasons, list):
            raise DistributionError("Privacy manifest API entry is malformed")
        observed[api_type] = {reason for reason in reasons if isinstance(reason, str)}
    for api_type, expected in PRIVACY_REASONS.items():
        if not expected.issubset(observed.get(api_type, set())):
            raise DistributionError(f"Privacy manifest is missing approved reasons for {api_type}")
    if any("3B52.1" in reasons for reasons in observed.values()):
        raise DistributionError("3B52.1 is not justified by the current mobile read call graph")
    return path, manifest


def signing_details(app: Path) -> str:
    try:
        subprocess.run(["codesign", "--verify", "--deep", "--strict", str(app)], check=True,
                       capture_output=True)
        result = subprocess.run(["codesign", "-dv", "--verbose=4", str(app)],
                                check=True, capture_output=True, text=True)
    except (OSError, subprocess.CalledProcessError) as error:
        raise DistributionError(f"Code signature verification failed: {app}") from error
    details = result.stdout + result.stderr
    if f"Identifier={BUNDLE_IDENTIFIER}" not in details:
        raise DistributionError("Signed app identifier does not match the target")
    if f"TeamIdentifier={TEAM_IDENTIFIER}" not in details:
        raise DistributionError("Signed app team does not match the target")
    return details


def verify_app(app: Path, expected_version: str, expected_build: int, profile_path: Path) -> dict:
    if not app.is_dir() or app.suffix != ".app":
        raise DistributionError(f"Expected an app bundle: {app}")
    info = read_plist(app / "Info.plist")
    if info.get("CFBundleIdentifier") != BUNDLE_IDENTIFIER:
        raise DistributionError("Packaged bundle identifier is incorrect")
    if info.get("CFBundleShortVersionString") != expected_version:
        raise DistributionError("Packaged marketing version differs from version.nfo")
    if str(info.get("CFBundleVersion")) != str(expected_build):
        raise DistributionError("Packaged build differs from version.nfo")
    if not (app / "Assets.car").is_file():
        raise DistributionError("Compiled asset catalog is missing")
    icon_name = info.get("CFBundleIconName")
    icon_files = info.get("CFBundleIcons", {}).get("CFBundlePrimaryIcon", {}).get("CFBundleIconFiles", [])
    if icon_name != "AppIcon" and not icon_files:
        raise DistributionError("Packaged app has no AppIcon metadata")
    if "UILaunchScreen" not in info and "UILaunchStoryboardName" not in info:
        raise DistributionError("Packaged app has no launch-screen metadata")
    if not any(key.startswith("UISupportedInterfaceOrientations") for key in info):
        raise DistributionError("Packaged app has no orientation metadata")
    profile_metadata = validate_profile_path(profile_path)
    embedded_profile = app / "embedded.mobileprovision"
    if not embedded_profile.is_file():
        raise DistributionError("Packaged app has no embedded provisioning profile")
    embedded_metadata = validate_profile_path(embedded_profile)
    if embedded_metadata != profile_metadata:
        raise DistributionError("Embedded provisioning profile differs from approved profile")
    signature = signing_details(app)
    executable = app / str(info.get("CFBundleExecutable", ""))
    if not executable.is_file():
        raise DistributionError("Packaged executable is missing")
    try:
        dependencies = subprocess.run(["otool", "-L", str(executable)], check=True,
                                      capture_output=True, text=True).stdout
    except (OSError, subprocess.CalledProcessError) as error:
        raise DistributionError("Unable to inspect packaged executable dependencies") from error
    if "XCTest.framework" in dependencies:
        raise DistributionError("Distribution app unexpectedly links XCTest")
    _, manifest = privacy_manifest(app)
    return {
        "bundle_identifier": BUNDLE_IDENTIFIER,
        "version": expected_version,
        "build": expected_build,
        "icon_name": icon_name,
        "launch_screen": "UILaunchScreen" in info or "UILaunchStoryboardName" in info,
        "orientation_keys": sorted(key for key in info if key.startswith("UISupportedInterfaceOrientations")),
        "privacy_manifest_types": sorted(
            entry["NSPrivacyAccessedAPIType"] for entry in manifest["NSPrivacyAccessedAPITypes"]
        ),
        "embedded_profile": embedded_metadata,
        "codesign_verified": True,
        "xctest_dependency": False,
        "nested_frameworks": sorted(str(path.relative_to(app)) for path in app.rglob("*.framework")),
        "signature_summary": "TeamIdentifier=" + TEAM_IDENTIFIER,
    }


def archive_app(archive: Path) -> Path:
    app = archive / "Products" / "Applications" / "LittleLeonardo.app"
    if not app.is_dir():
        raise DistributionError(f"Archive has no LittleLeonardo.app: {archive}")
    if list(archive.rglob("*.xctest")):
        raise DistributionError("Archive contains a test bundle")
    return app


def verify_archive(archive: Path, profile: Path, version: str, build: int) -> dict:
    app = archive_app(archive)
    result = verify_app(app, version, build, profile)
    result.update({"artifact": "xcarchive", "archive_sha256": sha256(archive / "Info.plist")})
    return result


def exported_app_path(ipa: Path) -> tuple[tempfile.TemporaryDirectory, Path]:
    temporary = tempfile.TemporaryDirectory(prefix="leonardo-ios-ipa-")
    root = Path(temporary.name)
    try:
        with zipfile.ZipFile(ipa) as archive:
            archive.extractall(root)
    except (OSError, zipfile.BadZipFile) as error:
        temporary.cleanup()
        raise DistributionError(f"Cannot inspect IPA: {ipa}") from error
    app = root / "Payload" / "LittleLeonardo.app"
    if not app.is_dir():
        temporary.cleanup()
        raise DistributionError("IPA does not contain Payload/LittleLeonardo.app")
    return temporary, app


def verify_ipa(ipa: Path, profile: Path, version: str, build: int) -> dict:
    temporary, app = exported_app_path(ipa)
    try:
        if any(path.name.endswith(".xctest") for path in app.rglob("*.xctest")):
            raise DistributionError("IPA contains a test bundle")
        result = verify_app(app, version, build, profile)
        result.update({"artifact": "ipa", "ipa_sha256": sha256(ipa)})
        return result
    finally:
        temporary.cleanup()


def write_provenance(path: Path, root: Path, artifact: dict, profile: Path) -> None:
    version, build = canonical_version(root / "version.nfo")
    payload = {
        "schema_version": 1,
        "repository": "PinedaTec-EU/LeonardoMD",
        "source_sha": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=root, text=True).strip(),
        "version_source": "version.nfo",
        "version_source_sha256": sha256(root / "version.nfo"),
        "version": version,
        "build": build,
        "bundle_identifier": BUNDLE_IDENTIFIER,
        "team_identifier": TEAM_IDENTIFIER,
        "profile_uuid": PROFILE_UUID,
        "profile_sha256": sha256(profile),
        "certificate_sha1": CERTIFICATE_SHA1,
        "icon_source": "assets/AppIcon/LeonardoMD.png",
        "icon_source_sha256": sha256(root / "assets/AppIcon/LeonardoMD.png"),
        "privacy_manifest_sha256": sha256(root / "Mobile/LittleLeonardo/PrivacyInfo.xcprivacy"),
        "generated_at": dt.datetime.now(dt.timezone.utc).isoformat(),
        "artifact": artifact,
    }
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def run_archive(args: argparse.Namespace, root: Path) -> None:
    version, build = canonical_version(root / "version.nfo")
    output = ensure_external(args.output_root, root)
    profile = Path(args.profile).expanduser().resolve()
    profile_metadata = validate_profile_path(profile)
    output.mkdir(parents=True, exist_ok=True)
    archive = output / "LittleLeonardo.xcarchive"
    derived = output / "DerivedData"
    command = [
        "xcodebuild", "-project", "Mobile/LittleLeonardo.xcodeproj", "-scheme", "LittleLeonardo",
        "-configuration", "Release", "-destination", "generic/platform=iOS",
        "-derivedDataPath", str(derived), "-archivePath", str(archive),
        "PRODUCT_BUNDLE_IDENTIFIER=" + BUNDLE_IDENTIFIER, "MARKETING_VERSION=" + version,
        "CURRENT_PROJECT_VERSION=" + str(build), "CODE_SIGNING_ALLOWED=YES",
        "CODE_SIGNING_REQUIRED=YES", "archive",
    ]
    recorder = [sys.executable, str(root / "scripts/compile-and-record.py"),
                "--root", str(root), "--pr-number", str(args.pr_number), "--"]
    subprocess.run(recorder + command, cwd=root, check=True)
    artifact = verify_archive(archive, profile, version, build)
    artifact["approved_profile"] = profile_metadata
    write_provenance(output / "distribution-provenance.json", root, artifact, profile)
    print(json.dumps({"archive": str(archive), "provenance": str(output / "distribution-provenance.json")}, indent=2))


def export_options(path: Path) -> None:
    options = {
        "destination": "export",
        "method": "app-store-connect",
        "signingStyle": "manual",
        "teamID": TEAM_IDENTIFIER,
        "provisioningProfiles": {BUNDLE_IDENTIFIER: PROFILE_UUID},
        "manageAppVersionAndBuildNumber": False,
        "testFlightInternalTestingOnly": True,
        "uploadSymbols": True,
    }
    with path.open("wb") as stream:
        plistlib.dump(options, stream, sort_keys=False)


def run_export(args: argparse.Namespace, root: Path) -> None:
    version, build = canonical_version(root / "version.nfo")
    output = ensure_external(args.output_root, root)
    archive = Path(args.archive).expanduser().resolve()
    profile = Path(args.profile).expanduser().resolve()
    verify_archive(archive, profile, version, build)
    export_path = ensure_external(Path(args.export_path), root)
    output.mkdir(parents=True, exist_ok=True)
    export_path.mkdir(parents=True, exist_ok=True)
    options_path = output / "ExportOptions.plist"
    export_options(options_path)
    subprocess.run(["xcodebuild", "-exportArchive", "-archivePath", str(archive),
                    "-exportPath", str(export_path), "-exportOptionsPlist", str(options_path)],
                   cwd=root, check=True)
    ipa_files = sorted(export_path.glob("*.ipa"))
    if len(ipa_files) != 1:
        raise DistributionError(f"Expected exactly one exported IPA, found {len(ipa_files)}")
    artifact = verify_ipa(ipa_files[0], profile, version, build)
    write_provenance(output / "distribution-provenance.json", root, artifact, profile)
    print(json.dumps({"ipa": str(ipa_files[0]), "provenance": str(output / "distribution-provenance.json")}, indent=2))


def run_validate(args: argparse.Namespace, root: Path) -> None:
    version, build = canonical_version(root / "version.nfo")
    ipa = Path(args.ipa).expanduser().resolve()
    profile = Path(args.profile).expanduser().resolve()
    artifact = verify_ipa(ipa, profile, version, build)
    subprocess.run(["xcrun", "altool", "--validate-app", "--file", str(ipa), "--type", "ios",
                    "--apiKey", args.api_key_id, "--apiIssuer", args.api_issuer],
                   cwd=root, check=True)
    report = {
        "schema_version": 1,
        "source_sha": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=root, text=True).strip(),
        "version": version,
        "build": build,
        "ipa_sha256": sha256(ipa),
        "artifact": artifact,
        "apple_validation": "altool --validate-app passed; no upload performed",
    }
    report_path = ensure_external(Path(args.report), root)
    report_path.parent.mkdir(parents=True, exist_ok=True)
    report_path.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps({"report": str(report_path), "ipa_sha256": report["ipa_sha256"]}, indent=2))


def parser() -> argparse.ArgumentParser:
    root = repository_root()
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    archive = commands.add_parser("archive")
    archive.add_argument("--pr-number", type=int, required=True)
    archive.add_argument("--identity", required=True)
    archive.add_argument("--profile", required=True)
    archive.add_argument("--output-root", type=Path, required=True)
    archive.set_defaults(handler=run_archive)
    export = commands.add_parser("export")
    export.add_argument("--archive", required=True)
    export.add_argument("--profile", required=True)
    export.add_argument("--output-root", type=Path, required=True)
    export.add_argument("--export-path", type=Path, required=True)
    export.set_defaults(handler=run_export)
    validate = commands.add_parser("validate")
    validate.add_argument("--ipa", required=True)
    validate.add_argument("--profile", required=True)
    validate.add_argument("--api-key-id", required=True)
    validate.add_argument("--api-issuer", required=True)
    validate.add_argument("--report", required=True)
    validate.set_defaults(handler=run_validate)
    parser.set_defaults(root=root)
    return parser


def main() -> int:
    args = parser().parse_args()
    try:
        args.handler(args, args.root)
    except (DistributionError, OSError, subprocess.CalledProcessError) as error:
        print(f"package-ios-distribution: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
