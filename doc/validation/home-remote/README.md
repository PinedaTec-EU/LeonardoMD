# macOS Home validation

App source `58096da5fcc7df8c7276cf0a215d3d86a85076b2`, packaged QA build 0.3.2288 on macOS 27.2.1. Launch with `LEONARDO_SOURCE_PR=599 ./launch.sh --qa`; for an empty Home, use a disposable macOS profile without favorites, history or accepted shares. Open a new tab.

- [Projects with all sections expanded](home-empty.jpg) shows the order and the empty remote guidance.
- [Documents with Favorites and Recents collapsed](home-documents.jpg) shows that the selected type controls Open and that Remotes stays expanded.
- English, Leonardo Classic. Window 2520 by 1700 backing pixels, images reduced to 1150 pixels wide. Captured from the running native app at 17:13–17:15 CET on 2026-11-25.
- [Packaged remote preview and bilingual Help checks](https://github.com/PinedaTec-EU/LeonardoMD/pull/599#issuecomment-7166218977) used the same executable and a synthetic remote project.

| Route | Native capture | Context | Image metadata |
| --- | --- | --- | --- |
| Home / Projects | [Empty Remote](home-empty.jpg) | [Context](home-empty.context.json) | [Metadata](home-empty.metadata.json) |
| Home / Documents | [Independent disclosure](home-documents.jpg) | [Context](home-documents.context.json) | [Metadata](home-documents.metadata.json) |
| Home / Projects / Remotes | [Synthetic project catalogue](remote-catalogue.jpg) | [Context](remote-catalogue.context.json) | [Metadata](remote-catalogue.metadata.json) |
| Home / Documents / Remotes | [Direct document preview](remote-preview.jpg) | [Context](remote-preview.context.json) | [Metadata](remote-preview.metadata.json) |

The catalogue and preview were captured locally from the existing synthetic
LeonardoSyncQA project. Only the sheets are included to exclude unrelated
background content. The capture build and the reviewed version use the same
row selection, content and preview routes. The reviewed version extracts the
same Home item enumeration into a static method so the native acceptance
fixture can call it with a restarted offline controller.

The focused Swift test starts and stops a synthetic source on loopback. After
the peer restarts offline, it verifies that the Home project remains listed,
opens the cached document using the Home row's project ID and path, and checks
that the uncached row cannot open offline. This test passed locally. The capture
session used QA PID 36424 and exited normally. No Device Hub sessions were used.
