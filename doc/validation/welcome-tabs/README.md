# Welcome saved-item tabs

Tracking: [#298](https://github.com/PinedaTec-EU/LeonardoMD/issues/298).

Native SwiftUI/AppKit captures from `FavoritesTests.testSavedItemTabsBoundLongListsAndScrollToLastItem`, using synthetic session data. Captured 2026-10-30, macOS, NSHostingView at 760 × 720 points (1520 × 1440 pixels, scale 2). These are view-level captures through XCTest, not a packaged app startup check. The existing user app was left running.

The regression checks both list viewports measure 256 points (five 48-point rows with four 4-point gaps), content extends beyond the viewport, and scrolling reaches the last row. It exercises all favorite categories in English and Spanish, and recent project/workspace lists.

- [Projects, first five rows](tabs-project-en.png)
- [Projects, last five rows after scrolling](tabs-project-en-scrolled.png)
- [Workspaces in Spanish](tabs-workspace-es.png)
- [Documents in Spanish, unavailable-item state](tabs-document-es.png)

Reproduce with `LEONARDO_TABS_CAPTURE=/tmp/leonardo-tabs python3 scripts/compile-and-record.py --pr-number 299 -- swift test --filter FavoritesTests`.

## Provenance refresh

The captures were regenerated at source/build revision `ab5c2cc36e305d5ef9b9a6721e6f3cec2c967bcb` with `LEONARDO_TABS_CAPTURE=/tmp/leonardo-299-provenance-captures python3 scripts/compile-and-record.py --pr-number 299 -- swift test --filter FavoritesTests.testSavedItemTabsBoundLongListsAndScrollToLastItem` (1 test passed). The canonical `capture_metadata.py` helper ran as each PNG was saved. Capture timestamps are the observed PNG-save completion times. Source was clean at capture. The evidence-only follow-up changes captures, this README, sidecars and the successful compilation allocation; production source, tests and build inputs are unchanged from the capture revision. Verify with `git diff ab5c2cc36e305d5ef9b9a6721e6f3cec2c967bcb HEAD -- Sources Tests Package.swift Package.resolved scripts Mobile`.

No browser is involved: browser fields explicitly say not applicable. The schema's `viewport_css` dimensions represent native points for this AppKit capture, as stated in each sidecar. They are not claimed to be browser measurements.

Authoritative hosted CI at capture-source revision (macos-15 / Xcode 26.3, `swift test`) reports 537 XCTest tests, 15 skipped, zero failures, and 65 Swift Testing tests in 8 suites. The separate local full run (macOS 27 / Xcode 27) reports 537 XCTest tests, 23 skipped, zero failures, and 65 Swift Testing tests (37 + 28 across targets). The former author summary mistakenly counted only the final 28-test target; the PR evidence corrects it. CI on the evidence-only head must also pass before merge.

| Capture / sidecar | UTC capture time | Bitmap | SHA-256 |
|---|---|---|---|
| [tabs-project-en](tabs-project-en.png) / [JSON](tabs-project-en.metadata.json) | 2026-10-30T11:28:01.918292+00:00 | 1520 × 1440 | `d5062758be990a82aa8db82a49e9cad56be824499d9b255cc7d89e0742dd1a2a` |
| [tabs-project-en-scrolled](tabs-project-en-scrolled.png) / [JSON](tabs-project-en-scrolled.metadata.json) | 2026-10-30T11:28:02.121477+00:00 | 1520 × 1440 | `a5b7248948479958acbb9ea368d0612e480438285bac7a60a2fc24319e23747d` |
| [tabs-workspace-es](tabs-workspace-es.png) / [JSON](tabs-workspace-es.metadata.json) | 2026-10-30T11:28:03.695460+00:00 | 1520 × 1440 | `37f23b727733a181f223e4a26f8714b2e27db3687c3da5bac6f2214cffcbe426` |
| [tabs-document-es](tabs-document-es.png) / [JSON](tabs-document-es.metadata.json) | 2026-10-30T11:28:02.812258+00:00 | 1520 × 1440 | `30ae39cc2e9cfd15639be77eb0f8b149a97cdb41c32d5480b526e0c15d5fdd8f` |
