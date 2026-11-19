# PR #473 — current packaged UI evidence

These captures use the product code at `041c4faa3bcf992890f2cc847926e394f07b957a`.
The follow-up PR commit adds only this evidence and the compilation-ledger
entry; it does not change product code.

## macOS Help and practice

- LeonardoMD QA `0.3.1894` / build `1894`, bundle
  `eu.pinedatec.LeonardoMD.qa.6038627454684a31acc99874e1bf5fca8`, process PID
  `37428` (started 2026-11-19 15:19:17 Europe/Madrid), macOS `27.0.1`.
- The real native Help menu opened Guide v103 EN and ES in the same instance.
  The app-window captures are `2744 × 1924` pixels (`1372 × 962` points at 2×);
  no browser is involved. Entry route: **Help → Leonardo user guide**.
- With Math enabled, the live guides were checked for Mermaid, inline and
  display math, the multiline tagged box-counting equation `(1)`, charts,
  local images and tables. The Spanish captures below show Mermaid, the tagged
  equation and chart, and the table/image examples. The English guide was also
  opened and inspected in the same process. With Math disabled, formulas and
  Markdown-sensitive TeX remained literal and code examples stayed literal;
  the original extension settings were restored.
- The practice link first opened the pre-existing English form. It was left
  byte-identical (SHA-256
  `12c375b7b6889d1a86a05efa76d51b67119acd359760105ae504ccc9ef48b662`). A
  separate temporary copy was filled with synthetic data, saved, closed and
  reopened in the same app. The screenshot shows the reopened values. No
  user-owned practice data is present in the capture.
- Preferences showed **Show non-document files** off. The preference off/on
  and image-row behavior captures remain in
  [`exact-head-74290fa2`](../exact-head-74290fa2/README.md); this current run
  restored and rechecked the off state.
- The task-owned process was quit normally and verified absent before handoff.

| State | Capture |
| --- | --- |
| Guide v103 English, opened through Help | [macos-help-en-v103.jpg](macos-help-en-v103.jpg) |
| Guide v103 Spanish, opened through Help | [macos-help-es-v103.jpg](macos-help-es-v103.jpg) |
| Spanish Mermaid and inline math | [macos-help-es-mermaid.jpg](macos-help-es-mermaid.jpg) |
| Spanish tagged equation `(1)` and chart | [macos-help-es-tagged-equation-chart.jpg](macos-help-es-tagged-equation-chart.jpg) |
| Spanish table and local image | [macos-help-es-table-image.jpg](macos-help-es-table-image.jpg) |
| English practice answers after save, close and reopen | [macos-practice-en-reopened.jpg](macos-practice-en-reopened.jpg) |

## Little Leonardo read-only documents

The following attachments came from
`PairingUITests/testNativeDirectEnrollmentRefreshOfflineRetentionRetryAndRevocation()`
on the fresh iPhone 17 simulator `4C448AE1-1736-4047-BCC1-0F9B3CA82182`, in
`qa-pr473-direct-20261119-run3/ReceivedDocuments.xcresult`. They show received
`.mdlf` and `.mdlr` documents rendered read-only. The screenshots are
`1206 × 2622` pixels. The full UI-test result and source metadata remain in the
local QA artifact directory.

| State | Capture |
| --- | --- |
| Received MDLF rendered read-only | [ios-mdlf-read-only.png](ios-mdlf-read-only.png) |
| Received MDLR rendered read-only | [ios-mdlr-read-only.png](ios-mdlr-read-only.png) |

See [`captures.metadata.json`](captures.metadata.json) for image hashes,
dimensions, app identity, capture route and state metadata.
