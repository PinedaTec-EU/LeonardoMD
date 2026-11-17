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

Before the source distribution archive, the PR compilation delta records thirteen
successful compiler-bearing invocations: the six listed above; the rebased
`swift test --disable-automatic-resolution`; the focused iPhone 17 UI tests for
the Demo/Help; the earlier packaged macOS build from `./launch.sh --qa`; three
focused English/Spanish frequency-localization `xcodebuild test` invocations;
and the final focused run against the current source. A full iOS UI-suite
attempt timed out and is not counted.
The source archive is a separate compiler invocation and is recorded only if
`xcodebuild archive` succeeds.

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
Xcode 27.1 with the original synthetic DOM click (one test, 0.710 seconds;
build delta 5). The earlier PR head `d00d6d804d5285b8f5dda240b95ffa3ec54ba6ec`
failed the same assertions in both the push and pull-request GitHub Actions
runs on macos-15/Xcode 26.3. The linked link was present in the WKWebView DOM,
but the diagnostic presenter was not called on that runner. Issue
[#468](https://github.com/PinedaTec-EU/LeonardoMD/issues/468) tracks the
hosted-runner failure.

The candidate test now posts the same `leonardoLink` message used by the
production renderer through the registered WKWebView bridge, then verifies the
nested preview and diagnostic presenter. This avoids relying on a synthetic
DOM click while keeping the production renderer, message handler and
navigation path in the test. The revised test passes locally (one test, 0.592
seconds; build delta 6). Exact-head GitHub Actions on macos-15/Xcode 26.3 still
needs to confirm the fix; this test failure does not establish a defect in a
packaged app.

## Packaged macOS Help smoke

Date: 2026-11-17. `./launch.sh --qa` produced a fresh native app with version
0.3.1884 (build 1884), macOS 27.0.1 (26A434), Xcode 27.1 (27A9275). Bundle:
`/var/folders/_s/khfztzr97kd4049py5k3zsg80000gn/T/leonardo-native-qa-cjlxt5nj/LeonardoMDQA.app`
(bundle ID `eu.pinedatec.LeonardoMD.qa.ae4d439124594d638ab21e949f7c91ca`),
PID 98357, started 18:01:50 CET. `CFBundleExecutable` named the real packaged
`LeonardoMD` executable; `otool -L` found no XCTest framework dependency.
The first window reached ready state. The process was gracefully quit after the
smoke and `ps -p 98357` confirmed it had exited. Earlier task-owned launches
93622 (17:57:17 CET) and 96868 (18:00:24 CET) were also closed and verified
exited; all used this same QA bundle path.

The test used `CFFIXED_USER_HOME=/tmp/leonardo-pr465-cfixed-home` so Help copies,
extension preferences and practice answers stayed in an isolated profile. The
real Welcome **Leonardo user guide…** workflow opened English Help, and the
Spanish Help workflow opened **Guía de Leonardo…** after setting the app
language to Español. The fresh user copies at
`User Guides/v94/en/Guide-v94-en.mdlz` and
`User Guides/v94/es/Guide-v94-es.mdlz` matched the packaged candidate resources
exactly (SHA-256 `d70236b6dbc2558af719961a1b9356e0d5012f7633b8f661e0abc5749b68f747`
and `197effc71529dd1c115508f371bdc0c5e2bc787f886ab09b84fb2b7eb3db4f22`).
The pre-existing user guide copies were left untouched.

* With Mermaid, Math and Charts enabled, both packaged guides rendered their
  local cover and diagrams, a Markdown table, Mermaid flowchart, one-line and
  multiline display equations, inline math, underbraces, radical/arrow/cancel
  examples, tagged box-counting equation (1), and a Vega-Lite chart. Equations
  rendered without literal display delimiters or visible KaTeX errors. Fenced
  Mermaid and other code examples remained literal.
* Turning Math off produced a recommendation containing Math only. Choosing
  **Ahora no** kept inline and display source notation visible without parsing
  it. Math was restored before teardown. Final isolated extension state was
  Mermaid on, Math on, Charts on, Citations off, Markdown extras off; global
  recommendation suppression remained off. The app language was Spanish at
  final inspection; the setting lived only in the temporary profile.
* English and Spanish practice forms were copied to
  `/tmp/leonardo-pr465-cfixed-home/QA-practice-en.mdlr` and
  `/tmp/leonardo-pr465-cfixed-home/QA-practice-es.mdlr`. Fictional text and
  checkbox answers were entered, saved, closed and reopened in Fill mode. Each
  reopened form showed all values. The repository practice sources were not
  edited.

This is a native packaged macOS smoke and visual inspection through CUA. It
supplements the iPhone 17 Simulator captures above and does not establish
physical-device or TestFlight acceptance.

This smoke used the earlier Guide v94 packages (EN SHA-256
`d70236b6dbc2558af719961a1b9356e0d5012f7633b8f661e0abc5749b68f747`; ES
`197effc71529dd1c115508f371bdc0c5e2bc787f886ab09b84fb2b7eb3db4f22`). It does
not accept the regenerated packages listed below.

## Frequency localization UI tests

Date: 2026-11-17, Xcode 27.1 (27A9275), iPhone 17 Simulator
(UDID `691F22BD-BD95-40DC-8744-352846B25B84`), iOS 27.0 (24A434), app bundle
`eu.pinedatec.LittleLeonardo`. The final run passed both
`PairingUITests.testEnglishSyncFrequencySettingsAreLocalized` and
`PairingUITests.testSpanishSyncFrequencySettingsRemainLocalized` (2 tests, 0
failures). It checked the section, picker label, helper copy and all six menu
options in both locales without changing the stored interval. Each test also
opened Little Leonardo's integrated bilingual Help, checked the extension-help
section and the new Frequency description, then gracefully terminated its app
process. Xcode confirmed both apps were no longer running; exact result bundle:
`/tmp/LeonardoMD-pr465-frequency-final4-20261117.xcresult`.

The XCTest result identifies task-created Simulator app processes 65742
(English test starting 19:11:52 CET) and 66174 (Spanish test starting
19:12:31 CET), both `eu.pinedatec.LittleLeonardo`; the test target confirmed
their termination. The Simulator was already booted before this run and remains
booted. The frequency screenshots are native XCTest attachments with capture
details and SHA-256 values in [ios-frequency-captures.json](ios-frequency-captures.json).
The same tests opened integrated Help and asserted the new frequency text plus
the document-extension section.

| Capture | State |
| --- | --- |
| [English frequency settings](ios-frequency-english.png) | English section, selected interval and all frequency choices in the native picker. |
| [Spanish frequency settings](ios-frequency-spanish.png) | Spanish section and all six localized choices in the native picker. |

## Refreshed Guide v94 packaged Help smoke — pending

The regenerated candidate packages are EN SHA-256
`0e1b1353b7f9e7811daf14e6c497284ee11b38ff9cf33c6ce72092d29184a9bb` and ES
`ce50a6c316e437a84b74a4bb97522c532624fa04928cddec79acd3703945b8de`. Packaged
Help still needs a fresh native macOS process that opens both package copies.

At the pre-launch process check on 2026-11-17, PID 16139 was already running
`/var/folders/_s/khfztzr97kd4049py5k3zsg80000gn/T/leonardo-native-qa-cjlxt5nj/LeonardoMDQA.app/Contents/MacOS/LeonardoMD`
(QA bundle ID `eu.pinedatec.LeonardoMD.qa.ae4d439124594d638ab21e949f7c91ca`,
build 1884; started 18:21:04 CET). It is not an instance created by this
validation, and LeonardoMD uses product-wide single-instance ownership. It was
left running; no new Help smoke or first-window readiness is claimed for the
regenerated hashes.

## Release cleanup gate

The primary checkout's `main` branch remains one commit behind `origin/main`
and has a pre-existing user modification to `.wiki/document-extensions.md`.
The release-cleanup workflow blocks merge and TestFlight publication until that
checkout is reconciled. This task left the file and branch untouched.

Local reproduction:

```sh
xcodebuild test \
  -project Mobile/LittleLeonardo.xcodeproj \
  -scheme LittleLeonardo \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=27.0' \
  -only-testing:LittleLeonardoUITests/MobileDemoUITests/testOfflineDemoRendersAndRetainsPracticeAcrossRelaunch
```
