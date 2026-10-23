# Application updates

`ApplicationUpdates.shared` exposes an observable application-wide subscription and Updates preferences tab. `SparkleUpdateDriver` bridges Sparkle 2.9.6/KVO, feeds and allowed channels; Sparkle persists check preferences and last-check date. No matching public signing key means an explanatory disabled development state in Preferences. Primary instances alone start Sparkle; installation uses the application termination guard covering all document tabs.

`scripts/configure-update-bundle.py` validates version/channel, positive numeric build and HTTPS feed. `prepare-release.sh` embeds helpers, signs inside out, notarizes and generates signed assets; beta-only local candidates may explicitly skip notarization. `verify-update-archive.py` checks real archive bytes with Sparkle. Beta and stable share one increasing build sequence and the existing stable Keychain key. Separate feeds remain: beta subscriptions require a combined stable+beta appcast prepared atomically by `compose-beta-appcast.py`. Stable is the default even in beta packages; user choice persists independently of installed maturity. Active Sparkle sessions and a durable pending-update decision guard block channel changes across relaunch; stable selection never downgrades. Old different-key beta packages require manual signed/notarized replacement. See [release contract](../doc/releases.md). Published packages and working owner-confirmed update detection/installation are established; remaining matrix acceptance stays in [#15](https://github.com/PinedaTec-EU/LeonardoMD/issues/15). The [Preferences-sheet termination limitation #202](https://github.com/PinedaTec-EU/LeonardoMD/issues/202) can keep the old instance open; closing Preferences and normal Quit completed the recorded 445 → 461 transition. The owner's 2026-10-20 report reconfirms installation, without adding exact-build matrix evidence.

Appcast CLI arguments are constructed in `generate-release-appcast.sh` with a nonempty array for system Bash 3.2 compatibility; stable/beta and invalid-channel subprocess regressions cover [#44](https://github.com/PinedaTec-EU/LeonardoMD/issues/44).

Stable appcasts must omit explicit channel tags; known stable/beta feed URLs cannot be assigned to the opposite bundle channel. Negative regressions track [#45](https://github.com/PinedaTec-EU/LeonardoMD/issues/45).

Release preparation compares the bundle public update key against the existing Keychain signing account before signing or generating release assets. Feed paths must use canonical unescaped URLs; encoded or dot-segment aliases are rejected before bundle metadata changes.

Owner convention (#53): visible and packaged versions are numeric `release.feature.build` for every channel. Channel identity stays in updater/feed metadata; beta/alpha suffixes are rejected.

PR #54 also restores marker-stripping protection with mandatory internal publication-channel metadata; regression tracked by #72 (https://github.com/PinedaTec-EU/LeonardoMD/issues/72).

Channel acceptance matrix and publication/key recovery contract: [releases](../doc/releases.md), tracking [#123](https://github.com/PinedaTec-EU/LeonardoMD/issues/123). Local policy/capture evidence does not prove hosted install/relaunch or resolve #15/#84.

Follow-up regressions: durable decision recovery [#125](https://github.com/PinedaTec-EU/LeonardoMD/issues/125), canonical archive URL/tag identity [#126](https://github.com/PinedaTec-EU/LeonardoMD/issues/126). The guard resolves on a completed/superseding build or explicit/confirmed Sparkle resolution; transport errors preserve it.

Owner publication policy: accepted PR → published/validated beta → stable with the exact accepted tag/version/build/SHA and ZIP, selected by the explicit central promotion event. This supersedes the former higher-build promotion rule without rewriting published history; tracking [#236](https://github.com/PinedaTec-EU/LeonardoMD/issues/236). The local [release skill](../.skills/leonardo-release/SKILL.md) permits a candidate-scoped explicit owner exception to beta, recorded with missing evidence and residual risk; other technical gates remain. This policy change grants no current publication or merge authorization.

Release-only promotions use `.github/workflows/promote-beta.yml` to dispatch an exact beta tag/SHA, structured owner acceptance URL and request ID to the trusted central promoter. It verifies accepted hashes, pinned Sparkle signature and packaged identity before changing feeds/release metadata; no promotion-only source delta or compilation. Later beta entries survive and keep their higher build, preventing automatic downgrade. Original embedded beta metadata remains package provenance. Historical PR-numbered promotion inputs remain immutable. Tracking: [#236](https://github.com/PinedaTec-EU/LeonardoMD/issues/236); central exact-artifact promotion is active.

About and the footer share `ApplicationUpdates.versionDisplayText`: numeric version plus verified installed maturity, falling back to embedded `LeonardoUpdateChannel` (development fallback), independent of subscription choice. Internal build remains available to update decisions. Tracking: [#142](https://github.com/PinedaTec-EU/LeonardoMD/issues/142).


Installed publication maturity ([#257](https://github.com/PinedaTec-EU/LeonardoMD/issues/257)) is modeled by `InstalledReleaseMaturity`,
independent of `ApplicationUpdates.channel` and immutable bundle provenance.
The owner Mac signs a per-tag `maturity/v<VERSION>.json` on `update-feeds` after stable promotion with
Sparkle's existing Keychain key. The runtime verifies the raw payload's Ed25519
signature using CryptoKit, repository/version/build and executable/resource-seal SHA-256,
reverifies cached evidence on offline startup, and updates all three installed
maturity displays observably. Network/invalid evidence cannot mutate subscriptions
or classify a different build. Linux central promotion alone does not create the
signed proof. No release asset is added, preserving exact-inventory replay; see `doc/releases.md` for the mandatory publication completion step.

#202 candidate: `CoordinatedUpdateUserDriver` awaits normal peer exit before
returning Install for the initial download, so Sparkle's single monitored target
can only be the principal. Automatic downloads are disabled in runtime and bundle
policy; automatic checks retain their normal scheduling. The exclusive launch gate
stays held through download/deferred installation until explicit candidate
resolution or process exit. Cancelling only Quit retains that gate. Concurrent
startup registration uses shared locks. `UpdateInstanceTermination` rejects stale
preflight results if a concurrent cancellation invalidated their gate.

`UpdateQuitEndpoint` requests ordinary local Quit and reports cancellation.
`UpdateProcessIdentity` binds discovery/IPC to PID plus launch date, rejecting
same-PID replacement and missing metadata. The principal's final termination still
uses all document/Git guards and checks for late legacy copies. Preferences window
identity permits selective dismissal while nested decisions remain intact. An
unbound restored installer is skipped without closing peers. Tests cover Sparkle's
first-process monitoring hazard at the user-driver boundary, primary refusal,
startup exclusion, gate lifetime, cancellation, IPC and document/Git safety.
Signed hosted update/relaunch remains pending. See
[issue #202](https://github.com/PinedaTec-EU/LeonardoMD/issues/202) and
[multiple-instance operations](../doc/multiple-instances.md).
