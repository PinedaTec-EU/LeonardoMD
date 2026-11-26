# PR #465 · Little Leonardo extensions

These are historical implementation-owned captures from the packaged iOS app,
exported before the PR was reconciled onto current `main`. They are retained
for provenance only; the capture/UI-test sources that produced them are not
part of the reconciled candidate. The original run used
`MobileDemoUITests.testOfflineDemoRendersAndRetainsPracticeAcrossRelaunch`
on an iPhone 17 Simulator on iOS 27.0 (build 24A434), at
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

## Historical linked-document test

The old PR included a linked-document diagnostic test tracked by issue
[#468](https://github.com/PinedaTec-EU/LeonardoMD/issues/468). Its fixture was
based on a renderer path that no longer exists on current `main`, so the
reconciliation deliberately skipped that stale test commit. The current
candidate retains the product integration coverage already present on `main`;
no replacement UI/capture test was added. The old hosted-runner observations
remain historical evidence only and do not establish a current-head failure.

## Historical packaged macOS Help smoke (Guide v94)

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

## Historical frequency localization UI evidence

The following evidence was produced by the old `PairingUITests` capture flow.
Those automated UI/capture tests were removed during reconciliation under the
current repository QA policy; the source evidence below is not a current-head
validation claim.

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

## Guide v156 package and preserved #465 runtime evidence

The reconciled Guide v156 packages combine the current `main` Guide v153
Finder/icon chapter from #415 with the #465 Little Leonardo chapter. Their
EN/ES SHA-256 values are
`3299b5faa869f34d6aa2b2aefeb0068d430b159a5d246d1355c94b4bb25cca32` and
`7027ef6d34f631b2d7158eb7d54a5b680073ca8f846c99a815252aec99190fea`.
Deterministic packaging and focused native `BundledUserGuideTests` validate
both locales and the package revision; no new GUI run was made after #415
merged. The preserved current-head native iOS validation opened the
integrated bilingual Help route and checked the document-extension and
frequency guidance. The exact simulator flow, process teardown, screenshots
and logs are in
[current-ios-qa/README.md](current-ios-qa/README.md). The fresh native macOS
v147 Help smoke, including English and Spanish routes, isolated personal-copy
hashes and exact process teardown, is preserved in
[current-macos-qa/README.md](current-macos-qa/README.md).

The earlier 2026-11-17 process note is historical only. The preserved v147
validation created and closed its own PID 13267 from the fresh QA bundle; see
[current-macos-qa/README.md](current-macos-qa/README.md) for the exact path,
hashes and termination log evidence. The #415 Finder visual record is in
[document-icons-415/README.md](../document-icons-415/README.md); this PR does
not duplicate that GUI run.

## Current-head criterion matrix for #464

The mobile implementation under review remains
`fd7b8b116f36e2bec360ffccecf2d0992387a3cd`; the branch is now reconciled with
the newly merged `origin/main` `06a93b2ab252d7439236ff92ae9c31d1acd73ff5`.
The iOS and macOS runtime evidence was observed before that merge at PR head
`c626cbc6f67ebe5d67422179c515c95b62a63ccd`; the current source/package
validation proves the unchanged #465 mobile chapter remains in Guide v156.
The matrix below separates source and automated coverage from runtime
acceptance that still belongs to beta/stable.

| #464 criterion | Current implementation and automated evidence | Observed visual evidence and remaining boundary |
| --- | --- | --- |
| Five independent device-local switches persist and reset locally | `Mobile/LittleLeonardo/MobileMarkdownPreferences.swift` and `Mobile/LittleLeonardo/MobileMarkdownExtensionsSettings.swift` persist the five `BuiltInExtension` flags. `MobileDemoStoreTests` covers bootstrap, locale/reset isolation, copy recovery and deletion behavior (9 focused cases passed locally at `fd7b8`). | [Extension settings capture](current-ios-qa/extension-settings-all-enabled.png) and its [sidecar](current-ios-qa/extension-settings-all-enabled.metadata.json) show all five enabled after independent changes. A fresh relaunch-persistence screenshot was not recorded; beta/stable validation must cover that runtime transition. |
| On-demand and offline previews remain read-only | `Mobile/LittleLeonardo/MobileDocumentView.swift`, `Mobile/LittleLeonardo/MobileRemoteDocumentPreview.swift`, `Mobile/LittleLeonardo/MobileDemoView.swift` and `Sources/LeonardoSyncUI/RemoteDocumentPreview.swift` feed the same feature configuration to received and bundled documents. `MobileReaderSpacingTests.testLeonardoDocumentsRenderReadOnlyInLittleLeonardo` remains the repository regression; the 9 Demo-store cases cover offline Demo copies and recovery. | [English Demo captures](current-ios-qa/demo-en-all-enabled-top.png) and [scrolled preview](current-ios-qa/demo-en-scrolled.png) show the bundled local, read-only flow. This run did not claim a remote transfer or physical/TestFlight session; fresh remote/on-demand runtime acceptance is deferred to beta/stable. |
| Grouped consent offers only detected disabled features; Not now/suppression/reset are safe | `Mobile/LittleLeonardo/MobileExtensionRecommendations.swift` and `Mobile/LittleLeonardo/MobileExtensionRecommendationDialog.swift` enforce allowlisted detection, exact-source context and explicit selection. `MobileExtensionRecommendationsTests.testRecommendationIsNotRepeatedForFormChangesAndResetsOnReopen` and `.testNotNowDoesNotEnableAndResetRestoresRecommendation` (2 focused cases) passed locally. | The current iOS run observed the grouped consent before enabling the Demo, but no prompt screenshot was retained. The older [English](../little-leonardo/mobile-extension-recommendation-full/mobile-extension-recommendation-en.metadata.json) and [Spanish](../little-leonardo/mobile-extension-recommendation-full/mobile-extension-recommendation-es.metadata.json) sidecars are valid historical visuals from source `d00d6d804d5285b8f5dda240b95ffa3ec54ba6ec`, not current-head proof. A fresh beta/stable prompt capture remains optional runtime follow-up. |
| Allowlisted engines, literal fallback, blocked remote content and read-only behavior remain intact | `Sources/LeonardoCore/BuiltInExtension.swift`, `Mobile/LittleLeonardo/MobileExtensionRecommendations.swift`, `Mobile/LittleLeonardo/MobileDocumentView.swift`, `Sources/LeonardoRender/MarkdownResourceCatalog.swift` and `Sources/LeonardoSyncUI/RemoteDocumentPreview.swift` preserve the five allowlisted IDs, disabled-engine fallback, `externalLinkPolicy: .blocked`/`.callbackOnly` and `allowsRemoteImages: false`. Existing renderer/mobile tests, including the read-only test above, provide regression coverage; no new current-head UI test was added. | The current Demo and Help captures show the selected feature state and local rendering only. Remote-resource authorization and physical-device behavior are not visually claimed here; beta/stable remains the acceptance boundary. |
| English and Spanish bundled Help document the workflow and remain package-identical | `doc/guide/en/body.md`, `doc/guide/es/body.md` now contain both #415 chapter-1 Finder guidance and the #465 mobile chapter. Guide v156 packages are EN `3299b5faa869f34d6aa2b2aefeb0068d430b159a5d246d1355c94b4bb25cca32` / ES `7027ef6d34f631b2d7158eb7d54a5b680073ca8f846c99a815252aec99190fea`; deterministic package tests and focused `BundledUserGuideTests` passed. | Current iOS and macOS screenshots/process evidence remains the preserved v147 run in [current-ios-qa](current-ios-qa/README.md) and [current-macos-qa](current-macos-qa/README.md); #415 Finder evidence is linked from [document-icons-415](../document-icons-415/README.md). No new GUI was run during this reconciliation. Physical/TestFlight Help acceptance remains a beta/stable gate. |

Hosted exact-head checks are recorded by CI rather than repeated in this
documentation/package reconciliation. The preserved iOS evidence README
records the local generic compile and 11 focused tests; it also preserves the
XcodeBuildMCP log paths and teardown identities. The new focused native guide
test records the v156 package/revision after the #415 merge. No screenshot
event time was persisted, so the sidecars intentionally expose that limitation
instead of deriving a capture time from file metadata.

## Release cleanup gate

The primary checkout's `main` branch matches `origin/main` (0 ahead, 0 behind)
but has a pre-existing user modification to `.wiki/document-extensions.md`.
The release-cleanup workflow blocks merge and TestFlight publication until that
user-owned file is reconciled. This task left the file and branch untouched.

Physical-device/TestFlight acceptance and the coordinator's fresh judge remain
pending. The current-head iOS simulator smoke is complete; it did not modify
the primary checkout, launch a macOS app, or merge the PR.
