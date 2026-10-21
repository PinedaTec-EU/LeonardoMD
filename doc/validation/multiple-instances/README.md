# macOS multiple-instance validation

Tracking: [#263](https://github.com/PinedaTec-EU/LeonardoMD/issues/263), [PR #264](https://github.com/PinedaTec-EU/LeonardoMD/pull/264).

## Automated coverage

`InstancePolicyTests`, `SingleInstanceTests`, `ProcessFileLockTests` and
`ConfigurationStoreTests` cover default-off preferences, the two launch gates,
principal election and forwarding, overlapping trees, aliases including new
files, abandoned claim recovery, a separate OS process holding/releasing a lock,
independent preference/recents merges and additional-instance service guards.

The full local suite passed: 471 XCTest cases (14 optional skips) plus 63 Swift
Testing cases, zero failures. Native component capture was enabled. The source
PR's current-head CI is the authoritative reproducible record; captures are in
its `preview-tags-<SHA>` artifact under `instances/` with their own provenance.

## Preference captures

The four committed PNGs render the actual `InstancePreferencesView` with the
native premium switch style, in English and Spanish, off and on. They use
isolated UserDefaults fixtures in a 532×220 point NSHostingView at 2× scale.
They show layout/localization and do not establish packaged-process startup,
Finder routing or a service installation. The CI capture reruns at its exact SHA.

## Packaged-process QA

Use `LEONARDO_SOURCE_PR=264 ./launch.sh --qa`. Inspect the executable with
`scripts/qa-bundle.py` and verify a new PID and actual first-window readiness.
Keep the canonical product service identity across disposable bundle identities.
Do not terminate a pre-existing user app without authorization.

The process exercise uses only synthetic Markdown documents. Check disabled
New instance, opt-in → New instance, Finder delivery to an additional process,
rejection of a reserved document, opening a distinct document, and election after
principal exit. Preserve the normal preference value after the exercise.
