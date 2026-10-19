# Native MDLF image background and Preview editing

Tracking: [issue #196](https://github.com/PinedaTec-EU/LeonardoMD/issues/196),
[PR #197](https://github.com/PinedaTec-EU/LeonardoMD/pull/197).

## Reproduction and disposition

The installed `/Applications/LeonardoMD.app` reported **0.1.441 beta** and
reproduced the absent-background/generic-metadata result, including after a
normal quit and fresh launch. Source inspection alone did not establish why
that installed binary behaved differently.

A clean release compilation of current main-based source loaded the same MDLF
background correctly. No runtime renderer patch was needed to obtain this
result. This change adds the missing reproducible fixture, native regression
coverage and user instructions; it does not claim to repair or replace the
installed 0.1.441 artifact or identify its binary/source discrepancy.

## Packaged native acceptance — 2026-10-19

- Build command: `LEONARDO_SOURCE_PR=197 ./launch.sh --qa <invoice.mdlf>`.
- Real executable: `LeonardoMD`, checked by `scripts/qa-bundle.py`, with packaged
  resources and Sparkle framework; no XCTest framework in the GUI executable.
- QA bundle numeric metadata: **0.1.445**. Its channel label was **stable** from
  local packaging defaults; this is a local QA candidate, not a published
  stable release. Source runtime baseline: `efd35b9`.
- New process PID: **21357**, from a disposable `LeonardoMDQA.app` bundle.
  The owner authorized normal termination of the installed instance. Fresh
  startup produced a real window; acceptance was not forwarded to that instance.
- Input: `/tmp/Leonardo-factura-imagen-real/Factura-con-imagen-de-fondo.mdlf`
  and its real `assets/membrete.svg`. The committed equivalent lives under
  `doc/format/examples/invoice/`.
- Preview displayed the SVG letterhead, logo and watermark beneath the Markdown
  invoice. The image contains no SVG text elements.
- Unlocked the toolbar padlock, selected the customer in Preview, replaced it
  with **CLIENTE VALIDADO DESDE PREVIEW**, and pressed **⌘S**.
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
It verifies image decoding, the Preview-to-session editing bridge, persistence,
exact preservation of all source bytes outside the changed customer, metadata
preservation, reopen rendering, and PDF production. With
`LEONARDO_VISUAL_EVIDENCE` set, it captures the reopened preview, PDF and head
provenance under `mdlf-background/` for CI review.

A hosted XCTest test is not a replacement for fresh-process native acceptance.
The packaged GUI validation above is recorded separately for that reason.
