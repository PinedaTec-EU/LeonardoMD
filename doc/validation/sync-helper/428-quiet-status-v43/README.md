# Synchronization Preferences captures — v43

- **PR / issue:** [#428](https://github.com/PinedaTec-EU/LeonardoMD/pull/428) / [#421](https://github.com/PinedaTec-EU/LeonardoMD/issues/421)
- **Capture source:** `2c59e4af16b2d96a3fed58c692a0faba1bbe3110`
- **Capture surface:** native AppKit / SwiftUI `NSHostingView`, synthetic helper state; no browser engine.
- **Environment:** macOS 27.0.1 (Build 26A434), English locale.
- **Viewport:** 532 × 260 native points; output 1064 × 520 pixels.

## Captures

| State | PNG | Context | Metadata | Capture time (UTC) | SHA-256 |
| --- | --- | --- | --- | --- | --- |
| A health check is pending; the last confirmed running indicator remains visible. | [PNG](./status-checking.png) | [JSON](./status-checking.context.json) | [JSON](./status-checking.metadata.json) | `2026-11-12T22:35:19.463Z` | `3d3505854df2f47ae898a58f1ed03d83ce21a8e78728366d1718f3a8609e480f` |
| The helper health check has returned successfully. | [PNG](./status-online.png) | [JSON](./status-online.context.json) | [JSON](./status-online.metadata.json) | `2026-11-12T22:35:19.799Z` | `3d3505854df2f47ae898a58f1ed03d83ce21a8e78728366d1718f3a8609e480f` |

The identical images show no temporary gray state, subtitle or layout shift.
They capture the production `SyncHelperPreferencesSection` in a native
component host, not a packaged application or hosted beta.

## Validation

The capture test runs against the reconciled source above and writes original
PNG/context pairs before the shared helper generates the hash-bound metadata:

```sh
EVIDENCE_SHA=2c59e4af16b2d96a3fed58c692a0faba1bbe3110 \
LEONARDO_SYNC_STATUS_EVIDENCE="$PWD/doc/validation/sync-helper/428-quiet-status-v43" \
  python3 scripts/compile-and-record.py --pr-number 428 -- \
  swift test --disable-automatic-resolution \
  --filter SyncHelperControllerTests/testStatusIndicatorStatesDuringHealthCheck
```

Result: **1 test passed, 0 failures**; the successful command is recorded as
build delta **190**. The full reconciled suite at the preceding source commit
passed 507 XCTest (35 optional skips), 44 Swift Testing tests and 28 package
tests. The deterministic bilingual guide package suite also passes (3 tests).

The capture fixture embeds only `SyncHelperPreferencesSection` and synthetic
controller state. The integration merge changes unrelated editor search,
shared Preferences composition and bundled help, so this recapture uses the
integrated source instead of carrying forward the older v42 pixels. Later
evidence-only changes to the PR do not alter product code or build inputs.
`launch.sh --qa` packaged the real app executable and passed static bundle
inspection, but the product-wide instance owner prevented a fresh candidate
process. First-window readiness and the complete English/Spanish packaged Help
smoke remain pending.
