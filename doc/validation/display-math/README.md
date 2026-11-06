# Display-math regression validation

Tracking: [#272](https://github.com/PinedaTec-EU/LeonardoMD/issues/272).

## Current evidence

Current captures are in [adjacent-fix/](adjacent-fix/), built from
`8061b04d640ea87554205e96ba60ea6ae4f165b0` after the adjacent-expression correction.
The block tokenizer stops at the first closing delimiter and delegates lines
with trailing HTML or text to the inline parser. The native regression verifies
`$$a_b$$<br>$$c_d$$` and `$$e_f$$ between $$g_h$$`, requiring four display equations,
a real line-break element, preserved intervening text and no KaTeX errors.

- Full `swift test`: 663 XCTest cases, 34 skipped, zero failures; 70 additional
  Swift Testing cases pass.
- Focused native display-math and bilingual guide suite: 7 cases pass, including
  adjacent expressions, enabled/disabled context replacement, literal code,
  editing boundaries, local images and live Mermaid/Math/Charts.
- Script suite: 95 tests, 7 skipped by environment/engine conditions.
- The release app builds and passes executable/dependency/signature verification.
- Seven successful compiler-bearing commands are recorded; failed/interrupted
  commands are not counted. The version remains the unmaterialized 0.3.898 baseline.

## Fresh packaged-process acceptance

The owner authorized closing the prior application. It quit normally through its
menu. `LEONARDO_SOURCE_PR=363 ./launch.sh --qa` started fresh PID **45732** from the
verified real executable and dependencies; the first window was observed.
Both revision-15 personal copies were opened through **Help → Leonardo user guide**
in that process. Current English and Spanish JPEGs show the rendered equations
and their tags. Math disabled fallback was observed in English and Math restored.
Mermaid, Charts, local images and tables were inspected. Both practice links opened
separate Fill forms; fictitious names were saved, tabs closed, forms reopened
through the help links and retained values verified. Test values were cleared
and saved again; the original English UI language was restored.

## Capture binding and source mapping

The component captures have canonical helper-generated `*.metadata.json` sidecars
with schema, observed WKWebView User-Agent/CSS viewport, original capture time,
actual PNG dimensions and SHA-256. Original measured context is retained separately.

Packaged CUA captures are original **2520 × 1700 JPEG** bytes, explicitly named
`.jpg`. Native sidecars use the shared helper's image-header reader and Git
identity collector and include exact hashes, build revision, process/bundle and
window state. Native CUA does not expose CSS viewport or packaged WKWebView
version; those browser-only fields are explicitly unavailable, not inferred from
window pixels. This follows the shared visual contract's unavailable-context
exception. Canonical browser-context sidecars belong to the component captures;
packaged window captures supplement them with real-process acceptance.

Run `python3 doc/validation/display-math/verify-source-mapping.py <review-SHA>`.
It rejects any difference from current capture sources outside this evidence
directory, PR 363's build-count entry and the non-packaged feature-coverage
revision inventory. The latter only corrects current-guide labels from v14 to
v15; neither the guide generator nor app build reads that inventory. Every
tracked product source, build
input, test, guide source/package and workflow must match. Ledger-count changes
do not materialize a runtime version. Later evidence-only heads use that mapping.

## Known separate defects

Underbrace SVG paths remain absent because of
[#274](https://github.com/PinedaTec-EU/LeonardoMD/issues/274). The variables,
subscripts and tagged box-counting equation render; captures do not claim complete
extensible-symbol acceptance. Outline navigation landed away from the selected
heading during the earlier QA; [#364](https://github.com/PinedaTec-EU/LeonardoMD/issues/364)
tracks that separate finding. Neither defect is fixed by this PR.

## Historical report and captures

`original-report.png` is the unmodified partner screenshot relayed by the owner
on 2026-11-06. Runtime version, extension state, OS, exact source and capture time
were unavailable; it proves reported literal notation, not its particular cause.

Root-level `math-regression-*` captures came from `ec218f2…`; root-level
`packaged-*` captures came from `cc71996…`, fresh PID 71769. They are retained
historically and are superseded by `adjacent-fix/` after the parser correction.
Earlier PNG suffixes on the CUA JPEGs and PNG-header-derived dimensions were
corrected without changing any image bytes; hashes and real dimensions are
recorded. Their older dirty collection identities are not current-head claims.

An early full run with all optional captures was stopped after AppKit dispatch
and animation starvation in recent-document lookup. The full run without optional
captures and focused current guide captures pass.
