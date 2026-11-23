# Project identity evidence

> The current #400 reconciliation after #408 is recorded in [reconciled-408/README.md](reconciled-408/README.md). The Guide28 and earlier producer evidence below is historical and must not be reused as current candidate acceptance.

Evidence for [issue #399](https://github.com/PinedaTec-EU/LeonardoMD/issues/399) and [PR #400](https://github.com/PinedaTec-EU/LeonardoMD/pull/400). The material documents the native project-role presentation and the bilingual Help examples; it does not claim a physical-device, two-Mac, TestFlight or release validation.

## Role criteria

The same semantic mapping is used on macOS and iOS:

| Role | Base presentation | Meaning |
| --- | --- | --- |
| Local | Project icon, no role indicator | Owned by the device being viewed and not configured to share outward. |
| Shared from this device | Project icon plus people indicator | The source device is configured to share selected content. A receiving device still requires its own invitation and authorization. |
| Received from another device | Project icon plus network indicator | Remote from the device being viewed. The source's sharing is implicit; it does not receive a second sharing badge. iOS direct caches remain received while offline. |
| Recovery archive | Project icon, no network or people indicator | Legacy Git content retained as a read-only recovery archive. It does not imply a live remote connection. |

Connectivity, synchronization progress, selected-content scope and read-only access are independent states.

## Evidence layout

### Native macOS component

The [macOS component captures](macos/components/) contain eight original PNGs: English and Spanish, light and dark Classic palettes, at 220-point and 540-point widths. Each original JSON is preserved beside its PNG. Canonical shared-schema metadata is under [`macos/components/canonical/`](macos/components/canonical/). The captures show local, outgoing selected-content, received, recovery and child-folder roles from the production AppKit/SwiftUI component at source `490086a6829f30cab3e5a7c6fe6e03a75f90e22d`.

The compact bilingual guide illustrations and their original contexts are in [`macos/guide/`](macos/guide/), with canonical metadata in [`macos/guide/canonical/`](macos/guide/canonical/). They are the native component artwork used by the v28 guide.

### Native iOS component

The [iOS component captures](ios/components/) contain eight original PNGs from `MobileProjectIdentityLabel`: received and recovery roles at iPhone/iPad widths and standard/accessibility Dynamic Type. The test-emitted metadata is preserved beside each PNG; canonical metadata is under [`ios/components/canonical/`](ios/components/canonical/). The primary captures use source `7ce073dfb43ca0317876223e1d98a42115d40075`, which adds the capture timestamp to the test driver while preserving the final application inputs from `490086a6829f30cab3e5a7c6fe6e03a75f90e22d`.

The source test metadata emits `captured_at`; canonical iOS metadata preserves that capture time. Native viewport dimensions are measured in points and explicitly labelled as a native-point equivalent in the shared browser-oriented schema; CSS is not applicable.

### Packaged macOS Help and practice

The [native macOS evidence](macos/native/) contains the original CUA screenshots and context sidecars from the final fresh-process instance for English and Spanish Help: project roles, Mermaid/local-image/math examples, disabled Math fallback, and practice saved/reopened states. Canonical metadata is under [`macos/native/canonical/`](macos/native/canonical/).

These CUA captures were produced from the final native producer `490086a6829f30cab3e5a7c6fe6e03a75f90e22d`. The CUA helper exposed screenshot pixels but no CSS viewport or native-point geometry. Canonical metadata preserves `viewport_css: null` and `native_viewport_points: null` rather than fabricating dimensions; pixel dimensions describe only the image file. The helper/browser-schema limitation is recorded in each canonical sidecar.

Native CUA originals are JPEG bytes. Their initial temporary `.png` suffix was corrected to `.jpg` in this evidence directory; image bytes and hashes are unchanged. Component originals remain PNGs.

The final fresh-process run used PID `14735`, QA bundle `/var/folders/_s/khfztzr97kd4049py5k3zsg80000gn/T/leonardo-native-qa-r8ca7p15/LeonardoMDQA.app`, and bundle identifier `eu.pinedatec.LeonardoMD.qa.f51d503ce01d4af598510e5a53a03e66`. The fresh process opened the synthetic local project. Its real Help menu opened both locales; Mermaid, inline and four display formulas including the tagged equation, charts, tables/role rows and local images were inspected. Both practices were filled, saved, closed and reopened with the original blank `practiceName` restored afterward. Math-disabled fallback, declined recommendations without remembered suppression, restoration of `originalMath=true` and English, normal process quit and disappearance were observed. Compilation was successfully recorded with release delta 8.

[Build inputs and package identity](build-inputs.json) record the full producer SHA, immutable Git object lists/digests, actual executable hashes and guide source/bundle/personal-copy hashes. Both Help copies match their packaged resources byte-for-byte. The native Mac bundle reports version/build `0.3.1113/1113`: this is the unmaterialized baseline of this source PR, not a new release. The local iOS Debug test-host app has no distribution version fields; its source SHA and executable digest identify it.

The Mac package uses producer `490086a6829f30cab3e5a7c6fe6e03a75f90e22d`. The timestamped iOS capture run rebuilt the test-host app at `7ce073dfb43ca0317876223e1d98a42115d40075`, preserving the production input objects from the Mac baseline commit. Its current built and simulator-installed executable hashes match and are recorded in `build-inputs.json`; they supersede the earlier iOS binary hash. The separately recorded `ios_capture_driver` group identifies the timestamp-only test change. Subsequent evidence/accounting-only commits must preserve the recorded input object lists. Recheck each group's `git ls-tree -r HEAD -- <input_scopes>` SHA-256 against `git_ls_tree_sha256` before reusing this mapping.

Representative originals: [Mac narrow Spanish rows](macos/components/project-identities-es-light-220.png), [iPhone received role](ios/components/received-iphone-large.png), [iPhone accessibility size](ios/components/received-iphone-accessibility3.png), [iPad-width accessibility size](ios/components/received-ipad-accessibility3.png), [fresh packaged local header](macos/native/local-project.jpg), [Spanish Help roles](macos/native/help-es-project-roles.jpg).

## Validation observed

| Area | Result |
| --- | --- |
| Full Swift log | `/tmp/leonardo-399-full.log`: 713 XCTest tests, 35 skips, 0 failures; 71 Swift Testing tests, 0 failures. |
| Repository Python suites | 112 tests with 7 skips; Leonardo Format plugin 38 tests; packaging 20 tests passed. |
| iOS simulator | 13 unit tests and 2 Demo UI tests passed on the owned iOS 27 simulator (UDID prefix `DF495415…`); the focused 13-unit run, timestamped native captures and final bilingual Demo UI rerun also passed. |
| Final packaged-process verification | Passed in fresh PID14735; package verification and source/bundle/personal-copy identity are recorded in `build-inputs.json`. English/Math preferences and blank practice names were restored; the process exited normally. |

The primary iOS set came only from `/tmp/leonardo-399-ios-components-timestamped`, with test-emitted capture times and source SHA. Earlier capture directories were not used. The final successful compiler-bearing invocation brought the source PR release delta to 9.
