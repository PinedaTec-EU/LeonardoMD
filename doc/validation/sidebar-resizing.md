# Project sidebar resizing

Tracking: [#86](https://github.com/PinedaTec-EU/LeonardoMD/issues/86), PR #87.

`WorkspaceView` uses a native `HSplitView`, with a 220–600-point sidebar (ideal 250) and a 440-point document-pane minimum. Standalone and focus mode omit the outer split; the inspector remains within the document pane.

`SidebarLayoutTests` hosts the real SwiftUI workspace in an AppKit window with an isolated project, preferences and synthetic Markdown. It sends native mouse-down, drag and mouse-up events directly to the split view. Assertions verify expansion to 500 points, reduction to 230 points, minimum/maximum constraints, document minimum, focus mode and standalone layout. Three captures show the wide, narrow and focus states. Browser: N/A (native AppKit). Viewport: 1260 × 850 points, images 2520 × 1700 pixels. Captured on 2026-10-09; runtime and test source match this PR's final source.

Reproduce the native interaction and optionally export captures:

```sh
LEONARDO_SIDEBAR_EVIDENCE=/tmp/sidebar-evidence swift test --skip-build --filter SidebarLayoutTests
```

Use `python3 scripts/compile-and-record.py --pr-number 87 -- swift test` first if this checkout has not been built. The complete suite and native interaction test passed locally. The ledger records five successful compiling commands: initial full tests, release packaging, native layout test, native drag test, and final full tests. Failed commands do not increment the ledger.

This is supported XCTest-runner QA, not a test executable packaged as an app. It neither acquires the product single-instance endpoint nor terminates the owner's app. Fresh-process startup was not repeated because that process is running; the PR changes no startup or ownership code. Release packaging and QA executable/dependency checks passed separately.
