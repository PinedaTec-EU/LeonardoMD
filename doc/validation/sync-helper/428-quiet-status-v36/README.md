# Synchronization recovery evidence — v36

These six native AppKit/SwiftUI captures were produced by the two checked-in
`SyncHelperControllerTests` regressions from product and test source commit
`843c54baf6263cb672e9c130a31b4db9ce004c38`. The shared capture metadata helper
collected each sidecar from that same clean checkout; every sidecar records the
same source revision with no tracked or untracked changes. The images use
synthetic peer and project data. They show native components hosted by
`NSHostingView`, not a browser or a packaged-app window.

During a cancelled health check and while a helper renewal is pending, the
previously confirmed green status remains visually steady. The English and
Spanish incoming-proposal rows and pairing-consent actions remain present while
their peer actions stay disabled until live helper health returns. The
regressions also assert that the same-endpoint invitation URL, consent rows and
incoming proposal survive the retry and remain after recovery; a separate
terminal-failure assertion confirms that obsolete sharing and its invitation
are cleared after a confirmed failure.

The viewports are native points; there is no browser or CSS viewport. Pixel
dimensions and SHA-256 values come from the generated metadata files.

| State | Capture and provenance | Native viewport; image pixels | Captured (UTC) | SHA-256 |
| --- | --- | --- | --- | --- |
| Last confirmed status after a cancelled health check | [PNG](./status-sharing-cancelled-recovery.png) · [context](./status-sharing-cancelled-recovery.context.json) · [metadata](./status-sharing-cancelled-recovery.metadata.json) | 532×260 pt; 1064×520 px | 2026-11-12T09:03:33.191Z | `3d3505854df2f47ae898a58f1ed03d83ce21a8e78728366d1718f3a8609e480f` |
| Last confirmed status during helper renewal | [PNG](./status-sharing-renewal-pending.png) · [context](./status-sharing-renewal-pending.context.json) · [metadata](./status-sharing-renewal-pending.metadata.json) | 532×260 pt; 1064×520 px | 2026-11-12T09:03:33.526Z | `3d3505854df2f47ae898a58f1ed03d83ce21a8e78728366d1718f3a8609e480f` |
| Incoming proposal action unavailable (English) | [PNG](./incoming-review-unavailable-en.png) · [context](./incoming-review-unavailable-en.context.json) · [metadata](./incoming-review-unavailable-en.metadata.json) | 532×100 pt; 532×100 px | 2026-11-12T09:03:33.857Z | `068eefa7b2ac99a3b5641d8918725a2b5436870cd58129d67f92d183bfd289f8` |
| Incoming proposal action unavailable (Spanish) | [PNG](./incoming-review-unavailable-es.png) · [context](./incoming-review-unavailable-es.context.json) · [metadata](./incoming-review-unavailable-es.metadata.json) | 532×100 pt; 532×100 px | 2026-11-12T09:03:34.530Z | `9a93a098de6bb0934035b866771b31a6048d67eb61b001407cd6dad5f627efba` |
| Pairing consent action unavailable (English) | [PNG](./consent-actions-unavailable-en.png) · [context](./consent-actions-unavailable-en.context.json) · [metadata](./consent-actions-unavailable-en.metadata.json) | 420×60 pt; 840×120 px | 2026-11-12T09:03:34.195Z | `47f0d4b6f5d02b52bf691a1f545fc67de26969fa2cd933a9e432b16e43aad442` |
| Pairing consent action unavailable (Spanish) | [PNG](./consent-actions-unavailable-es.png) · [context](./consent-actions-unavailable-es.context.json) · [metadata](./consent-actions-unavailable-es.metadata.json) | 420×60 pt; 840×120 px | 2026-11-12T09:03:34.859Z | `fe90ebdff440fec9974e114becd9708b18383ec0e56171985a285271f815474b` |

Validation on the captured source: `SyncHelperControllerTests` passed 125 cases
with one opt-in capture skipped; the full suite passed 504 XCTest cases with 35
opt-in skips, 44 Swift Testing cases in 7 suites and 28 package tests in 2
suites. No test failed. The focused two regression tests were then rerun with
capture output enabled and both passed. Build delta for PR #428 is 167.

These captures and tests do not establish packaged-app startup, Developer ID
helper acceptance, or hosted beta installation, update and relaunch.
