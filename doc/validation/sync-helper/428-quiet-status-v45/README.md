# PR #428 synchronization status evidence — integrated Guide v68 candidate

- **PR / issue:** [#428](https://github.com/PinedaTec-EU/LeonardoMD/pull/428) / [#421](https://github.com/PinedaTec-EU/LeonardoMD/issues/421)
- **Product source:** `29759ce4f4027b4f2e22c44ee7ea17c48d7eb4d8`
- **Capture surface:** production `SyncHelperPreferencesSection` in native AppKit / SwiftUI `NSHostingView`, synthetic helper state.
- **Environment:** macOS 27.0.1 (Build 26A434), English locale.
- **Viewport:** 532 × 260 native points; output 1064 × 520 pixels.

## Captures

| State | PNG | Context | Metadata | Capture time (UTC) | SHA-256 |
| --- | --- | --- | --- | --- | --- |
| Health check pending; last confirmed green state stays visible with no subtitle. | [PNG](./status-checking.png) | [JSON](./status-checking.context.json) | [JSON](./status-checking.metadata.json) | `2026-11-13T08:14:22.407Z` | `2b4b1b752e17424b798432b47ce8bd1c1901a3ca56a462d65cc5ee744478c015` |
| Health check confirmed; green state and layout remain unchanged. | [PNG](./status-online.png) | [JSON](./status-online.context.json) | [JSON](./status-online.metadata.json) | `2026-11-13T08:14:22.739Z` | `2b4b1b752e17424b798432b47ce8bd1c1901a3ca56a462d65cc5ee744478c015` |
| Confirmed failure; red state and one diagnostic line are shown. | [PNG](./status-error.png) | [JSON](./status-error.context.json) | [JSON](./status-error.metadata.json) | `2026-11-13T08:14:23.074Z` | `0ae329f9905df565d89eb42072d02f3507943f67b02bc3c1d9bda5bc978183dc` |

The checking and online images are byte-identical. The failure capture also
verifies the generic offline message is not repeated as a second detail line.
The fixture captures a native component with synthetic state; it does not
claim packaged-app startup or hosted beta installation acceptance.

## Validation

- `LEONARDO_SYNC_STATUS_EVIDENCE=... python3 scripts/compile-and-record.py --pr-number 428 -- swift test --disable-automatic-resolution`: full Swift suite passed; the command recorded build delta **212**. The opt-in status test captured all three states above.
- `python3 -m unittest discover -s scripts/tests -p 'test_package_user_guide.py'`: 3 tests passed for bundled Guide v68 packaging.
- `git diff --check` and `git diff --cached --check` pass after evidence assembly.

The layout keeps its reserved row height during health checks. Healthy status
polling remains throttled; errors stay visible until a successful recovery.
