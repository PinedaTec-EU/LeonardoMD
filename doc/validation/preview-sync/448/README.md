# Preview synchronization recovery acceptance — PR #448

## Scope and source

This report records validation for [issue #447](https://github.com/PinedaTec-EU/LeonardoMD/issues/447) and [PR #448](https://github.com/PinedaTec-EU/LeonardoMD/pull/448). The validated application source is commit `0a463909c9f8abdf16e1a74b792f0ee4d7266a41`, based on `main` at `8711e44aae3babc5beb914bb6b3e69dfe2715e96` (Guide v74). It preserves v74, incorporates the bilingual recovery text in Guide v76, and leaves earlier personal copies intact.

An ordinary Preview synchronization failure now presents one native action. If closing reaches a failed Preview flush, the recovery alert names the affected document and offers Keep Open for retry or an explicit discard of only the unapplied Preview edits. Any other unsaved document changes still use the regular Save, Discard or Cancel decision. During close preparation, already queued Preview and form messages remain authorized through the final renderer snapshot; the gate then closes before the ordinary save decision. A failed inactive tab is selected before the alert appears and remains visible when the user keeps it open.

The reporter-provided screenshot remains attached to public issue #447. The four captures below are separate implementation evidence from the production AppKit alert builders, rendered by the opt-in XCTest with fictional content.

## Native alert captures

The ordinary warning has one action in English and Spanish. The close warning names `sample.md`, explains that the unapplied Preview edits can be retried or discarded, and presents Keep Open and a visually destructive Preview-only discard action. The images are native alert components, not full application-window captures.

| State | Capture | Sidecar | Captured (UTC) | AppKit viewport | Image pixels |
| --- | --- | --- | --- | ---: | ---: |
| English, ordinary retry | [PNG](preview-alert-en-retry.png) | [JSON](preview-alert-en-retry.png.metadata.json) | 2026-11-13 16:38:13.990482 | 306 × 280 pt | 612 × 560 |
| English, close recovery | [PNG](preview-alert-en-close.png) | [JSON](preview-alert-en-close.png.metadata.json) | 2026-11-13 16:38:13.989980 | 306 × 330 pt | 612 × 660 |
| Spanish, ordinary retry | [PNG](preview-alert-es-retry.png) | [JSON](preview-alert-es-retry.png.metadata.json) | 2026-11-13 16:38:13.991466 | 306 × 312 pt | 612 × 624 |
| Spanish, close recovery | [PNG](preview-alert-es-close.png) | [JSON](preview-alert-es-close.png.metadata.json) | 2026-11-13 16:38:13.990986 | 314 × 362 pt | 628 × 724 |

Each sidecar binds the current image hash and dimensions to its observed write/capture time, native screen, synthetic data, viewport points and source revision at collection. The capture source is `0a463909c9f8abdf16e1a74b792f0ee4d7266a41`. Later changes in the evidence commit are limited to the build ledger, captures and sidecars, this report, and `.wiki` notes; application code, guides, tests and build inputs are unchanged.

## Packaged application and Help acceptance

`./launch.sh --qa` produced the real app bundle. `scripts/qa-bundle.py --verify-only` passed; `CFBundleExecutable` is `LeonardoMD`, and `otool -L` showed its AppKit, SwiftUI and WebKit dependencies without `XCTest.framework`.

The isolated QA app was relaunched from that verified bundle as a fresh process using `CFFIXED_USER_HOME=/private/tmp/leonardo-448-final-home.Z0nRMl` and `LEONARDO_SOURCE_PR=448`. PID `77330` reached `first_window_shown` and `application_ready`; bundle identifier `eu.pinedatec.LeonardoMD.qa.6617357555e04ec9bcee181c0cc99adf`, bundle `/var/folders/_s/khfztzr97kd4049py5k3zsg80000gn/T/leonardo-native-qa-ayyin875/LeonardoMDQA.app`, version `0.3.1602`, build `1602`. The process did not forward to an existing app.

In that same process, I opened both bundled guides through the native Help menu: Help → Leonardo user guide… opened `Guide-v76-en.mdlz`, and after temporarily changing the isolated interface language, Ayuda → Guía de Leonardo… opened `Guide-v76-es.mdlz`. Each Help-opened personal copy matched its bundled resource byte-for-byte:

- English SHA-256: `85d3b5fbbb0669584e9264eed202e1bb233a7702f9b93b3d70e1dd87182a185e`.
- Spanish SHA-256: `2b1423efd816a0e8f9c6ef35d3ac31ef2f864486d78a137d8627658b6d015864`.

Both live guides showed their local cover image, Mermaid diagram, tables and Vega-Lite chart. With Mermaid, Math and Charts enabled, the one-line and multiline display equations, inline math, underscore/underbrace expressions and tagged box-counting equation `(1)` rendered without literal delimiters or KaTeX errors. With Math disabled, the English guide retained formula source literally and code examples remained code; Math was re-enabled afterward. Chapter 10 in both locales explained the retry and Preview-only discard choice.

The Spanish practice form was opened from the guide, saved, closed and reopened from the guide button in the same process. Its fictional answers persisted and Ready to share remained unchecked:

| Locale | Name | Goal | Ready to share |
| --- | --- | --- | --- |
| Spanish | `Prueba v76 final` | `Comprobar la persistencia al cerrar y volver a abrir la guía.` | No |

The isolated app language was restored to English and Math remained enabled. The QA app was quit normally. The guide copies, practice form and preferences stayed under the isolated temporary home; the normal user home was not used.

## Automated validation

- Full `scripts/compile-and-record.py --pr-number 448 -- swift test --disable-automatic-resolution` passed at source `0a463909c9f8abdf16e1a74b792f0ee4d7266a41`: 530 XCTest (36 skipped), 44 Swift Testing and 28 package tests; zero failures. Recorded build delta: 22.
- Focused `SessionEditingTests` and `InlineFormTests` passed: 18 executed, 2 optional capture cases skipped, zero failures. Recorded build delta: 20.
- `LEONARDO_PREVIEW_ALERT_EVIDENCE=doc/validation/preview-sync/448 python3 scripts/compile-and-record.py --pr-number 448 -- swift test --disable-automatic-resolution --filter SessionEditingTests/testCapturePreviewSynchronizationWarningsInBothLanguages` passed: 1 executed, zero failures. Recorded build delta: 21.
- `python3 -m unittest discover -s scripts/tests -p 'test_package_user_guide.py' -v` passed all 3 deterministic Guide packaging checks.
- The full compile produced non-failing warnings in unrelated existing code, including a `.wifiAware` exhaustiveness warning in `Sources/LeonardoSyncTransport/HTTPSResponseDiagnostics.swift`; none is in this PR's source changes.
- Exact-head GitHub CI and a strict independent review are separate merge gates; both require a result for the published PR head.

The four sidecars and this report are linked from the [PR #448 validation thread](https://github.com/PinedaTec-EU/LeonardoMD/pull/448). The machine-readable acceptance record is [native-acceptance.json](native-acceptance.json).
