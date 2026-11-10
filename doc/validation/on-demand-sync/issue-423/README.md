# Issue #423 validation

Reviewed source: `052feadc5c2991892b96f6a20a26e000306c5830`

The shared catalogue component was captured from that exact source with
synthetic data. The root shows only the immediate folders `notes` and
`reference`; descendant files are not flattened into the root. The English
and Spanish captures also show the existing cache and offline-retention
states used by the production view.

| Capture | Original | Context | Metadata |
|---|---|---|---|
| English catalogue and cache controls | [PNG](downloads-en.png) | [JSON](downloads-en.context.json) | [sidecar](downloads-en.metadata.json) |
| Spanish catalogue and cache controls | [PNG](downloads-es.png) | [JSON](downloads-es.context.json) | [sidecar](downloads-es.metadata.json) |

Capture mode is native AppKit/SwiftUI component rendering at 1180×640 native
points and 2360×1280 image pixels. Data is synthetic. The capture time, OS,
route, state and image SHA-256 are recorded in each sidecar. The source
checkout was clean at capture time.

The real release bundle was built from the same source SHA and passed the
packaging inspection: executable `LeonardoMD`, version `0.3.1276`, no
`XCTest.framework` dependency, signed helper and Sparkle framework present.
The inspection record is [package-inspection.json](package-inspection.json).

The fresh packaged-process first-window and bundled Help smoke test remain
pending because the installed LeonardoMD instance already owns the product-wide
single-instance process. Launching the disposable QA copy forwarded/exited
without a new first-window process; the owner instance was not terminated.
