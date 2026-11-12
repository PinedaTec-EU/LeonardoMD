# Local image resource policy

Tracking: [#243](https://github.com/PinedaTec-EU/LeonardoMD/issues/243).

`MarkdownDocumentSchemeHandler` resolves allowed local paths or immutable corpus
assets, then delegates bounded loading to a per-web-view `MarkdownImageLoader`
actor. Stop/teardown cancels delivery; the actor serializes reads and ImageIO
work. New render generations reset admission; WebKit stop/teardown retires requests.
A pending image can be reused across a DOM update and must still complete. Repeated
full-URL/content/target variants share an admission entry; no image cache is retained.

`MarkdownImagePolicy` holds the limits: 16 KiB URL metadata, 32 MiB input, 2 MiB SVG, 40 million
source pixels, 4 million preview pixels, 16 million PDF pixels, animations with
at most 128 frames and 4 million total canvas pixels, 128 MiB estimated admitted
cost, 256 variants and 256 pending requests. Cost uses an 8-byte pixel allowance.
These are admission/work limits, not total process resident-memory bounds.

Static rasters use ImageIO thumbnail creation with source caching disabled.
Preview resolution follows viewport dimensions, device scale and current page
zoom at request time; it does not reload automatically on later window/zoom
changes. `image-loading.js` requests a separate PDF variant from rendered CSS
bounds at 300 dpi, with hard pixel/side limits, freezes its display dimensions,
and restores preview source selection/styles afterward. Original assets are
never rewritten. SVG stays vector; bounded animations keep their original bytes.

Failures keep authored alt text; PDF asset readiness rejects missing images.
Memory corpus bytes exist before this boundary. Remote/data images and arbitrary
SVG path/filter complexity are outside its raster policy. Native codec/WebKit
internal allocations and transient old/new document overlap are not measured or
strictly bounded by the cost estimate.

Regression coverage: `MarkdownImageLoaderTests`, `MarkdownImageSchemeTests` and
real `WebKitRuntimeTests` for raster/PDF quality, restoration and failure behavior.
See [validation and limits](../doc/validation/image-resources.md).

PDF exports are serialized per preview host, including awaited restoration before
the next export starts. Queued cancellation returns without waiting for the active
export; teardown fails queued/native requests and isolates late callbacks from
a replacement view.

macOS image menus preserve WebKit copy/subject/share items. `MarkdownImageWebView`
replaces open/save actions by their WebKit tags, capturing the selected image URL
in an isolated content world. Local image windows use the existing bounded image
loader; save sheets export original bytes through its bounded reader. Both reuse
the document scheme handler’s memory/path confinement, never temporary package
URLs handed to another application. Errors appear as native alerts.
Tracking: [#295](https://github.com/PinedaTec-EU/LeonardoMD/issues/295).

Opt-in native action QA: `LEONARDO_IMAGE_EVIDENCE=/tmp/image-actions swift test
--skip-build --filter MarkdownImageContextVisualTests` after a recorded compilation.
It opens a real MDLZ in `MarkdownPreviewHost`, presents the image/save windows,
finishes the sheet through AppKit and checks original bytes plus cancellation.
Set the disposable save directory before presenting the panel; the remote panel
ignores later setters. `NSSavePanel.ok` is unimplemented. Native/XPC window
evidence uses window capture rather than `cacheDisplay`, which omits the remote UI.
