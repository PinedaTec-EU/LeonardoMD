# Synchronization Preferences captures — v42

- **PR / issue:** [#428](https://github.com/PinedaTec-EU/LeonardoMD/pull/428) / [#421](https://github.com/PinedaTec-EU/LeonardoMD/issues/421)
- **Capture and build source:** `95c69884b051273da52e982148289fa191ad972f`
- **Capture surface:** native AppKit / SwiftUI `NSHostingView`; synthetic helper state; no browser engine.
- **Capture environment:** macOS 27.0.1 (Build 26A434), English locale.
- **Viewport:** 532 × 260 native points; output 1064 × 520 pixels.

## Captures

| State | PNG | Context | Metadata | Capture time (UTC) | SHA-256 |
| --- | --- | --- | --- | --- | --- |
| A health check is pending; the last confirmed running status remains visible. | [PNG](./status-checking.png) | [JSON](./status-checking.context.json) | [JSON](./status-checking.metadata.json) | `2026-11-12T21:38:47.726Z` | `3d3505854df2f47ae898a58f1ed03d83ce21a8e78728366d1718f3a8609e480f` |
| The helper health check has returned successfully. | [PNG](./status-online.png) | [JSON](./status-online.context.json) | [JSON](./status-online.metadata.json) | `2026-11-12T21:38:48.154Z` | `3d3505854df2f47ae898a58f1ed03d83ce21a8e78728366d1718f3a8609e480f` |

The two original PNGs have the same SHA-256. The enable label, retained green
indicator, helper description and following section therefore render identically
while a check is pending and after a healthy result; no gray checking state or
layout shift is shown.

## Validation

The status captures were produced by
`SyncHelperControllerTests/testStatusIndicatorStatesDuringHealthCheck` while
compiling the test bundle from the exact source revision above:

```sh
LEONARDO_SYNC_STATUS_EVIDENCE="$PWD/doc/validation/sync-helper/428-quiet-status-v42" \
  python3 scripts/compile-and-record.py --pr-number 428 -- \
  swift test --disable-automatic-resolution \
  --filter SyncHelperControllerTests/testStatusIndicatorStatesDuringHealthCheck
```

Result: **1 test passed, 0 failures**. The command recorded build delta **187**
in `deploy/version/entries/428.yaml`.

The automatic consent-poll alert regression also passed against that freshly
built test bundle using `swift test --disable-automatic-resolution --skip-build
--filter SyncHelperControllerTests/testConsentFailureChecksHealthOncePerFailureEpisode`
(1 passed, 0 failures). It holds helper recovery pending, verifies no alert-bound
error during the first failed read, checks one persistent report per failure
episode, verifies successful recovery clears only automatic errors, and keeps
explicit-action errors intact. This is controller-state evidence; these two
component images do not depict the consent-poll alert or claim to be screenshots
from a packaged application.

The capture source predates this evidence-only refresh. The reviewed branch head
after the evidence commit differs from the capture/build source only in the
release compilation ledger, validation records and agent-facing wiki; production
and test sources and build inputs are unchanged. The sidecars record the capture
source SHA and the ledger-only tracked change present when metadata was collected.

These are native component captures, so browser inspection is not applicable.
They do not replace the separately recorded packaged Help smoke test, signed
helper acceptance or the required hosted beta install/update/relaunch checks.
Hosted beta acceptance remains pending publication.
