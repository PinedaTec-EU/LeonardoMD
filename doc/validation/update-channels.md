# Update channel validation

Tracking: [#123](https://github.com/PinedaTec-EU/LeonardoMD/issues/123), [PR #124](https://github.com/PinedaTec-EU/LeonardoMD/pull/124).

## Local checks

- Full Swift test run: 352 XCTest cases, zero failures, nine optional skips locally with captures enabled. CI may skip an additional platform-dependent native case; report its own count separately rather than copying the local count. The Updates native capture case ran with `LEONARDO_UPDATE_EVIDENCE` set; other device/runtime opt-in cases remain skipped.
- `scripts/tests`: 24 cases, zero failures, seven private-engine cases skipped without `LEDGER_ENGINE_ROOT`.
- `Tests/Packaging`: 20 cases, zero failures, including both channel trust roots, subscription defaults, atomic mixed-feed composition, canonical encoded-tag/path rejection and negative inputs. A separate-process preferences read plus a reconstructed driver proves durable pending-decision recovery; offline errors preserve it and completed builds/no-update/skip resolve it.
- Real macOS development packaging passed `build-app.sh` and `qa-bundle.py --verify-only`: real LeonardoMD executable, packaged resources/frameworks, local signature, no XCTest linkage. Packaged numeric version remains the current ledger checkpoint; source PR compilation deltas are recorded in `deploy/version/entries/124.yaml`, not materialized manually.

The optional native capture harness renders isolated `NSHostingView` fixtures in English and Spanish for stable, beta, waiting for stable, active check, deferred download, unconfigured development and startup failure. It uses a test-only driver and isolated updater defaults, never network/installation or a replacement of the owner's app. The full Preferences fixture is 580×620 points; the Updates component fixture is 532×550 points with the same appearance/button styles.

CI exports these captures under `updates/` in its `preview-tags-<head SHA>` Actions artifact, alongside the existing renderer captures. `updates/provenance.txt` binds the exact checked-out PR head, route, viewports, languages and states. Full-view bitmap captures cannot rasterize the native glass tab bar reliably (black compositor pixels); inspect component captures for the changed form. A native hosting capture is not evidence of fresh packaged startup or physical user interaction. Screen Recording and CUA cannot inspect the standalone XCTest runner in this session; no permissions were changed and no test executable was put inside an `.app`.

For a compiling capture run use the existing recorder with the PR number:

```bash
LEONARDO_UPDATE_EVIDENCE=/tmp/leonardo-update-evidence python3 scripts/compile-and-record.py --pr-number 124 -- swift test --filter UpdatePreferencesVisualTests
```

The currently running owner application retains product-wide single-instance ownership. Fresh packaged first-window readiness was not tested; do not infer it from packaging or forwarding to that instance.

## Publication acceptance

The [release contract and channel matrix](../releases.md#channel-acceptance-matrix) separate local policy/metadata checks from actual signed hosted checks, install, quit cancellation and relaunch. This PR does not publish feeds, release tags or archives, replace the installed legacy beta, or claim that its unpublished feed is reachable. Hosted acceptance remains in [#15](https://github.com/PinedaTec-EU/LeonardoMD/issues/15) and legacy beta-feed recovery in [#84](https://github.com/PinedaTec-EU/LeonardoMD/issues/84).

The existing stable public key is retained in both new channels. Legacy beta packages with a different key require manual signed/notarized replacement with preferences and documents preserved. Publication operators must keep stable-only and combined beta feeds isolated, verify archive bytes under the common key before composition, and refresh beta's stable entries after each stable publication.
