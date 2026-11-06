# Little Leonardo offline demo validation

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
- Six successful compiler-bearing invocations recorded in PR #383's own ledger entry. Failed/metadata-only commands are not counted.
- Independent isolated code review found no known code blocker at `854ae4a`; this is not an overall delivery PASS.

## Original native captures

These are original XCTest screenshots of the running packaged iOS app, using bundled/fictional content. The adjacent JSON files preserve source, actual attachment capture time, device/runtime, locale/state, dimensions and hashes. Browser CSS viewport and browser version were not exposed by native XCTest; they are explicitly unavailable instead of invented for the browser-only metadata helper.

- [English welcome](english-welcome.png) and [Spanish welcome](spanish-welcome.png).
- [Markdown and table](english-gallery-0.png).
- [Local image and Mermaid](english-gallery-1.png).
- [Inline/display math, tagged equation and Vega chart](english-gallery-2.png).
- [Actual typed form controls](english-gallery-3.png).
- [Saved local practice](english-saved-practice.png).

Manual inspection confirmed the local image, rendered Mermaid, actual display equations with tag `(1)`, chart and form controls; no literal math delimiters or KaTeX error message appeared in the inspected math capture. Screenshots cover the English gallery and both localized welcomes; they do not establish complete manual Spanish gallery or disabled-extension acceptance. Native Help smoke remains separate.

Later evidence/ledger-only commits do not change the tested product inputs. Verify with `git diff 854ae4a <reviewed-head> -- Mobile Sources Package.swift` before reusing these captures for an exact-head review; any product-input change requires a new build/capture.

## Pending acceptance and retained workspace

The PR remains draft. Required CI must finish for its final head. A strict current-head judge PASS has not been published because packaged Help acceptance remains pending.

The user's running macOS development instance (`LeonardoMD-Dev-0.3.1000`) owns product-wide single-instance access. It was not terminated. The repository requires Spanish and English bundled guides to be opened through the real Help workflow in a fresh tested packaged instance, including Mermaid/math/charts/images/tables, separate practice open/fill/save/reopen and enabled/disabled-extension behavior. This cannot be replaced by passing WKWebView tests. Owner authorization to close the running app was requested; absent that authorization, this acceptance remains pending.

The task worktree `.worktrees/381-little-demo` remains on `codex/381-little-demo` for pending acceptance. Task-owned external caches are `XcodeData/DerivedData/LeonardoMD-381` (Xcode) and `XcodeData/DerivedData/LeonardoMD-381-SwiftPM` (SwiftPM), together approximately 1.2 GiB at validation time. Preserve original test evidence before retiring those caches and the task simulator `D1B54EA2-B8EF-4DB6-8D49-AEFE06FA924E`. Other workspaces and running app instances are outside this task's cleanup scope.
