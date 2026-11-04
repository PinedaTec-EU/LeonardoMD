# Images, page objects and rubrics — #193

Issue: https://github.com/PinedaTec-EU/LeonardoMD/issues/193
PR: https://github.com/PinedaTec-EU/LeonardoMD/pull/316

The selected generated design is `../../design/193/selected-concept.png`.
It is a design reference, not product evidence.

## Real packaged-process evidence

Built source: `59b6b148fdae5b0f6789e119c0d6c965462846d7`.
These captures precede a storage-only hardening change. The final runtime source is
`35cec6d3a6d2008735dd8b70cc4b85ac8bfe53f1`; `final-source-and-bundle.json` records its hashes.
Only RubricLibrary read-latest locking and editor on-appear refresh changed after
the earlier captures; the rendering, geometry, toolbar and field behavior are unchanged.
A fresh final executable (PID 76850) opened the synthetic document and the menu canvas;
see [final canvas](native/final-library-canvas.jpg) and `final-startup.json`.
The later evidence commit changes no runtime source. The bundle remains
numeric version 0.1.765 during development; this does not claim publication.

`./launch.sh --qa --args --new-instance -allowMultipleInstances YES` produced a
real executable without XCTest linkage, verified/re-signed by `qa-bundle.py`.
Fresh PID 56028 showed and operated its first window; the installed user process
69025 stayed running. `startup.json` retains that process's startup events.
The multiple-instance choice was process-local, not a stored preference change.
The task-owned QA process was closed after validation.

1. [Selected rubric and floating controls](native/selected-object.jpg): dark
   native app, synthetic document, dropdown mode, independent selection border,
   X/Y/Z and collapsed size/page controls.
2. [Mode dropdown](native/mode-dropdown.jpg): Preview / Edit / Split share one
   control. Accessibility inspection exposed one Mode element with active value.
3. [Expanded protected-field canvas](native/form-canvas.jpg): a writable rubric
   field opens a native dialog while the source stays protected. Synthetic line;
   library opt-in is off.
4. [Saved protected-field answer](native/protected-field-filled.jpg): Fill,
   source padlock protected, saved field-bounded ink. Source-body and definition
   semantics were checked afterward; see `protected-form-result.json`.

JPEGs are original Computer Use captures. Context files record UTC times,
measured image pixel dimensions and hashes. Computer Use did not expose native
point or embedded-browser viewport dimensions/version. The shared browser
sidecar helper requires a CSS viewport, so it was not used to invent one for
these native-process captures. That measurement limit is explicit.

An earlier exploratory packaged process also created, saved and inserted a
menu-created rubric and showed it in the saved library. The task-created entry
was removed afterward, preserving a recovery copy outside the repository.
Final protected-field validation opted out of library saving and left it empty.
All documents and ink were synthetic; no personal signature or legal signing.

## Contract and automated evidence

| Criterion | Direct checks |
| --- | --- |
| Coordinates, order, portable strokes | `LeonardoGraphicTests` round trip, malformed geometry/source/ID and ink budgets |
| Library concurrency | `testIndependentLibrariesMergeWritesAndFailClosedOnCorruption`: two independent stores preserve add/delete, busy lock rejects, corrupt bytes preserved; all five RubricSessionTests passed on final source |
| Protected fields and history | `RubricSessionTests`: source protection, stale request, bounded field mutation, undo/redo and save |
| Imported images and packages | transparent image normalization, relocated MDLZ with original source removed, package save, symlink rejection |
| Page token and rendering | `GraphicRuntimeTests`: standalone page token, inline/code exclusion, malformed draft ink, legacy absolute-image origin, Z/definition order and floating selection |
| PDF | [Two-page vector PDF](current-component/graphics/page-objects.pdf); PDFKit page/text/physical-size assertions and [rendered page 1](current-component/rendered/page-1.png), [page 2](current-component/rendered/page-2.png) |
| Overflow | oversized block is marked and PDF export fails explicitly instead of clipping |
| Help | English/Spanish production-component captures, v7 deterministic guides, actual WKWebView images and practice/navigation checks |
| Platform | macOS Swift suite and generic iOS Simulator companion build |

Full local Swift validation passed: 597 XCTest cases (32 intentional opt-in
skips) plus 28 Swift Testing cases. Subsequent focused controls/PDF tests passed.
Python: 38 plugin tests, 52 script tests (7 shared-engine opt-in skips), and
20 packaging tests passed. Compilation invocations are recorded exclusively in
the PR ledger entry; evidence comments obtain that count from committed HEAD.

Help screenshots in `doc/guide/{en,es}/assets` are original instructional
component captures with isolated synthetic libraries, not fresh-process proof.

## Limits and follow-up

- Page flow breaks at blocks. Split an over-height block before export; text
  edits never reposition page objects automatically.
- Plain Markdown requires explicit MDLF conversion for placement. Its reading
  export omits rubric ink and page objects.
- Library sync, pressure hardware, cryptographic signing and Preview private
  signature access are outside scope. Stroke color is preserved, so choose ink
  suitable for the document's actual paper/background color.
- Existing metadata-inflated word counts are tracked separately in
  [#317](https://github.com/PinedaTec-EU/LeonardoMD/issues/317).
- No merge, release, hosted update or mobile pairing acceptance is claimed.
