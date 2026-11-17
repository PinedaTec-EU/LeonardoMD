# PR #465 · Little Leonardo extensions

These are implementation-owned captures from the packaged iOS app, exported
from the passing `MobileDemoUITests.testOfflineDemoRendersAndRetainsPracticeAcrossRelaunch`
run. The UI test used the iPhone 17 Simulator on iOS 27.0 (build 24A434), at
402 × 874 points / 1206 × 2622 pixels. The screenshots are reduced to 828 ×
1800 JPEGs for review; the unmodified XCTest PNG attachments remain in its
result bundle.

The native route is **Library → Demo, Local → Demo-en.mdlr**. Extension settings
are at **Library → Sync settings → Document extensions**. The preview is the
app's WKWebView; there is no external browser. Demo images, chart data and
citations are bundled locally.

| Capture | State |
| --- | --- |
| [Extension settings](ios-extension-settings.jpg) | Five independent device-local switches enabled; the reset control is visible. |
| [Recommendation](ios-extension-recommendation-en.jpg) | Demo opened with all five extensions disabled; the grouped consent dialog offers the detected extensions. |
| [Cover and table](ios-demo-cover-table.jpg) | Demo's bundled local image and Markdown table render in the preview. |
| [Mermaid, math and chart](ios-demo-mermaid-math-chart.jpg) | Enabled Mermaid flowchart, inline/display equations, tagged equation (1), and Vega-Lite chart. |
| [Citations and extras](ios-demo-citations-extras.jpg) | Local chart, bibliography, footnote and GitHub-style callout. |
| [Practice form](ios-demo-practice-form.jpg) | Local form after the test saved fictional practice data. |
| [Spanish Demo](ios-demo-welcome-es.jpg) | Spanish language copy opens separately. |

The run also reopened the saved English practice after terminating and relaunching
the test app, then opened the Spanish copy. The separate passing
`testSpanishSourceRoundTripKeepsFormEditableAndAnswersSeparate` run verified
Spanish source/answer separation and persistence. Both are Simulator checks;
they do not establish physical-device or TestFlight acceptance.

Before the source distribution archive, the PR compilation delta records five
successful compiler-bearing invocations: `swift test`; the two named iPhone 17
UI-test invocations above; `swift build -c release` from `./launch.sh --qa`;
and the focused `swift test --filter
testLinkedDocumentFailureUsesItsDiagnosticPresenter` run below. A full iOS
UI-suite attempt timed out and is not counted. The source archive is a separate
compiler invocation and is recorded only if `xcodebuild archive` succeeds.

## Recorder and ledger regression

The archive preflight initially stopped before Xcode because
`scripts/compile-and-record.py` rejected the nested delta entry used by this
PR and accepted by the pinned ledger engine. No count or archive was produced
by that failed attempt. Issue [#467](https://github.com/PinedaTec-EU/LeonardoMD/issues/467)
tracks the mismatch. The recorder now supports the engine's nested and
top-level segment forms, validates an optional PR identity, preserves summary
metadata, and increments only successful builds.

* `python3 scripts/tests/test_compile_and_record.py`: 9 tests pass, including
  both supported entry shapes, malformed entries, concurrent updates and
  summary preservation.
* `LEDGER_ENGINE_ROOT=<pinned checkout> python3
  scripts/tests/test_release_ledger.py`: 7 tests pass against the pinned
  central engine.

## Hosted linked-document test

The focused linked-document diagnostic test passes locally on macOS 27.0.1,
Xcode 27.1 (one test, 0.710 seconds; recorded as build delta 5). The earlier
PR head `d00d6d804d5285b8f5dda240b95ffa3ec54ba6ec` failed the same assertions in
both the push and pull-request GitHub Actions runs on macos-15/Xcode 26.3. The
linked link is present in the WKWebView DOM, but the diagnostic presenter is
not called on that runner. This CI-specific failure is tracked in
[#468](https://github.com/PinedaTec-EU/LeonardoMD/issues/468); it does not
establish a defect in the packaged app. A correction is pending.

## Packaged macOS Help smoke

Date: 2026-11-17. A fresh `./launch.sh --qa` process built version 0.3.1846
(stable) from the PR worktree. Bundle:
`/var/folders/_s/khfztzr97kd4049py5k3zsg80000gn/T/leonardo-native-qa-dbk3r030/LeonardoMDQA.app`
(bundle ID `eu.pinedatec.LeonardoMD.qa.5f0366a9e8d44917bb1f36ffe9e4de25`),
PID 80640, started at 16:21:56 Europe/Madrid. `CFBundleExecutable` resolved to
the packaged `LeonardoMD`; `otool -L` showed no XCTest framework dependency.
The fresh process opened its initial window. It was gracefully quit after the
smoke; `ps -p 80640` confirmed that the process had exited.

* English: Welcome → **Leonardo user guide…** opened
  `User Guides/v94/en/Guide-v94-en.mdlz`.
* Spanish: after temporarily changing General → On this Mac → Language to
  Español, Help → **Guía de Leonardo…** opened
  `User Guides/v94/es/Guide-v94-es.mdlz`. The setting was restored to English
  before quitting.
* With Mermaid, Math and Charts enabled, both packaged guides rendered their
  local cover image, format table, Mermaid flowchart, inline and display math,
  underbraces, radical/arrow/cancellation example, numbered box-counting
  equation (1), and Vega-Lite chart. The equation tag was visible, with no
  literal display delimiters or rendering errors.
* Math was temporarily disabled. The app recommended only the detected Math
  extension; **Not now** left display/inline source notation literal and left
  code examples literal. Math was re-enabled after this check. Initial extension
  preferences were Mermaid on, Math on, Charts on, Citations off and Markdown
  extras on; those values were restored before quitting. Global recommendation
  suppression remained off.
* Opened a disposable copy of the English practice form at
  `/tmp/pr465-macos-smoke.7dJ0D9/practice.mdlr`; filled its text fields and
  checkbox, saved, closed and reopened it. All values persisted. The repository
  practice source was not edited.

This is a native packaged macOS smoke. It supplements the iPhone 17 Simulator
captures above and does not establish physical-device or TestFlight acceptance.

Local reproduction:

```sh
xcodebuild test \
  -project Mobile/LittleLeonardo.xcodeproj \
  -scheme LittleLeonardo \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=27.0' \
  -only-testing:LittleLeonardoUITests/MobileDemoUITests/testOfflineDemoRendersAndRetainsPracticeAcrossRelaunch
```
