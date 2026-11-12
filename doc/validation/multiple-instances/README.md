# macOS multiple-instance validation

Tracking: [#263](https://github.com/PinedaTec-EU/LeonardoMD/issues/263), [PR #264](https://github.com/PinedaTec-EU/LeonardoMD/pull/264).

## Automated coverage

`InstancePolicyTests`, `SingleInstanceTests`, `ProcessFileLockTests` and
`ConfigurationStoreTests` cover default-off preferences, the two launch gates,
principal election and forwarding, overlapping trees, aliases including new
files, abandoned claim recovery, a separate OS process holding/releasing a lock,
independent preference/recents merges and additional-instance service guards.

The final full local suite passed: 472 XCTest cases (22 optional skips) plus 63
Swift Testing cases, zero failures. The preceding capture-enabled run covered 471
XCTest cases (14 optional skips) plus the same 63 Swift Testing cases. The source
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

### Recorded packaged run (2026-10-21)

Product source: `3b83d2bef1d8bda4f8ce2b433f5e297b95b1da4a` (subsequent
validation-document edits do not change the executable). Packaged version/build:
0.1.612 / 612, pending PR-owned compilation deltas not yet materialized.
`qa-bundle.py --verify-only` verified the real LeonardoMD executable, no XCTest
linkage, the bundle signature and byte-identical packaged release changes.

- Principal PID 18338 reached a real window. New instance was disabled by default.
- Enabling the preference and choosing File → New instance created PID 19931 with
  `--new-instance`, while PID 18338 stayed alive. The blank temporary additional
  process was terminated as a process-exit recovery exercise.
- A second disposable bundle identity started additional PID 20386. Opening
  `principal.md` through its own native Open panel showed the ownership conflict
  sheet; `additional.md` opened successfully. The Updates tab explained principal
  ownership instead of showing update controls.
- Disabling the preference left both processes alive; a new explicit launch
  forwarded and exited, leaving the same two PIDs.
- A Finder-style open delivered to the additional bundle opened `recovery.md` in
  the principal (its native window and selected tab were inspected).
- After normal termination of PID 18338, the same request to PID 20386 elected it
  principal and opened `recovery.md`, retaining `additional.md`. This also proved
  release of the former principal's document/cache reservations.
- Preference restored off; disposable processes closed; original fixture files
  remained unchanged. Existing app closure used the owner's explicit permission.

Native window/panel/alert content was inspected through macOS accessibility.
Committed PNGs are the separately described component evidence; no unsupported
claim of full-window screenshot capture is made.

Packaged executable SHA-256: `1b062c70759a731c074114a65db279adc94a3890d1e867f912ef927da9081b49`.

After refreshing onto main `785cf1a`, the full suite passed again (471 XCTest cases, 22 optional skips without capture mode, plus 63 Swift Testing cases). A rebuilt real QA bundle from product-source commit `7e4d4d9592d0ad177b3ee900708583ced70f7652` reached its first window and closed normally. Its executable SHA-256 is `6bb1a83b3b56c1ded41c85f2729e25086b1315ad4d72fbf082f581002c7f270c`. This refresh adds the independent hover-row change from main; no multi-instance behavior changed.

Final case-alias regression: `InstancePolicyTests.testCaseAliasesReserveTheSameExistingAndFuturePaths` passed on the case-insensitive local volume. The final release executable built from product source `7f278ab74236353aec20d0c123f3148f7e0e70b3` reached a fresh native first window and closed normally. Its SHA-256 is `cbf63d3de73cd9538f43c972890ac700f86dd29f6d000938b4234c5eb03de052`.
