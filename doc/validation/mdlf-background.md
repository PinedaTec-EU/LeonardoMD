# Native MDLF image background and Preview editing

Tracking: [issue #196](https://github.com/PinedaTec-EU/LeonardoMD/issues/196),
[PR #197](https://github.com/PinedaTec-EU/LeonardoMD/pull/197).

## Root cause and correction

With **Show metadata** enabled, `MarkdownHTMLShell.payloadJSON` parsed the
complete MDLF source through the generic Markdown front-matter parser. That
created a tall panel containing technical JSON keys and displaced the invoice
and its image background below the first viewport. The initial report that the
image did not load was incomplete: inspection of public beta 0.1.445 confirmed
the image below the metadata panel.

The installed **0.1.441 beta** executable matches the public 0.1.441 archive
(SHA-256 `b369fb607bc9548ec97ef2709151b7a558fc8d9fa8b7dcb74b5133a226778d02`).
A first QA build did not show the problem because its fresh preference domain
had Show metadata off. This was a masked condition, not evidence that a clean
build alone repaired the defect.

The correction parses opted-in MDLF once and builds the generic preview view
of its body without routing its JSON envelope through Markdown metadata parsing.
The full original source and typed Leonardo layout still reach the renderer
and editing bridge. Standard Markdown keeps its existing front matter and tags.
The regression explicitly enables **Show metadata** and failed before this fix.

Migration of original Markdown/YAML content belongs to
[issue #191](https://github.com/PinedaTec-EU/LeonardoMD/issues/191); this change
does not implement that migration or a replacement metadata inspector.

## Packaged native acceptance — 2026-10-19

- Build command: `LEONARDO_SOURCE_PR=197 ./launch.sh --qa <invoice.mdlf>`.
- Real executable: `LeonardoMD`, checked by `scripts/qa-bundle.py`, with packaged
  resources and Sparkle framework; no XCTest framework in the GUI executable.
- QA bundle numeric metadata: **0.1.445**. Its channel label was **stable** from
  local packaging defaults; this is a local QA candidate, not a published
  stable release. Source base: `efd35b9`, with the PR #197 metadata correction applied.
- Fresh process identity is recorded in the capture provenance for the final
  disposable `LeonardoMDQA.app` bundle.
  The owner authorized normal termination of the installed instance. Fresh
  startup produced a real window; acceptance was not forwarded to that instance.
- Input: `/tmp/Leonardo-factura-imagen-real/Factura-con-imagen-de-fondo.mdlf`
  and its real `assets/membrete.svg`. The committed equivalent lives under
  `doc/format/examples/invoice/`.
- With **Show metadata enabled**, Preview displayed the SVG letterhead, logo
  and watermark beneath the Markdown invoice without a technical JSON panel.
  The image contains no SVG text elements.
- Unlocked the toolbar padlock, selected the customer in Preview, replaced it
  with **CLIENTE VALIDADO MDLF CORREGIDO**, and pressed **⌘S**.
- Closed the document tab, reopened the same MDLF through the app, and observed
  both the background and the changed customer. Read back the saved MDLF to
  verify the native image reference, changed body and absence of HTML markup.
- Exported PDF from the reopened document using the native export action and
  rendered it with Poppler. The letterhead, watermark and edited customer are
  visible. This is single-document evidence, not multipage print-layout proof.

Native screenshots and PDF evidence are captured alongside this record.
The source/head and bundle digest are recorded in `mdlf-background/provenance.json`.

## Automated regression

`Tests/LeonardoAppTests/MDLFBackgroundPreviewTests.swift` hosts `WorkspaceView`
and its real WKWebView with a temporary copy of the committed MDLF invoice.
With Show metadata enabled, it verifies absence of the generic JSON panel,
image decoding, the Preview-to-session editing bridge, persistence,
exact preservation of all source bytes outside the changed customer, metadata
preservation, reopen rendering, and PDF production. With
`LEONARDO_VISUAL_EVIDENCE` set, it captures the reopened preview, PDF and head
provenance under `mdlf-background/` for CI review.

A hosted XCTest test is not a replacement for fresh-process native acceptance.
The packaged GUI validation above is recorded separately for that reason.
