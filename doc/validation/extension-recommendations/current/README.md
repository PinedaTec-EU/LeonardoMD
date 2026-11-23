# Canonical guide and extension captures

Capture/build source: `b8900bf14f17aba18e4e89cb141c392048a5314f` (clean checkout).
Tracking: [#310](https://github.com/PinedaTec-EU/LeonardoMD/issues/310), [PR #311](https://github.com/PinedaTec-EU/LeonardoMD/pull/311).

The recorded focused compiler-bearing run built the committed product/test/resource
sources. After committing that unchanged source plus its compilation allocation,
the four guide tests ran with `swift test --skip-build --filter BundledUserGuideTests`.
The native capture test ran separately for each locale using `swift test --skip-build
--filter ExtensionRecommendationVisualTests` and `LEONARDO_NATIVE_CAPTURE_LANGUAGE=en`
or `es`. Each run used
`EVIDENCE_SHA=b8900bf14f17aba18e4e89cb141c392048a5314f` and an external evidence
directory. All runs passed. Isolating native locales avoids the known cached-text capture artifacts when switching interface language within one process. No recompilation or new build allocation was made for
this evidence-only run.

Each original PNG has its original `.context.json`, recorded in the capture
workflow with observed capture-start UTC time and measured viewport. Native
controls use a directly measured native-point equivalent for the common helper's
CSS-viewport field, explicitly labeled as such; there is no native browser or CSS
engine. WKWebView captures report JavaScript `innerWidth`/`innerHeight` and the
reported User-Agent, identifying engine compatibility tokens without inferring a
Safari or OS version. Raw context retains native dimensions and directly reported
OS information.

Immediately after capture, the canonical shared
`pr-judge-delivery/scripts/capture_metadata.py` helper generated each
`.metadata.json` from that original image/context and the clean source checkout.
The helper binds image SHA-256, actual file dimensions, capture time and source
revision/dirty-state indicators. `collected_at` is the helper's collection time,
separate from `capture.captured_at`. All fourteen sidecars were verified against
the original file hashes and clean source revision before copying this bundle.
No original image was resized, cropped, annotated or composited.

The evidence-only commit following this source adds only this bundle and the
validation README. Product code, tests, resources, manifests, scripts and build
inputs remain identical to the capture/build source. Verify the mapping against
the reviewed head; any later product/build-input change requires fresh captures.
The current-head CI artifact is supplemental; this canonical bundle is the
author-owned provenance evidence for the mapped source.

These are real native SwiftUI/WKWebView component captures with synthetic guide
answers. They demonstrate the displayed UI, not a fresh packaged-process startup,
installation or released deployment. Native interaction/persistence tests provide
the separate behavior evidence; the images and sidecars alone do not prove it.
All capture modes below are `element`; exact screen/route, state, browser/engine
report and data provenance are in each linked sidecar and original context.

| Original capture | Viewport (CSS / labeled native-point equivalent) | PNG pixels | Observed UTC capture time | Image SHA-256 | Canonical sidecar |
|---|---|---|---|---|---|
| [dialog-en-global.png](dialog-en-global.png) | 538×600 | 1076×1200 | 2026-10-31T09:39:59.127000+00:00 | `5fdf4bdbb7b9fce2a091f96d5a25e5b52769bda2a389d7f69317c96bb13b4630` | [JSON](dialog-en-global.metadata.json) |
| [dialog-en-project.png](dialog-en-project.png) | 538×600 | 1076×1200 | 2026-10-31T09:39:59.314000+00:00 | `b66fc05aaa6dbcc9a0dc30b137cca55705d5659495f985a7cc76491ebcad0aaf` | [JSON](dialog-en-project.metadata.json) |
| [reset-en.png](reset-en.png) | 560×820 | 1120×1640 | 2026-10-31T09:39:59.526000+00:00 | `cee76b3f7c509cafb942ce174229de05dbdf561fe2442b1aa8333835c90b9bb4` | [JSON](reset-en.metadata.json) |
| [dialog-es-global.png](dialog-es-global.png) | 538×600 | 1076×1200 | 2026-10-31T09:40:05.264000+00:00 | `0d3c29253bbc8e7e3f8e6636c7e3080b37352bdec5f3b817dedc364f23f3d0e0` | [JSON](dialog-es-global.metadata.json) |
| [dialog-es-project.png](dialog-es-project.png) | 538×600 | 1076×1200 | 2026-10-31T09:40:05.442000+00:00 | `4eaaf9a0ce46ec2293deb221bd3b0794ab5fa7d5a1ee97373000c976033ee540` | [JSON](dialog-es-project.metadata.json) |
| [reset-es.png](reset-es.png) | 560×820 | 1120×1640 | 2026-10-31T09:40:05.638000+00:00 | `6dda137a6124e7357ed647f19c12db376c056f0362163e05c69d1f8bb5810855` | [JSON](reset-es.metadata.json) |
| [chart-en.png](chart-en.png) | 1100×517 | 2200×1034 | 2026-10-31T09:40:12.708000+00:00 | `2bd9f374cb364bafecd821bce78ee935a9f9ab2599487a9930defc5620e80eb0` | [JSON](chart-en.metadata.json) |
| [chart-es.png](chart-es.png) | 1100×491 | 2200×982 | 2026-10-31T09:40:13.888000+00:00 | `75bb06c89016057fcc6052ab1083031985accb0e25b5cd339ef79079c793afd4` | [JSON](chart-es.metadata.json) |
| [diagram-en.png](diagram-en.png) | 1100×517 | 2200×1034 | 2026-10-31T09:40:12.652000+00:00 | `3730ad6ccdc784f881f534abb2c3b260ab2d05fed783a8569c5d19e3c5f60928` | [JSON](diagram-en.metadata.json) |
| [diagram-es.png](diagram-es.png) | 1100×491 | 2200×982 | 2026-10-31T09:40:13.843000+00:00 | `efe8476efe7b25b86aab77fc006c0eca52c71d7f8a958422c9810fe8b809d452` | [JSON](diagram-es.metadata.json) |
| [guide-en.png](guide-en.png) | 1100×517 | 2200×1034 | 2026-10-31T09:40:12.728000+00:00 | `ecbd0958cf571c60bce059d02c441f8a9abcbc486de6228a8c10f9cd749f8860` | [JSON](guide-en.metadata.json) |
| [guide-es.png](guide-es.png) | 1100×491 | 2200×982 | 2026-10-31T09:40:13.910000+00:00 | `f4207300469ca09fb3352c236edfb5704b84c317f37295c9021ab5f9c06cd3b3` | [JSON](guide-es.metadata.json) |
| [math-en.png](math-en.png) | 1100×517 | 2200×1034 | 2026-10-31T09:40:12.683000+00:00 | `0104b4fcab31a36835d3eace71a2c28db6ea2bbf0da240ad909098a19b2853fd` | [JSON](math-en.metadata.json) |
| [math-es.png](math-es.png) | 1100×491 | 2200×982 | 2026-10-31T09:40:13.867000+00:00 | `a176f4d59a355635f218b4c8bc697dbb0ae01595b3a77f59300b5ce7e0a7de0e` | [JSON](math-es.metadata.json) |
