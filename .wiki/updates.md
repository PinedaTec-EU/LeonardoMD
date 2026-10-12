# Application updates

`ApplicationUpdates.shared` exposes an observable application-wide subscription and Updates preferences tab. `SparkleUpdateDriver` bridges Sparkle 2.9.6/KVO, feeds and allowed channels; Sparkle persists check preferences and last-check date. No matching public signing key means an explanatory disabled development state in Preferences. Primary instances alone start Sparkle; installation uses the application termination guard covering all document tabs.

`scripts/configure-update-bundle.py` validates version/channel, positive numeric build and HTTPS feed. `prepare-release.sh` embeds helpers, signs inside out, notarizes and generates signed assets; beta-only local candidates may explicitly skip notarization. `verify-update-archive.py` checks real archive bytes with Sparkle. Beta and stable share one increasing build sequence and the existing stable Keychain key. Separate feeds remain: beta subscriptions require a combined stable+beta appcast prepared atomically by `compose-beta-appcast.py`. Stable is the default even in beta packages; user choice persists independently of installed maturity. Active Sparkle sessions and a durable pending-update decision guard block channel changes across relaunch; stable selection never downgrades. Old different-key beta packages require manual signed/notarized replacement. See [release contract](../doc/releases.md). Publication and hosted end-to-end acceptance remain pending for [#15](https://github.com/PinedaTec-EU/LeonardoMD/issues/15), PR #17.

Appcast CLI arguments are constructed in `generate-release-appcast.sh` with a nonempty array for system Bash 3.2 compatibility; stable/beta and invalid-channel subprocess regressions cover [#44](https://github.com/PinedaTec-EU/LeonardoMD/issues/44).

Stable appcasts must omit explicit channel tags; known stable/beta feed URLs cannot be assigned to the opposite bundle channel. Negative regressions track [#45](https://github.com/PinedaTec-EU/LeonardoMD/issues/45).

Release preparation compares the bundle public update key against the existing Keychain signing account before signing or generating release assets. Feed paths must use canonical unescaped URLs; encoded or dot-segment aliases are rejected before bundle metadata changes.

Owner convention (#53): visible and packaged versions are numeric `release.feature.build` for every channel. Channel identity stays in updater/feed metadata; beta/alpha suffixes are rejected.

PR #54 also restores marker-stripping protection with mandatory internal publication-channel metadata; regression tracked by #72 (https://github.com/PinedaTec-EU/LeonardoMD/issues/72).

Channel acceptance matrix and publication/key recovery contract: [releases](../doc/releases.md), tracking [#123](https://github.com/PinedaTec-EU/LeonardoMD/issues/123). Local policy/capture evidence does not prove hosted install/relaunch or resolve #15/#84.

Follow-up regressions: durable decision recovery [#125](https://github.com/PinedaTec-EU/LeonardoMD/issues/125), canonical archive URL/tag identity [#126](https://github.com/PinedaTec-EU/LeonardoMD/issues/126). The guard resolves on a completed/superseding build or explicit/confirmed Sparkle resolution; transport errors preserve it.

Owner publication policy ([#123](https://github.com/PinedaTec-EU/LeonardoMD/issues/123)): accepted PR → published/validated beta → stable from the validated functional source, using a new higher build. The local [release skill](../.skills/leonardo-release/SKILL.md) permits a candidate-scoped explicit owner exception to beta, recorded with missing evidence and residual risk; other technical gates remain. This policy change grants no current publication or merge authorization.
