# Little Leonardo offline demo validation

**Current refresh:** #274 and #364 are integrated through #377. See [integrated-fixes validation](integrated-fixes/README.md) for the refreshed source and captures. The record below is historical evidence from the earlier baseline and retains its original failed observations.

Tracking: [#381](https://github.com/PinedaTec-EU/LeonardoMD/issues/381), [draft PR #383](https://github.com/PinedaTec-EU/LeonardoMD/pull/383).

## Tested application

The final iOS run compiled source `854ae4a9ab4ed35df65595a590ddba564aced887` into the real `LittleLeonardo.app` through Xcode's normal test workflow. Runtime: iPhone 17 Pro simulator, iOS 27.0 (24A434), bundle `eu.pinedatec.LittleLeonardo`. The local Debug build does not inject version/build plist fields; the source SHA identifies this validation artifact. Distribution supplies its canonical version separately. No TestFlight upload or physical-device claim is made.

The simulator was created for this task, without a paired Mac. The demo uses bundled resources and local data. Airplane-mode operation was not independently exercised. Native controls are bilingual, while the selected demo is Spanish or English. Mermaid, Math, Vega-Lite, Markdown extras and Leonardo form rendering are explicitly enabled only in the demo configuration. Synchronized-document rendering and permissions retain their existing behavior.

## Results

- Final iOS XCTest run: **13 passed, 0 failed, 0 skipped**. Includes all mobile unit tests plus the demo UI walkthrough. See [machine-readable result](ios-test-summary.json).
- UI walkthrough: open English demo, confirm reset, assert empty field, open/close field help, enter fictional answer, explicitly save, terminate/relaunch the application and verify the answer survives; open Spanish demo.
- Store tests: create both personal copies, preserve answers on reload, reset each language independently, preserve malformed personal bytes instead of overwriting them, parse bundled fields/resources.
- Full SwiftPM suite: **365 XCTest cases, 30 skipped, 0 failed**, plus **28 Swift Testing cases passed**. Explicit fixture/capture-dependent cases retain their opt-in skip conditions.
- Focused native bundled-guide suite: **5 passed**; component/WKWebView checks do not substitute for packaged Help acceptance.
- Python tools: **111 cases, 7 skipped, 0 failed**; portable format helper: **38 passed**; packaging: **20 passed**.
- Both demo MDLR files validated against the versioned format contract/schema. Deterministic bilingual guide packaging tests passed; Guide v18 and both web manuals were regenerated. Earlier personal guide copies and practice answers are preserved.
- Seven successful compiler-bearing invocations recorded in PR #383's own ledger entry. Failed/metadata-only commands are not counted.
- Independent isolated code review found no known code blocker at `854ae4a`; this is not an overall delivery PASS.

## Original native captures

These are original XCTest screenshots of the running packaged iOS app, using bundled/fictional content. The adjacent JSON files preserve source, actual attachment capture time, device/runtime, locale/state, dimensions and hashes. Browser CSS viewport and browser version were not exposed by native XCTest; they are explicitly unavailable instead of invented for the browser-only metadata helper.

- [English welcome](english-welcome.png) and [Spanish welcome](spanish-welcome.png).
- [Markdown and table](english-gallery-0.png).
- [Local image and Mermaid](english-gallery-1.png).
- [Inline/display math, tagged equation and Vega chart](english-gallery-2.png).
- [Actual typed form controls](english-gallery-3.png).
- [Saved local practice](english-saved-practice.png).

Manual inspection confirmed the local image, rendered Mermaid, actual display equations with tag `(1)`, chart and form controls; no literal math delimiters or KaTeX error message appeared in the inspected math capture. Screenshots cover the English gallery and both localized welcomes; they do not establish complete manual Spanish gallery or disabled-extension acceptance. The subsequent native Help run is recorded below; the original iOS captures are not a claim that #274 is fixed.

Later evidence/ledger-only commits do not change the tested product inputs. Verify with `git diff 854ae4a <reviewed-head> -- Mobile Sources Package.swift` before reusing these captures for an exact-head review; any product-input change requires a new build/capture.

## Packaged macOS Help run — 6 November 2026

The owner authorized a normal quit and QA replacement. `LEONARDO_SOURCE_PR=383 ./launch.sh --qa` built the real executable and packaged resources/frameworks. `qa-bundle.py --verify-only` and `otool -L` confirmed the proper LeonardoMD executable/dependencies and no XCTest GUI linkage. Fresh process **35129** loaded the task's `leonardo-native-qa-vknuayfl` bundle, identifier `eu.pinedatec.LeonardoMD.qa.cfd1f038fd614a619dd5a0a8b58b99b8`, version **0.3.1022**, build **1022**. This local release build retains the canonical baseline version; the unintegrated PR delta is not materialized as a published release. Build source was `743b21d`, with only its compilation count changing; product inputs remain equal to `854ae4a`.

Both Guide v18 locales were opened using the real Help menu. Existing local v18 copies belonged to another QA revision (known [#378](https://github.com/PinedaTec-EU/LeonardoMD/issues/378)); they and the separate practice directories were retained before fresh bundled copies were generated. The new copies exposed this PR's Little Leonardo appendix.

Observed in the actual packaged instance:

- English and Spanish: real Mermaid diagrams, local images, tables and Vega charts display. One-line mean, inline math and multiline box-counting equation render with tag `(1)`; inline code stays literal and there is no KaTeX parse error or literal display delimiter in the enabled equations.
- English and Spanish: disable Mermaid/Math/Charts through Preferences, choose Not now in the consent dialog, and verify source/notation remains visible. Re-enable the original three engines afterward.
- English and Spanish: follow the guide's separate practice link, enter fictional name/goal/checkmark, save, close, reopen through the guide and verify all three values persist. [English reopened practice](macos-help/en-practice-reopened.png), [Spanish reopened practice](macos-help/es-practice-reopened.png).
- **FAILED graphical math acceptance:** operands and labels render, but underbrace shapes are missing. This reproduces existing [#274](https://github.com/PinedaTec-EU/LeonardoMD/issues/274). [English evidence](macos-help/en-examples-enabled.png), [Spanish evidence](macos-help/es-examples-enabled.png). Semantic/accessibility math text alone does not prove SVG shape fidelity.
- **FAILED outline navigation:** choosing Display formulas lands around the later format section, reproducing existing [#364](https://github.com/PinedaTec-EU/LeonardoMD/issues/364). [Observed wrong destination](macos-help/en-fullscreen.png). Scrolling via the actual scrollbar allowed the remaining inspection without changing application code.

[English disabled engines](macos-help/en-examples-disabled.png) and [Spanish disabled engines](macos-help/es-examples-disabled.png) preserve the actual fallback. Adjacent native provenance JSON and AX snapshots record state; screenshots are originals. Window placement initially produced unusable thumbnails, so only the subsequent full-screen captures are retained as review evidence.

UI handoff is complete: QA process 35129 quit normally; no LeonardoMD process remained at release of the UI. Original guide/practice directories were restored and verified byte-for-byte against retained SHA-256 maps. Original interface language English and extension state Mermaid/Math/Charts on, Markdown extras on, Citations off were restored. The temporary practice answers were isolated from the user's originals. The UI is released for other chats; no further app actions are planned in this checkpoint.

## Pending acceptance and retained workspace

The Help smoke was executed and has known failures, so this PR remains draft and has no strict delivery PASS. Existing #274 and #364 are maintained in their own workflows; this task does not silently fold in their fixes. Repeat affected native and iOS acceptance after those fixes are integrated/refreshed. CI passed on `743b21d`; new evidence-only head checks must finish separately. No merge, beta or App Store/TestFlight publication is claimed.

The task worktree `.worktrees/381-little-demo` remains on `codex/381-little-demo` for follow-up. Task-owned external caches are `XcodeData/DerivedData/LeonardoMD-381` (Xcode) and `XcodeData/DerivedData/LeonardoMD-381-SwiftPM` (SwiftPM Debug/Release, linked by the task's ignored `.build`). Preserve test evidence before retiring caches and task simulator `D1B54EA2-B8EF-4DB6-8D49-AEFE06FA924E`. Other workspaces, Guide v19/v20 and other chats' QA candidates were not modified by the final inspection/restore workflow.
