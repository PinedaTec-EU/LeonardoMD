# Window placement validation

Tracking: [issue #259](https://github.com/PinedaTec-EU/LeonardoMD/issues/259), [PR #260](https://github.com/PinedaTec-EU/LeonardoMD/pull/260).

## Automated regression

`swift test --filter WindowFramePersistenceTests` covers first launch, saved size/position, every connected display (including negative coordinates), an unavailable saved display, and an oversized frame after display resizing. The full `swift test` suite passed on the implementation sources. The source PR ledger records successful compiler invocations; failed experiments earn no build delta.

The original `NSWindow.setFrameUsingName` implementation failed the all-display test on two of three equal-sized displays by restoring onto the active display. Persistence now records the CoreGraphics display UUID, frame and screen origin, translates for changed origins, and constrains to the chosen screen's visible frame. This also accommodates Dock/menu-bar reservations.

## Packaged native check

The owner authorized normal termination of the installed app for QA. It exited without an unsaved-changes prompt. `LEONARDO_SOURCE_PR=260 ./launch.sh --qa` built the real app with resources and Sparkle; `qa-bundle.py` verified executable identity, dependencies (no XCTest), and signing before launch. A fresh process displayed its first window and rendered a synthetic Markdown document.

Native Window menu operations moved the actual app between Studio Display and LG HDR 4K (2), and Zoom changed the persisted size from 1260 × 850 to 2560 × 1409. A maximized frame was subsequently constrained for the Dock on restoration; this is not an exact-size comparison case.

For the final reproducible comparison, the isolated QA defaults were seeded once with a 1120 × 720 frame at (-2000, 400) on LG HDR 4K (2). The real app opened it, rendered the synthetic document, closed through its normal close button and exited, and reopened in a different process **without reseeding**. Both captures measure 2240 × 1440 Retina pixels. The persisted placement is identical before and after the close/relaunch; the native Window menu confirms the left-hand display remains selected. See `provenance.json` for display UUID, coordinates, process IDs, executable hash, source tree and capture hashes.

- [Before close](before-close.jpg)
- [After relaunch](after-relaunch.jpg)
- [Restored display menu](restored-monitor-menu.txt)

These are actual packaged-app captures with synthetic document content, not generated UI images. Browser: N/A (native AppKit/WKWebView). Screen: main document preview; viewport: 1120 × 720 points. No runtime source changed between the recorded build and the evidence/ledger commit; compare `runtime_sources_tree` with the reviewed head's `Sources` tree. Packaging uses the materialized baseline version 0.1.606; this is a development QA package, not a new published release.

## Reproduction

Run the focused Swift tests on the reviewed checkout. For packaged interaction, close other LeonardoMD instances normally, run `LEONARDO_SOURCE_PR=260 ./launch.sh --qa`, open a synthetic document, move/resize the window on a connected display, close it and reopen the **same** disposable QA bundle. Creating another QA bundle changes its defaults domain and is not a persistence test. Verify a fresh PID and first-window readiness. Do not launch XCTest as an app or terminate another user's instance.

Disconnected-screen acceptance is an automated persisted-placement fixture, not a physical unplug test. No display settings or physical connections were changed.
