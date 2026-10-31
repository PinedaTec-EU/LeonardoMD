# Guide v3 and extension recommendation validation

Tracking: [#310](https://github.com/PinedaTec-EU/LeonardoMD/issues/310).
Implementation and exact-head CI evidence: [PR #311](https://github.com/PinedaTec-EU/LeonardoMD/pull/311).

## Coverage

- `ExtensionDetectionTests`: real WKWebView, all five extensions detected with their engines disabled; fenced/inline/quoted literal examples ignored; consumed footnote definitions detected; incremental source identity retained.
- `ExtensionRecommendationTests`: grouped disabled-only selection, inactive/preferences deferral and actual attached native sheet, per-opening deferral, per-extension persistence, reset without flag changes, project/global activation, preserved unrelated flags and stale consent rejection.
- `BundledUserGuideTests`: English/Spanish package opening, independent v3 working-copy paths, preserved v2 sentinel and saved v3 practice answers, four local images, real Mermaid SVG, KaTeX and Vega-Lite SVG.
- `scripts/tests/test_package_user_guide.py`: deterministic packages, local PNG header and SVG assets, revision 3 metadata, required live syntax, unrelated output preservation.

## Visual evidence

CI's `preview-tags-<head SHA>` artifact includes:

- `user-guide/guide-en.png` and `guide-es.png`: compact branded header and introduction.
- `user-guide/diagram-*.png`, `math-*.png`, `chart-*.png`: live extension output and nearby requirements.
- `extension-recommendations/dialog-<en|es>-<global|project>.png`: grouped consent, explicit preference scope and per-extension suppression.
- `extension-recommendations/reset-<en|es>.png`: reset control and explanation.

These are native SwiftUI/WKWebView component captures with synthetic practice data.
Their neighboring JSON/context files record provenance and the tested source SHA.
They do not establish a fresh packaged-process launch or release acceptance.

The native capture fixtures explicitly back text/buttons with the session surface
and force Aqua host appearance. Initial unbacked captures reproduced the evidence
limitation tracked in [#187](https://github.com/PinedaTec-EU/LeonardoMD/issues/187);
those black captures are not accepted validation evidence. This does not claim a
general fix for #187.

The guide reuses the approved application About artwork as a locally packaged,
compact header; no remote image dependency or generated mock validation is used.
Existing complex-math issues [#272](https://github.com/PinedaTec-EU/LeonardoMD/issues/272)
and [#274](https://github.com/PinedaTec-EU/LeonardoMD/issues/274) remain outside scope.

## Local reproduction

Set `LEONARDO_VISUAL_EVIDENCE` to an output directory and `EVIDENCE_SHA` to the
source revision before running the Swift suite through the repository's
`scripts/compile-and-record.py` wrapper with the source PR number. CI runs the
same test suite and uploads the evidence directory. Guide source changes require
regenerating the two resources with `scripts/package-user-guide.py`.

## Author verification

On 2026-10-31, the final local Swift suite passed: 579 XCTest cases (15 skipped)
plus 28 Swift Testing cases, with no failures. Script tests passed (52, seven
engine-dependent skips), as did plugin tests (38) and packaging tests (20).
The source PR ledger records successful compiler-bearing local validation invocations.
The author inspected native captures in both languages for header, diagram/formula,
chart, consent dialog and reset preferences. GitHub CI and independent review are
tracked on the PR and must be checked for its current head before integration.
