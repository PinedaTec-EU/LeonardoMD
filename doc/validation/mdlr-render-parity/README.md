# MDLR render parity

Tracking: [#234](https://github.com/PinedaTec-EU/LeonardoMD/issues/234).

Captured on 2026-10-20 from the real hosted WorkspaceView/WKWebView using the synthetic service-request.mdlr fixture. Native macOS WebKit; 1440 × 1024 point host window. The help sidebar reduces the Preview viewport; Split additionally reserves the source editor. The document responds to those available widths using the same form layout. Dark Graphite Glass palette, Spanish labels; invalid email intentionally tests diagnostics.

- [Fill](fill.png)
- [Preview](preview.png)
- [Split preview pane](split.png)

Run `LEONARDO_VISUAL_EVIDENCE=/tmp/leonardo-evidence python3 scripts/compile-and-record.py --pr-number 235 -- swift test --filter InlineFormTests` to reproduce. Captures are WebKit component evidence, not fresh packaged-process acceptance. The owner’s running application is untouched.

The regression verifies all eleven input occurrences remain present in Preview/Split and are disabled. Simulated regular and composing events cannot modify the session or saved response. Fill still accepts editing, repeated numeric drafts, save/reopen and PDF export. PDF retains plain values and omits generated form labels and controls.
