# Signed macOS releases

## Prerequisites

The maintainer needs a Developer ID Application identity, an existing `notarytool` Keychain profile, and a Sparkle Ed25519 signing key in the login Keychain. The stable LeonardoMD Keychain account is `LeonardoMD-stable`; set `SPARKLE_KEY_ACCOUNT=LeonardoMD-stable` and read its public key with `generate_keys --account LeonardoMD-stable -p`. Generate a missing Sparkle key once using `.build/artifacts/sparkle/Sparkle/bin/generate_keys` after resolving the package. Keep the private key and Apple credentials out of the repository and release assets. Back up the key securely. Only its public value is embedded in the app.

Set `LEONARDO_VERSION` to the canonical `release.feature.build` in `version.nfo` and `LEONARDO_BUILD` to its third segment, strictly greater than every previous published build, `SPARKLE_PUBLIC_KEY` to the generated public key, `DEVELOPER_ID_APPLICATION` to the signing identity, `NOTARY_PROFILE` to the stored profile, and `RELEASE_NOTES_FILE` to a nonempty Markdown file. Supply these through the process environment, not tracked files. Ordinary development builds derive their version and build from `version.nfo` (initial seed 0.1.56 / 56) and do not enable the channel.

## Prepare and inspect

Run `./scripts/prepare-release.sh` from the repository. It builds the app, embeds Sparkle including symlinks and executable helpers, signs nested components inside out with hardened runtime, verifies signatures, notarizes, staples, assesses Gatekeeper, then generates the archive and EdDSA-signed appcast. It stops on failure. Release notes are embedded in the appcast. Output is under `output/release-<version>/`. No tag or release is published by this script.

The archive contains only the application. Sparkle infers supported hardware and the minimum OS from the bundle. This script builds for the host architecture; publish only for that architecture until universal builds have been independently validated. Every stable release must include `appcast.xml` and its referenced ZIP, with URLs matching the tag `v<version>`. The bundled feed uses GitHub's latest stable release redirect. Mark experimental releases as prereleases and never promote them as latest. Keep a stable channel available even if a non-app release is created.

Before publishing, inspect the version/build, appcast URLs, release notes and archive contents. Confirm the build is newer than the current stable feed. Publish the ZIP and appcast together in a draft GitHub release and make it public only when complete. GitHub's latest stable release must always have the feed asset. Retain old release ZIPs referenced by prior feeds. This change does not publish a release or provision signing credentials.

## Acceptance on a release candidate

Install an older signed app in a writable Applications folder and publish a newer signed candidate on a controlled test feed. Verify manual no-update/error/update dialogs, persisted periodic-check preference, release notes, download, install and relaunch. Edit a document before installation; cancel quit and confirm the draft survives, then save and retry. Confirm Git operations also prevent premature quit. Tamper with the ZIP and confirm signature rejection before extraction; test offline mode and an unsupported architecture. Repeat with the production feed before claiming end-to-end release acceptance.

## Beta candidates

Set `LEONARDO_CHANNEL=beta` and append `-beta.N` to the canonical version (for example, `0.1.56-beta.1`). `LEONARDO_BUILD` must equal the canonical third segment. Before publishing a later beta or stable package, materialize a new ledger build greater than every previously published beta and stable build; changing beta.N alone does not advance Sparkle ordering. Sparkle orders updates by this numeric build, independently of the displayed version. Both channels share one monotonic build sequence. Keep beta and stable keys in separate Keychain accounts; select the beta account with `SPARKLE_KEY_ACCOUNT`. Use the matching public key in `SPARKLE_PUBLIC_KEY`.

Beta bundles use `https://raw.githubusercontent.com/PinedaTec-EU/LeonardoMD/update-feeds/beta/appcast.xml`, or an explicit `LEONARDO_FEED_URL` HTTPS test endpoint. The feed branch is a publication target, not created by preparation. Beta appcasts mark every item with `sparkle:channel=beta`; stable bundles do not opt into that channel. The verifier rejects prerelease tags in stable feeds. Public beta publication requires a GitHub prerelease (never latest) containing the ZIP, followed by an atomic update of the beta feed branch. Never replace the stable appcast with a beta feed.

`LEONARDO_NOTARIZE=0` permits a **local beta candidate only** when a notarytool profile is unavailable. It remains Developer ID signed and Ed25519 signed; Gatekeeper/notarization acceptance is not claimed. Stable preparation always requires notarization. Preparation verifies archive bytes using Sparkle's `sign_update --verify` after generating the appcast. The scripts do not publish releases, feeds, or tags.

PR #8 is integrated. The implementation is refreshed on current main in PR #17. Keep issue #15 open until the hosted update and relaunch acceptance above is complete.

Release preparation compares the bundle public update key against the existing Keychain signing account before signing or generating release assets. Feed paths must use canonical unescaped URLs; encoded or dot-segment aliases are rejected before bundle metadata changes.
