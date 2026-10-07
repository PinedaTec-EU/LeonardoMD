# Signed macOS releases

## Prerequisites

The maintainer needs a Developer ID Application identity, an existing `notarytool` Keychain profile, and a Sparkle Ed25519 signing key in the login Keychain. Generate the Sparkle key once using `.build/artifacts/sparkle/Sparkle/bin/generate_keys` after resolving the package. Keep the private key and Apple credentials out of the repository and release assets. Back up the key securely. Only its public value is embedded in the app.

Set `LEONARDO_VERSION` to a stable `major.minor.patch`, `LEONARDO_BUILD` to a positive integer strictly greater than every previous stable release, `SPARKLE_PUBLIC_KEY` to the generated public key, `DEVELOPER_ID_APPLICATION` to the signing identity, `NOTARY_PROFILE` to the stored profile, and `RELEASE_NOTES_FILE` to a nonempty Markdown file. Supply these through the process environment, not tracked files. Ordinary development builds use 0.1.0 / 1 and do not enable the channel.

## Prepare and inspect

Run `./scripts/prepare-release.sh` from the repository. It builds the app, embeds Sparkle including symlinks and executable helpers, signs nested components inside out with hardened runtime, verifies signatures, notarizes, staples, assesses Gatekeeper, then generates the archive and EdDSA-signed appcast. It stops on failure. Release notes are embedded in the appcast. Output is under `output/release-<version>/`. No tag or release is published by this script.

The archive contains only the application. Sparkle infers supported hardware and the minimum OS from the bundle. This script builds for the host architecture; publish only for that architecture until universal builds have been independently validated. Every stable release must include `appcast.xml` and its referenced ZIP, with URLs matching the tag `v<version>`. The bundled feed uses GitHub's latest stable release redirect. Mark experimental releases as prereleases and never promote them as latest. Keep a stable channel available even if a non-app release is created.

Before publishing, inspect the version/build, appcast URLs, release notes and archive contents. Confirm the build is newer than the current stable feed. Publish the ZIP and appcast together in a draft GitHub release and make it public only when complete. GitHub's latest stable release must always have the feed asset. Retain old release ZIPs referenced by prior feeds. This change does not publish a release or provision signing credentials.

## Acceptance on a release candidate

Install an older signed app in a writable Applications folder and publish a newer signed candidate on a controlled test feed. Verify manual no-update/error/update dialogs, persisted periodic-check preference, release notes, download, install and relaunch. Edit a document before installation; cancel quit and confirm the draft survives, then save and retry. Confirm Git operations also prevent premature quit. Tamper with the ZIP and confirm signature rejection before extraction; test offline mode and an unsupported architecture. Repeat with the production feed before claiming end-to-end release acceptance.

## PR dependency

The update implementation is intentionally stacked on PR #8 at owner request. Merge #8 first, then retarget the updater PR to `main` and refresh its validation/review. Do not merge the updater branch independently of the MVP application.
