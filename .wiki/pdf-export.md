# PDF export and preview replacement

Tracking: [#212](https://github.com/PinedaTec-EU/LeonardoMD/issues/212).

Preview/Split/Fill branches can overlap while SwiftUI reconciles native views.
An outgoing representable may receive a final update after the replacement
has attached. Never claim controller ownership from every update: that lets
the outgoing host steal export/scroll/edit ownership just before teardown.

`MarkdownPreviewCoordinator` binds once per representable/controller identity;
updates refresh callbacks without reclaiming ownership. A changed controller
rebinds explicitly. Dismantling detaches only the current host and resets ready
state asynchronously; stale teardown/readiness cannot affect its replacement.
Both macOS and iOS wrappers use this coordinator.

`PDFModeTransitionTests` mounts the production `WorkspaceView`, opens a portable
MDLZ with a local image and Mermaid, changes modes repeatedly, and checks PDF
text/diagram content without changing the source or dirty state. Optional
`LEONARDO_VISUAL_EVIDENCE` exports native WebKit snapshots and resulting PDFs.
This is a native test-runner fixture, not a packaged-app startup or hosted update
acceptance. Host-level PDF serialization and image policy are documented in
[image resources](image-resources.md).
