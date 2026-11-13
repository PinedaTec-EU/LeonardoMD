# Preview synchronization alert acceptance — PR #448

## Scope and source

This report validates the native alert correction tracked by [issue #447](https://github.com/PinedaTec-EU/LeonardoMD/issues/447) and [PR #448](https://github.com/PinedaTec-EU/LeonardoMD/pull/448). The alert implementation and these captures are bound to source commit `21c17142d179ccc0ebe2c9ec68ad31df6252c417`, based on current `main` `8711e44aae3babc5beb914bb6b3e69dfe2715e96`. The follow-up evidence commit changes documentation and validation records only.

An ordinary Preview renderer sync failure now presents a single **OK** action. When close is blocked by the same failure, the alert explains that the document can stay open for a retry or that unapplied Preview edits can be discarded to close. Other unsaved document changes still use the existing Save/Discard/Cancel flow.

## Native alert captures

These four screenshots are captures of the production `NSAlert` builders rendered by the opt-in `SessionEditingTests.testCapturePreviewSynchronizationWarningsInBothLanguages` XCTest. They use synthetic content and show the alert component, not the full application window. The ordinary warning has one action in both locales. The close warning offers both recovery choices; the destructive discard action appears above Keep Open in the captured vertical layout, while Keep Open remains the first/accessibility default action and uses Escape.

| State | Capture | Metadata |
| --- | --- | --- |
| English, ordinary sync retry | [PNG](preview-alert-en-retry.png) | [JSON](preview-alert-en-retry.png.metadata.json) |
| English, close recovery | [PNG](preview-alert-en-close.png) | [JSON](preview-alert-en-close.png.metadata.json) |
| Spanish, ordinary sync retry | [PNG](preview-alert-es-retry.png) | [JSON](preview-alert-es-retry.png.metadata.json) |
| Spanish, close recovery | [PNG](preview-alert-es-close.png) | [JSON](preview-alert-es-close.png.metadata.json) |

The sidecars record capture time, native AppKit surface, Retina dimensions, synthetic-data provenance, image hash and the source revision. The original user-provided screenshot remains attached to public issue #447.

## Packaged application acceptance

`./launch.sh --qa` produced a disposable packaged macOS app. Its `CFBundleExecutable` was `LeonardoMD`; `otool -L` showed the expected AppKit, SwiftUI and WebKit dependencies and no XCTest framework; `scripts/qa-bundle.py --verify-only` passed. The bundle identified as `eu.pinedatec.LeonardoMD.qa.9f42ce38c3b6481fb15706acaf832071`, version `0.3.1602`, build `1602`. A fresh isolated process (PID `8844`) reached `first_window_shown` / `application_ready`; it did not forward to another instance.

In that same process, the bundled guides were opened through the real Help menu:

- English: **Help → Leonardo User Guide**, `Guide-v76-en.mdlz`.
- Spanish: **Ayuda → Guía de Leonardo**, `Guide-v76-es.mdlz`.

The live guide inspection covered Mermaid diagrams, inline and display math, charts, tables and local images. With Math enabled, the equations and tagged equation `(1)` rendered without KaTeX errors or literal delimiters. With Math disabled, the English guide retained literal math notation and code examples remained literal. Spanish Math was re-enabled for its rendered equation inspection.

The separate practice form was opened from each guide, filled with fictional QA values, saved, closed and reopened. The English name/goal were `Codex QA smoke` / `Verify the bilingual help workflow and saved practice answers.`; the Spanish values were `Codex QA smoke ES` / `Comprobar que la guía española guarda y recupera respuestas ficticias.`. The share-ready checkbox remained selected in both reopened forms. No existing user practice file was used.

The app/help observations are recorded in machine-readable form in [`native-acceptance.json`](native-acceptance.json). The live guide screens were inspected in the running instance; only the four alert-component screenshots above were retained as image files.

## Automated validation

- `scripts/compile-and-record.py --pr-number 448 -- swift test --disable-automatic-resolution`: 526 XCTest cases (36 skipped), 44 Swift Testing cases and 28 package tests; zero failures. Successful compiler build delta: 9.
- `python3 -m unittest discover -s scripts/tests -p 'test_package_user_guide.py' -v`: 3 tests passed, covering deterministic bilingual bundles, preserved historical copies and localized image references.
- The relevant `SessionEditingTests` verify a single retry action in both languages, Keep Open as the Escape action, destructive explicit discard, and closing after renderer failure without repeatedly retrying the failed flush.
- `git diff --check`: passed before evidence files were added; the evidence commit is checked separately.

The Swift compile emitted a non-failing Network.framework exhaustiveness warning in `Sources/LeonardoSyncTransport/HTTPSResponseDiagnostics.swift` for `.wifiAware`; that file is outside this PR's change. Exact-head CI and the independent PR judgment are delivery gates and are reported on the PR, not asserted by this local report.
