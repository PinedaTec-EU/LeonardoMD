# Preview synchronization alert acceptance — PR #448

## Scope and source

This report validates the native alert correction tracked by [issue #447](https://github.com/PinedaTec-EU/LeonardoMD/issues/447) and [PR #448](https://github.com/PinedaTec-EU/LeonardoMD/pull/448). The corrected close-flush source is in commit 28a0fa127f32a7922e23053795f061e98d42c1de; the current full capture source revision is 9f679837788fc733f6667e9274c365b90b5b1716, based on main at 8711e44aae3babc5beb914bb6b3e69dfe2715e96.

An ordinary Preview renderer synchronization failure now presents one native action. During a close blocked by the same failure, the app offers Keep Open for another retry or explicit discard of only unapplied Preview edits. Other unsaved document changes still use the regular Save, Discard or Cancel decision.

The original reporter-provided screenshot remains attached to public issue #447. The component captures below are separate, fresh synthetic-data captures from the corrected source.

## Native alert captures

The four PNGs capture the production AppKit alert builders through the opt-in SessionEditingTests.testCapturePreviewSynchronizationWarningsInBothLanguages test. They show the alert component, not a full application window. The retry warning has exactly one action in both locales. The close warning offers the destructive discard action and Keep Open; Keep Open is the first/accessibility default and responds to Escape.

| State | Capture | Metadata |
| --- | --- | --- |
| English, ordinary sync retry | [PNG](preview-alert-en-retry.png) | [JSON](preview-alert-en-retry.png.metadata.json) |
| English, close recovery | [PNG](preview-alert-en-close.png) | [JSON](preview-alert-en-close.png.metadata.json) |
| Spanish, ordinary sync retry | [PNG](preview-alert-es-retry.png) | [JSON](preview-alert-es-retry.png.metadata.json) |
| Spanish, close recovery | [PNG](preview-alert-es-close.png) | [JSON](preview-alert-es-close.png.metadata.json) |

Each sidecar records the observed capture time, native AppKit surface, window-point viewport, Retina pixel dimensions, synthetic-data provenance, image hash and Git source revision. At collection, HEAD was 9f679837788fc733f6667e9274c365b90b5b1716. The sidecars report tracked changes because the successful capture invocation advanced the PR build counter to delta 17 and replaced the tracked capture images; no untracked files were present. Application sources and test inputs were unchanged from that HEAD. The subsequent evidence commit contains validation records, captures and ledger/wiki bookkeeping only.

## Packaged application and Help acceptance

The disposable app was launched with an isolated home using CFFIXED_USER_HOME=/private/tmp/leonardo-448-corrected-home.bOCg20yT and LEONARDO_SOURCE_PR=448 via ./launch.sh --qa --args --new-instance -allowMultipleInstances YES. Its real CFBundleExecutable was LeonardoMD; otool -L showed the expected AppKit, SwiftUI and WebKit dependencies and no XCTest.framework; scripts/qa-bundle.py --verify-only passed.

The QA bundle identifier was eu.pinedatec.LeonardoMD.qa.5b11a2952aaa4b9ea40defd3324c114b, app version 0.3.1602, build 1602. Fresh process PID 92461 reached first_window_shown and application_ready; it did not forward to an existing process.

In that same process, both bundled guides were opened through the native Help menu: Help → Leonardo user guide… opened Guide-v76-en.mdlz and Ayuda → Guía de Leonardo… opened Guide-v76-es.mdlz. The bundle resource and Help-opened personal copy matched byte-for-byte in each locale:

- English SHA-256: 85d3b5fbbb0669584e9264eed202e1bb233a7702f9b93b3d70e1dd87182a185e.
- Spanish SHA-256: 2b1423efd816a0e8f9c6ef35d3ac31ef2f864486d78a137d8627658b6d015864.

Both live guides showed their local cover image, table, Mermaid diagram and Vega-Lite chart. With Mermaid, Math and Charts enabled, the one-line and multiline display equations, inline math, Markdown-sensitive underscore/underbrace expressions and tagged box-counting equation (1) rendered; no KaTeX errors or literal delimiters appeared. Math was disabled in English to verify the literal-source fallback and code examples remaining literal, then re-enabled before completing the bilingual check. Chapter 10 in both locales visibly explains retry and discarding only unapplied Preview edits.

The separate practice form was filled with fictional values, saved, closed and reopened from its guide button. The reopened values were intact and the Ready to share checkbox remained unchecked:

| Locale | Name | Goal | Ready to share |
| --- | --- | --- | --- |
| English | QA Guide v76 | Check local practice form persistence. | No |
| Spanish | Prueba v76 | Comprobar que las respuestas ficticias se guardan en la copia local. | No |

The application preference was restored to English and Math remained enabled after validation. All QA preferences and answers were kept under the isolated temporary home; no user guide or practice copy in the normal home was used.

## Automated validation

- Full swift test --disable-automatic-resolution passed: 528 XCTest cases (36 skipped), 44 Swift Testing cases and 28 package tests, zero failures; recorder build delta 14.
- Focused SessionEditingTests and InlineFormTests passed: 16 executed, 2 optional capture tests skipped; recorder build delta 13.
- The bilingual native alert capture test passed: 1 executed, zero failures; recorder build delta 17.
- python3 -m unittest discover -s scripts/tests -p test_package_user_guide.py -v passed all 3 deterministic guide packaging tests.
- The compile emitted a non-failing Network.framework exhaustiveness warning for .wifiAware in Sources/LeonardoSyncTransport/HTTPSResponseDiagnostics.swift; that file is outside this PR.
- git diff --check is rerun after preparing this evidence commit. Current-head CI and the fresh strict judge are tracked on the PR and must match the final pushed SHA.
