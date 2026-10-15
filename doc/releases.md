# Signed macOS releases

## Prerequisites

The maintainer needs a Developer ID Application identity, an existing `notarytool` Keychain profile, and a Sparkle Ed25519 signing key in the login Keychain. The stable LeonardoMD Keychain account is `LeonardoMD-stable`; set `SPARKLE_KEY_ACCOUNT=LeonardoMD-stable` and read its public key with `generate_keys --account LeonardoMD-stable -p`. Generate a missing Sparkle key once using `.build/artifacts/sparkle/Sparkle/bin/generate_keys` after resolving the package. Keep the private key and Apple credentials out of the repository and release assets. Back up the key securely. Only its public value is embedded in the app.

Set `LEONARDO_VERSION` to the canonical `release.feature.build` in `version.nfo` and `LEONARDO_BUILD` to its third segment, strictly greater than every previous published build, `SPARKLE_PUBLIC_KEY` to the generated public key, `DEVELOPER_ID_APPLICATION` to the signing identity, `NOTARY_PROFILE` to the stored profile, and `RELEASE_NOTES_FILE` to a nonempty Markdown file. Supply these through the process environment, not tracked files. Ordinary development builds derive their version and build from `version.nfo` (initial seed 0.1.56 / 56) and do not enable the channel.

## Local signing and notarization configuration

Verified on 2026-10-15 for the existing releases on this Mac:

- Developer ID identity: `Developer ID Application: JOSE MANUEL RODRIGUEZ PINEDA (AU2Z3P42U7)`.
- Notarytool Keychain profile: `x-notch-notary`. Despite its historical name, this existing profile is also used for LeonardoMD; `notarytool` resolves it from the current user's Keychain without a `--keychain` override.
- Sparkle signing account: `LeonardoMD-stable`, shared by stable and beta. Read only its public key with the command in Prerequisites.

Set `NOTARY_PROFILE=x-notch-notary` and `DEVELOPER_ID_APPLICATION` to the identity above when invoking `prepare-release.sh`. Verify profile access without exposing credentials:

```bash
xcrun notarytool history --keychain-profile x-notch-notary
```

GitHub beta is a public prerelease plus its subscription feed. Apple notarization is a separate verification of that downloadable macOS package; it is not App Store publication or local installation. Publication does not authorize replacing `/Applications/LeonardoMD.app` or running an update on the owner's Mac. Hosted installation/relaunch acceptance must remain explicitly pending when installation is excluded.

Keep credentials in the Keychain, never in this document or tracked environment files. Tracking: [#15](https://github.com/PinedaTec-EU/LeonardoMD/issues/15).

## Prepare and inspect

Run `./scripts/prepare-release.sh` from the repository. It builds the app, embeds Sparkle including symlinks and executable helpers, signs nested components inside out with hardened runtime, verifies signatures, notarizes, staples, assesses Gatekeeper, then generates the archive and EdDSA-signed appcast. It stops on failure. Release notes are embedded in the appcast. Output is under `output/release-<version>/`. No tag or release is published by this script.

The archive contains only the application. Sparkle infers supported hardware and the minimum OS from the bundle. This script builds for the host architecture; publish only for that architecture until universal builds have been independently validated. Every stable release must include `appcast.xml` and its referenced ZIP, with URLs matching the tag `v<version>`. The bundled feed uses GitHub's latest stable release redirect. Mark experimental releases as prereleases and never promote them as latest. Keep a stable channel available even if a non-app release is created.

Before publishing, inspect the version/build, appcast URLs, release notes and archive contents. Confirm the build is newer than the current stable feed. Publish the ZIP and appcast together in a draft GitHub release and make it public only when complete. GitHub's latest stable release must always have the feed asset. Retain old release ZIPs referenced by prior feeds. This change does not publish a release or provision signing credentials.

## Publication progression and explicit exceptions

The normal publication path is an accepted PR integrated into `main`, followed
by a published, signed and notarized beta with recorded acceptance, and then a
stable promotion. Use the repository-local
[leonardo-release skill](../.skills/leonardo-release/SKILL.md) for these operations.
Record the beta source SHA, version/build, tag, archive digest and actual hosted
update/install/relaunch evidence in the canonical issue before stable promotion.
A local candidate or an unvalidated public beta does not satisfy this stage.
The stable candidate must preserve that validated functional source: ledger
version materialization and channel metadata may change, but functional code or
dependency changes return the candidate to beta. Stable uses a new higher build
and new tag, never a relabeled beta artifact.

The owner may explicitly authorize direct stable publication for a named
candidate or bounded publication request. Record the direct instruction,
candidate identity, skipped beta stage, reason (or explicitly unspecified),
missing acceptance evidence, residual risk and follow-up in the canonical issue
and publication record. This is a one-request exception; an ordinary release or
merge request does not imply it. Do not ask again after a clear instruction.
The exception does not waive PR CI/review, signing, notarization, archive
verification, build ordering, feed isolation or the remaining release acceptance
checks. Changing this policy authorizes no publication or merge.

## Acceptance on a release candidate

Install an older signed app in a writable Applications folder and publish a newer signed candidate on a controlled test feed. Verify manual no-update/error/update dialogs, persisted periodic-check preference, release notes, download, install and relaunch. Edit a document before installation; cancel quit and confirm the draft survives, then save and retry. Confirm Git operations also prevent premature quit. Tamper with the ZIP and confirm signature rejection before extraction; test offline mode and an unsupported architecture. Repeat with the production feed before claiming end-to-end release acceptance.

## Beta candidates

Set `LEONARDO_CHANNEL=beta` while keeping `LEONARDO_VERSION` equal to the numeric canonical version (for example, `0.1.56`) and `LEONARDO_BUILD` equal to its third segment. Do not append beta, alpha or other maturity suffixes: the visible version is identical across channels. Before publishing a later package, materialize a new ledger build greater than every previously published build. Sparkle orders updates by this numeric build. Channel selection belongs only in bundle/feed metadata and GitHub prerelease status, not in version strings. Both channels must now use the existing `LeonardoMD-stable` signing account and stable public key. The public trust root is recorded in `scripts/Info.plist` as `LeonardoUpdatePublicKey`; distribution packaging rejects another key before metadata is written. No new key is generated. Release preparation defaults to `LeonardoMD-stable` and still compares the embedded key with the actual selected Keychain account.

Bundles embed separate stable and beta endpoints. A fresh subscription always selects stable, including inside a beta package; the user can explicitly select beta in Preferences. Beta subscriptions use `https://raw.githubusercontent.com/PinedaTec-EU/LeonardoMD/update-feeds/beta/appcast.xml`. For controlled test endpoints use `LEONARDO_STABLE_FEED_URL` and `LEONARDO_BETA_FEED_URL`; `LEONARDO_FEED_URL` overrides only the packaged channel’s endpoint. The runtime delegate selects the endpoint from the user’s persisted choice. `SUFeedURL` remains stable by default. The feed branch is a publication target, not created by preparation. Generated beta-only release appcasts mark every item with `sparkle:channel=beta`; the stable-only appcast never opts into beta. The published beta subscription appcast combines both kinds without relabeling any entry. The verifier rejects prerelease tags in stable feeds. Public beta publication requires a GitHub prerelease (never latest) containing the ZIP, followed by an atomic update of the combined beta subscription feed. Every stable publication also refreshes the stable entries in that combined feed. Never replace the stable appcast with a beta feed.

`LEONARDO_NOTARIZE=0` permits a **local beta candidate only** when a notarytool profile is unavailable. It remains Developer ID signed and Ed25519 signed; Gatekeeper/notarization acceptance is not claimed. Stable preparation always requires notarization. Preparation verifies archive bytes using Sparkle's `sign_update --verify` after generating the appcast. The scripts do not publish releases, feeds, or tags.

PR #8 is integrated. The implementation is refreshed on current main in PR #17. Keep issue #15 open until the hosted update and relaunch acceptance above is complete.

Release preparation compares the bundle public update key against the existing Keychain signing account before signing or generating release assets. Feed paths must use canonical unescaped URLs; encoded or dot-segment aliases are rejected before bundle metadata changes.

## First stable publication

Stable [0.1.64](https://github.com/PinedaTec-EU/LeonardoMD/releases/tag/v0.1.64) was published on 2026-10-08 from `3aebf4459edfa45c9c45e6a4ea64ac1ac216180d`, canonical version 0.1.64 / build 64. The arm64 application passed Developer ID signature verification, Apple notarization, stapling and Gatekeeper assessment. The release contains the verified ZIP and signed appcast. This proves signed distribution; hosted update/install/relaunch acceptance remains separately tracked in [#15](https://github.com/PinedaTec-EU/LeonardoMD/issues/15).

Every newly generated appcast item carries mandatory internal `leonardo:channel` publication metadata in the `https://pinedatec.eu/xml-namespaces/leonardo` namespace. It must agree with the selected publication channel and Sparkle markers: stable omits `sparkle:channel`, while beta has exactly one `beta` marker. Removing either binding or beta marker fails publication validation. Generation refuses to relabel existing bindings. Regenerate legacy appcasts before validating them with the current tooling. These metadata checks supplement the existing signed archive/key verification; they are not a cryptographic signature of the XML feed.

## User-selected channels and legacy beta migration

Update controls live in Preferences → Updates. Installed package channel and selected subscription are independent. `updateChannel` persists the subscription; `pendingUpdateTargetBuild` is an application-owned durable decision guard, not a scheduling preference. Automatic checks and last-check time remain Sparkle-owned. Channel changes reset Sparkle’s scheduling cycle, preserve the automatic-check choice, and are blocked while an update session is active or a downloaded update is deferred. The guard is persisted before starting a download and recovered before Preferences can change channel after relaunch. Reopen the pending update with Check now and finish or skip it before changing channel; Sparkle can resume a downloaded update without fetching the new feed. Network/installer errors retain the guard. A completed/superseding installed build, an explicit skip, dismissal of a fresh non-downloaded candidate, or a successful no-update check resolves it. Manual checking remains available when Sparkle permits focusing an existing update. Automatic checks begin disabled; downloading/installing automatically is disallowed.

Both new channels retain the stable Ed25519 trust root already embedded in stable 0.1.64. There is no stable-user key rotation. Existing beta packages with the old beta key (including the installation diagnosed in [#84](https://github.com/PinedaTec-EU/LeonardoMD/issues/84)) must install a new Developer ID signed and notarized package manually. Preserve the same bundle identity and user preferences; never remove application data or rewrite the installed bundle’s key/feed. A bridge signed with the old beta key would be a separate migration requiring its own hosted acceptance; this change does not publish one.

Use short-lived issue branches from main for code. Stable and beta are publication channels, not long-lived divergent code branches. Tags identify immutable numeric builds. Promoting tested beta code means publishing a new higher-build stable package from that source lineage; do not reuse the beta tag/build or relabel an existing appcast item.

## Combined beta subscription feed

After verifying each input release’s archive signatures with the common signing account, prepare the subscription artifact with:

```bash
python3 scripts/compose-beta-appcast.py --stable /path/to/stable/appcast.xml --beta /path/to/beta/appcast.xml --output /path/to/subscription/appcast.xml
```

The helper validates the stable-only and beta-only publication bindings, signatures’ shape, archive URLs, positive lengths and numeric builds, then sorts all entries by build and atomically replaces its output. It preserves each enclosure, signature, release notes, compatibility metadata and channel marker. It rejects missing/malformed feeds, marker stripping, duplicate builds/tags (including encoded aliases), noncanonical archive paths and overwriting either input. Validation and duplicate detection share the canonical release-tag parser. It does **not** download archives or cryptographically verify their bytes; run `verify-update-archive.py` on the original feeds and corresponding downloaded archives first. Its synthetic regression signatures prove feed structure only.

Publish the combined result at `update-feeds/beta/appcast.xml` only after the referenced public archives exist and are verified. Publish both initial feeds before installing a beta-capable distribution with automatic checks enabled. Refresh the combined feed after either channel publishes. Probe both actual bundled HTTPS endpoints from a clean installation; a build, local composition or launch is not proof of feed reachability. A beta feed with no beta releases can initially mirror the verified stable-only feed; do not fabricate a beta entry. The composition helper is used once beta-only inputs exist. Do not replace stable’s appcast with the combined subscription feed. If feeds themselves carry optional XML signatures, sign the composed feed again after composition.

## Channel acceptance matrix

Tracking: [#123](https://github.com/PinedaTec-EU/LeonardoMD/issues/123). Run hosted rows with real signed/notarized archives and the exact candidate build; keep evidence separate from local policy tests.

| Starting installation / choice | Candidate | Required result | Local coverage / hosted evidence |
| --- | --- | --- | --- |
| Stable / Stable | Newer beta | No beta offered | Stable-only feed validation and delegate allowed-channel tests; actual hosted check required |
| Stable / Beta | Newer beta | Beta offered; install only on user action | Choice/feed/combined metadata tests; signed install and relaunch required |
| Beta / Beta | Newer beta | Newer beta offered | Shared build ordering and combined-feed tests; signed install and relaunch required |
| Beta / Beta | Newer stable | Stable offered with beta subscription retained | Stable entries preserved in combined-feed tests; hosted promotion required |
| Beta / Stable | Stable build ≤ installed beta | No downgrade; Preferences explains waiting | Sparkle comparator, independent subscription/package state and native captures; hosted no-update required |
| Beta / Stable | Stable build > installed beta | Stable offered; stable subscription retained | Stable delegate feed/channel and comparator tests; signed install and relaunch required |
| Either / Either | Tampered ZIP or wrong update key | Reject before extraction | Distribution key mismatch and archive-verifier regressions; real tamper test required |
| Either / Either | Offline, HTTP 404 or no newer version | Clear Sparkle result; editor remains usable | Missing/malformed feed regressions; real offline/HTTP/no-update dialogs required |
| Either / Either | Change channel during a check/download/prompt or deferred download | Selection disabled until session finishes or is cancelled | Live driver session/deferred-download gate regressions and native busy/deferred captures |
| Either / Either | Restart with a deferred update, or successful install | Channel/decision guard, automatic checks, documents and settings survive; completed target clears the guard | External-process defaults read plus reconstructed-driver gating, installed-build/no-update resolution and Sparkle-owned preference tests; hosted unsaved/Git quit-cancel and relaunch required |
| Development / Either | No configured signature trust | Check/automatic controls disabled with explanation | Unconfigured model and native capture tests |
| Legacy beta / Either | Different old beta trust root | Manual signed/notarized replacement; preserve data | Documented recovery; not an automatic key migration |

Publication operators must record URLs, source/build, installed and target channels, signature/notarization checks, selected subscription, check mode, result and relaunch/document evidence for each hosted transition. [#15](https://github.com/PinedaTec-EU/LeonardoMD/issues/15) and [#84](https://github.com/PinedaTec-EU/LeonardoMD/issues/84) remain separate hosted acceptance/publication work; local tests do not close them.
