# Inline form validation

Tracking: [#206](https://github.com/PinedaTec-EU/LeonardoMD/issues/206).

The approved composition is a document with in-place controls and optional right
field-help sidebar. The sidebar has help above and independent editability and
requiredness properties at its lower edge. It never duplicates inputs.

## Automated checks

Run `InlineFormTests` and `MarkdownFormStateTests` first, followed by `swift test`
using the repository compilation recorder for the source PR. The native test
hosts real `WorkspaceView` and WKWebView against the self-contained
`doc/format/examples/form-showcase/service-request.mdlr` fixture. It checks rapid
Unicode/IME input, repeated fields, immediate manual save, read-only rejection,
atomic batch validation, checkbox/switch persistence, contextual help, reopening,
Preview mode and clean PDF values. The bridge regressions reject stale sources,
unknown fields, wrong types and read-only changes. Existing package session tests
cover the shared guarded form updates through MDLZ save/reopen.

With `LEONARDO_VISUAL_EVIDENCE=/absolute/output/path` and `EVIDENCE_SHA=<full-head>`,
the native test writes `inline-forms/` with real light/dark WebKit document
captures (upper/lower scroll positions), separate native editable/read-only help
panels, PDF and provenance. CI supplies both variables and uploads the directory
in its exact-head preview artifact. Compare those captures to the approved mock;
mock images are design references, never validation evidence.

These are hosted native component tests, not proof of fresh packaged startup.
Do not terminate an owner's running LeonardoMD instance or disguise XCTest as
an app. Fresh-process QA, when independently authorized and possible, must use
`./launch.sh --qa` and respect product-wide single-instance ownership.

## Manual acceptance

1. Open the showcase response in Fill mode, with source protection still on.
2. Edit each type in place. Use Tab/Shift-Tab and activate `?` with the keyboard.
3. Consult Correo, then Referencia: the sidebar must switch from editable/required
   to read-only/optional. Close the panel and continue editing.
4. Enter invalid email, code and out-of-range hours; verify inline diagnostics.
   Save the draft, reopen it, correct the values and save again.
5. Check that both Nombre occurrences agree and that checkbox/switch values
   persist. Preview and PDF must show values without inputs/help chrome.
6. Repeat with the light and Graphite Glass palettes and narrow the window to
   verify form-only paragraphs reflow without clipping controls.

Numeric and text formulas are excluded and remain in
[#203](https://github.com/PinedaTec-EU/LeonardoMD/issues/203).
