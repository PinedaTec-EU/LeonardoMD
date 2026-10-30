# Welcome saved-item tabs

Tracking: [#298](https://github.com/PinedaTec-EU/LeonardoMD/issues/298).

Native SwiftUI/AppKit captures from `FavoritesTests.testSavedItemTabsBoundLongListsAndScrollToLastItem`, using synthetic session data. Captured 2026-10-30, macOS, NSHostingView at 760 × 720 points (1520 × 1440 pixels, scale 2). These are view-level captures through XCTest, not a packaged app startup check. The existing user app was left running.

The regression checks both list viewports measure 256 points (five 48-point rows with four 4-point gaps), content extends beyond the viewport, and scrolling reaches the last row. It exercises all favorite categories in English and Spanish, and recent project/workspace lists.

- [Projects, first five rows](tabs-project-en.png)
- [Projects, last five rows after scrolling](tabs-project-en-scrolled.png)
- [Workspaces in Spanish](tabs-workspace-es.png)
- [Documents in Spanish, unavailable-item state](tabs-document-es.png)

Reproduce with `LEONARDO_TABS_CAPTURE=/tmp/leonardo-tabs python3 scripts/compile-and-record.py --pr-number 299 -- swift test --filter FavoritesTests`.
