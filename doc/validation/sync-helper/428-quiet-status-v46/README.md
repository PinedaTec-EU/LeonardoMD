# PR #428 synchronization status evidence — bounded Preferences refresh

- **PR / issue:** [#428](https://github.com/PinedaTec-EU/LeonardoMD/pull/428) / [#421](https://github.com/PinedaTec-EU/LeonardoMD/issues/421)
- **Product source:** `4264d8fb7ee1c1f176ae0f734a28d14637b8a701`
- **Capture surface:** production `SyncHelperPreferencesSection` in native AppKit / SwiftUI `NSHostingView`, synthetic helper state.
- **Environment:** macOS 27.0.1 (Build 26A434), English locale.
- **Viewport:** 532 × 260 native points; output 1064 × 520 pixels.

## Captures

| State | PNG | Context | Metadata | Capture time (UTC) | SHA-256 |
| --- | --- | --- | --- | --- | --- |
| Health check pending; last confirmed green state stays visible with no subtitle. | [PNG](./status-checking.png) | [JSON](./status-checking.context.json) | [JSON](./status-checking.metadata.json) | `2026-11-13T08:39:55.250Z` | `2b4b1b752e17424b798432b47ce8bd1c1901a3ca56a462d65cc5ee744478c015` |
| Health check confirmed; green state and layout remain unchanged. | [PNG](./status-online.png) | [JSON](./status-online.context.json) | [JSON](./status-online.metadata.json) | `2026-11-13T08:39:55.598Z` | `2b4b1b752e17424b798432b47ce8bd1c1901a3ca56a462d65cc5ee744478c015` |
| Confirmed failure; red state and one diagnostic line are shown. | [PNG](./status-error.png) | [JSON](./status-error.context.json) | [JSON](./status-error.metadata.json) | `2026-11-13T08:39:55.952Z` | `0ae329f9905df565d89eb42072d02f3507943f67b02bc3c1d9bda5bc978183dc` |

The checking and online images are byte-identical. The failure capture shows one
diagnostic line. These are native component captures with synthetic state; they
do not claim packaged-app startup or hosted beta installation acceptance.

## Validation

- Focused `SyncHelperControllerTests`: 134 cases, 1 opt-in skip, 0 failures; the new Preferences lifecycle test verifies one initial consent read, one refresh on reopen, no reads after 2.2 seconds without interaction, and a working explicit refresh. The successful compiled run recorded build delta **214**.
- `swift test --disable-automatic-resolution`: 886 XCTest cases (26 opt-in skips), 72 Swift Testing cases, 0 failures; build delta **215**.
- `SyncHelperControllerTests/testStatusIndicatorStatesDuringHealthCheck`: 1 test passed, 0 failures; exact-source capture recorded build delta **216**. The capture was repeated with `EVIDENCE_SHA=4264d8fb7ee1c1f176ae0f734a28d14637b8a701` and `--skip-build` to bind the context to the product source commit.
- `python3 -m unittest discover -s scripts/tests -p 'test_package_user_guide.py'`: 3 tests passed for bundled Guide v68 packaging.
- `git diff --check` and `git diff --cached --check` pass after evidence assembly.

Preferences refreshes linked devices when opened or reopened and through the
explicit **Refresh linked devices** control. The page does not run a periodic
consent read while it remains open. A dismissed alert acknowledges one visible
diagnostic; clearing an action error does not consume a queued polling diagnostic.
