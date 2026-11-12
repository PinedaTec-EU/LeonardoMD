# PR #418 native UI evidence

These six captures show the production SwiftUI extension recommendation dialog and extension preference screen rendered in a native `NSHostingView` harness at source commit [`86e3e4258ce7a007df4f1f0a8ae46726378fd6b3`](https://github.com/PinedaTec-EU/LeonardoMD/commit/86e3e4258ce7a007df4f1f0a8ae46726378fd6b3). They use synthetic fixtures and contain no user document data. The dialog captures select Mermaid and Charts, leave Math, Citations, and Markdown extras unselected, and leave the global warning switch off. The reset captures show all five extensions off and the warning-reset action.

The capture is an element capture from `Native AppKit / SwiftUI NSHostingView`; there is no browser engine. The dialog viewport is 538 × 600 native points (1076 × 1200 image pixels); the preferences viewport is 560 × 820 native points (1120 × 1640 image pixels). OS: macOS 27.0.1 (Build 26A434). Exact capture timestamps, screen routes, states and image SHA-256 values are in each `.metadata.json` sidecar. `.context.json` records the observed capture context used by the canonical metadata helper.

| Screen | Language | Viewport | Captured at (UTC) | Image | Metadata |
| --- | --- | --- | --- | --- | --- |
| Recommendation dialog, global scope | English | 538 × 600 pt; 1076 × 1200 px | 2026-11-12 13:38:33.633 | [PNG](dialog-en-global.png) | [JSON](dialog-en-global.metadata.json) |
| Recommendation dialog, project scope | English | 538 × 600 pt; 1076 × 1200 px | 2026-11-12 13:38:34.005 | [PNG](dialog-en-project.png) | [JSON](dialog-en-project.metadata.json) |
| Extension preferences and warning reset | English | 560 × 820 pt; 1120 × 1640 px | 2026-11-12 13:38:34.371 | [PNG](reset-en.png) | [JSON](reset-en.metadata.json) |
| Recommendation dialog, global scope | Spanish | 538 × 600 pt; 1076 × 1200 px | 2026-11-12 13:38:42.239 | [PNG](dialog-es-global.png) | [JSON](dialog-es-global.metadata.json) |
| Recommendation dialog, project scope | Spanish | 538 × 600 pt; 1076 × 1200 px | 2026-11-12 13:38:42.589 | [PNG](dialog-es-project.png) | [JSON](dialog-es-project.metadata.json) |
| Extension preferences and warning reset | Spanish | 560 × 820 pt; 1120 × 1640 px | 2026-11-12 13:38:42.959 | [PNG](reset-es.png) | [JSON](reset-es.metadata.json) |

The recommendation captures were produced by `ExtensionRecommendationVisualTests.testNativeRecommendationAndResetCaptures` from the source checkout at the commit above. To reproduce both locales from that checkout:

```sh
LEONARDO_VISUAL_EVIDENCE=/tmp/leonardo-pr418-captures-en \
EVIDENCE_SHA=86e3e4258ce7a007df4f1f0a8ae46726378fd6b3 \
LEONARDO_NATIVE_CAPTURE_LANGUAGE=en \
swift test --skip-build --filter ExtensionRecommendationVisualTests

LEONARDO_VISUAL_EVIDENCE=/tmp/leonardo-pr418-captures-es \
EVIDENCE_SHA=86e3e4258ce7a007df4f1f0a8ae46726378fd6b3 \
LEONARDO_NATIVE_CAPTURE_LANGUAGE=es \
swift test --skip-build --filter ExtensionRecommendationVisualTests
```

The interaction smoke test and bilingual Help smoke test were performed separately in a fresh packaged QA app, as recorded in PR #418. This evidence-only commit adds no app source, resources, package inputs, scripts, or workflow changes; its parent is the source commit recorded above.
