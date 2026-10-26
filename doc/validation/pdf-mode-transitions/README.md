# PDF export after mode changes

Tracking: [#212](https://github.com/PinedaTec-EU/LeonardoMD/issues/212).

`PDFModeTransitionTests` runs the actual `WorkspaceView` in a native 1000 × 700
point NSWindow. The fixture opens an MDLZ with a local blue SVG and a Mermaid
flowchart. Mermaid is explicitly enabled in its isolated preferences. It
switches Preview → Split → Preview → Split → Preview and exports after each
replacement attaches and its image loads. PDFKit verifies the heading and
rendered diagram labels, rejects diagram source text, and verifies unchanged
source/dirty state. Controller tests cover late outgoing updates, teardown,
stale readiness, callback refresh, controller replacement and removal.

The attached PNGs are native WKWebView snapshots of the last Preview and Split
states; PDFs are their actual exports. The window includes native chrome and
app controls outside the captured WebKit viewport. No browser or generated
mockup is involved. Preview is 2000 × 682 pixels; Split is 998 × 682 pixels
on the local 2× display. The synthetic blue rectangle and Inspect → Export
diagram appear in both preview and PDF. These captures establish renderer
behavior, not fresh packaged-app startup or hosted installation acceptance.

From the reviewed source checkout, reproduce without compiling again:

```sh
LEONARDO_VISUAL_EVIDENCE=/tmp/leonardo-pdf-evidence swift test --skip-build --filter PDFModeTransitionTests
```

If a build is needed, use the repository compilation recorder with the source
PR number. Captures are written to `pdf-mode-transitions/` inside the requested
evidence directory. Use XCTest through `swift test`; do not launch the test
executable as a standalone app. The PR records the exact reviewed SHA and its
post-commit evidence run.
