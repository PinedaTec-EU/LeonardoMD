# Guide v4 and recommendations: original review captures

Capture/build source: `9f4a27f4b681be3592b5f02a1b52aae3bf0608de`. All 22 canonical sidecars were generated from
that clean checkout; tracked and untracked dirty indicators are false.
The already-built Swift sources, tests, resources and package inputs match
this source. Later commits in this evidence-only bundle change documentation
under `doc/validation/` only; verify that mapping before using these captures
for a later reviewed head. Historical v3 captures remain in their old directory.

## What was checked

- Both localized v4 packages open through the actual native document flow.
- Eleven local images load in each package; three live engines render without errors.
- Practice answers save; reopening preserves them; v2/v3 copies remain untouched.
- Header, Mermaid, math, chart, practice fields and three illustrated chapters
  were visually inspected in each locale. The long images in chapter captures
  extend beyond the viewport and remain scrollable; original full instructional
  PNGs are in `doc/guide/<locale>/assets/`.
- Global/project consent dialogs and warning reset components are readable in
  both languages. Those captures show actual components with synthetic data;
  lifecycle/scope tests establish the interactions, not static pictures alone.

WKWebView reports engine compatibility User-Agent:
`Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko)`.
This is not an observed host macOS version. For native captures the shared
`viewport_css` field is explicitly the measured native-point equivalent,
with CSS/browser version not applicable. Every image is an element capture;
all data is synthetic. Actual capture time is distinct from sidecar collection time.

| Original / sidecars | Screen and state | Browser; viewport | Pixels | UTC capture time; SHA-256 |
| --- | --- | --- | --- | --- |
| [dialog-en-global](dialog-en-global.png) · [metadata](dialog-en-global.metadata.json) · [context](dialog-en-global.context.json) | /native/extensions/dialog-en-global; Extension consent, global scope; language en; synthetic fixture; viewport_css is the measured native-point equivalent; CSS is not applicable | Native AppKit/SwiftUI (browser N/A); 538×600; element | 1076×1200 | 2026-10-31T10:31:04.606000+00:00; `5fdf4bdbb7b9fce2a091f96d5a25e5b52769bda2a389d7f69317c96bb13b4630` |
| [dialog-en-project](dialog-en-project.png) · [metadata](dialog-en-project.metadata.json) · [context](dialog-en-project.context.json) | /native/extensions/dialog-en-project; Extension consent, project scope; language en; synthetic fixture; viewport_css is the measured native-point equivalent; CSS is not applicable | Native AppKit/SwiftUI (browser N/A); 538×600; element | 1076×1200 | 2026-10-31T10:31:04.796000+00:00; `b66fc05aaa6dbcc9a0dc30b137cca55705d5659495f985a7cc76491ebcad0aaf` |
| [dialog-es-global](dialog-es-global.png) · [metadata](dialog-es-global.metadata.json) · [context](dialog-es-global.context.json) | /native/extensions/dialog-es-global; Extension consent, global scope; language es; synthetic fixture; viewport_css is the measured native-point equivalent; CSS is not applicable | Native AppKit/SwiftUI (browser N/A); 538×600; element | 1076×1200 | 2026-10-31T10:31:05.431000+00:00; `0d3c29253bbc8e7e3f8e6636c7e3080b37352bdec5f3b817dedc364f23f3d0e0` |
| [dialog-es-project](dialog-es-project.png) · [metadata](dialog-es-project.metadata.json) · [context](dialog-es-project.context.json) | /native/extensions/dialog-es-project; Extension consent, project scope; language es; synthetic fixture; viewport_css is the measured native-point equivalent; CSS is not applicable | Native AppKit/SwiftUI (browser N/A); 538×600; element | 1076×1200 | 2026-10-31T10:31:05.625000+00:00; `4eaaf9a0ce46ec2293deb221bd3b0794ab5fa7d5a1ee97373000c976033ee540` |
| [reset-en](reset-en.png) · [metadata](reset-en.metadata.json) · [context](reset-en.context.json) | /native/extensions/reset-en; Extension preferences and warning reset; language en; synthetic fixture; viewport_css is the measured native-point equivalent; CSS is not applicable | Native AppKit/SwiftUI (browser N/A); 560×820; element | 1120×1640 | 2026-10-31T10:31:05.004000+00:00; `cee76b3f7c509cafb942ce174229de05dbdf561fe2442b1aa8333835c90b9bb4` |
| [reset-es](reset-es.png) · [metadata](reset-es.metadata.json) · [context](reset-es.context.json) | /native/extensions/reset-es; Extension preferences and warning reset; language es; synthetic fixture; viewport_css is the measured native-point equivalent; CSS is not applicable | Native AppKit/SwiftUI (browser N/A); 560×820; element | 1120×1640 | 2026-10-31T10:31:05.823000+00:00; `6dda137a6124e7357ed647f19c12db376c056f0362163e05c69d1f8bb5810855` |
| [chart-en](chart-en.png) · [metadata](chart-en.metadata.json) · [context](chart-en.context.json) | /native/user-guide/en; Live chart example; built-in extension enabled; language en | WKWebView; 1100×517; element | 2200×1034 | 2026-10-31T10:30:59.662000+00:00; `2bd9f374cb364bafecd821bce78ee935a9f9ab2599487a9930defc5620e80eb0` |
| [chart-es](chart-es.png) · [metadata](chart-es.metadata.json) · [context](chart-es.context.json) | /native/user-guide/es; Live chart example; built-in extension enabled; language es | WKWebView; 1100×491; element | 2200×982 | 2026-10-31T10:31:02.692000+00:00; `75bb06c89016057fcc6052ab1083031985accb0e25b5cd339ef79079c793afd4` |
| [diagram-en](diagram-en.png) · [metadata](diagram-en.metadata.json) · [context](diagram-en.context.json) | /native/user-guide/en; Live diagram example; built-in extension enabled; language en | WKWebView; 1100×517; element | 2200×1034 | 2026-10-31T10:30:59.209000+00:00; `3730ad6ccdc784f881f534abb2c3b260ab2d05fed783a8569c5d19e3c5f60928` |
| [diagram-es](diagram-es.png) · [metadata](diagram-es.metadata.json) · [context](diagram-es.context.json) | /native/user-guide/es; Live diagram example; built-in extension enabled; language es | WKWebView; 1100×491; element | 2200×982 | 2026-10-31T10:31:02.202000+00:00; `efe8476efe7b25b86aab77fc006c0eca52c71d7f8a958422c9810fe8b809d452` |
| [guide-en](guide-en.png) · [metadata](guide-en.metadata.json) · [context](guide-en.context.json) | /native/user-guide/en; Guide preview; all local images loaded; language en | WKWebView; 1100×517; element | 2200×1034 | 2026-10-31T10:31:00.614000+00:00; `ecbd0958cf571c60bce059d02c441f8a9abcbc486de6228a8c10f9cd749f8860` |
| [guide-es](guide-es.png) · [metadata](guide-es.metadata.json) · [context](guide-es.context.json) | /native/user-guide/es; Guide preview; all local images loaded; language es | WKWebView; 1100×491; element | 2200×982 | 2026-10-31T10:31:03.671000+00:00; `f4207300469ca09fb3352c236edfb5704b84c317f37295c9021ab5f9c06cd3b3` |
| [math-en](math-en.png) · [metadata](math-en.metadata.json) · [context](math-en.context.json) | /native/user-guide/en; Live math example; built-in extension enabled; language en | WKWebView; 1100×517; element | 2200×1034 | 2026-10-31T10:30:59.436000+00:00; `0104b4fcab31a36835d3eace71a2c28db6ea2bbf0da240ad909098a19b2853fd` |
| [math-es](math-es.png) · [metadata](math-es.metadata.json) · [context](math-es.context.json) | /native/user-guide/es; Live math example; built-in extension enabled; language es | WKWebView; 1100×491; element | 2200×982 | 2026-10-31T10:31:02.447000+00:00; `a176f4d59a355635f218b4c8bc697dbb0ae01595b3a77f59300b5ce7e0a7de0e` |
| [practice-en](practice-en.png) · [metadata](practice-en.metadata.json) · [context](practice-en.context.json) | /native/user-guide/en; Practice fields scrolled into view; synthetic answers; language en | WKWebView; 1100×517; element | 2200×1034 | 2026-10-31T10:31:00.865000+00:00; `6eb22900fa54b3048ced8fdb0281a1f6e5cb251d515f6e14468f9e843d871ddf` |
| [practice-es](practice-es.png) · [metadata](practice-es.metadata.json) · [context](practice-es.context.json) | /native/user-guide/es; Practice fields scrolled into view; synthetic answers; language es | WKWebView; 1100×491; element | 2200×982 | 2026-10-31T10:31:03.938000+00:00; `4308293a0938bc54070c4f7dfc93d30cf4fe860ce456815c8891e2d55a54ea8f` |
| [section-activation-en](section-activation-en.png) · [metadata](section-activation-en.metadata.json) · [context](section-activation-en.context.json) | /native/user-guide/en; Detailed chapter with original activation screenshot; all images loaded; language en | WKWebView; 1100×517; element | 2200×1034 | 2026-10-31T10:31:00.133000+00:00; `15cb21f5b366b3166fc05466418f4a21b85ecc4a8c5dc80a4e5b57ee5aa3044a` |
| [section-activation-es](section-activation-es.png) · [metadata](section-activation-es.metadata.json) · [context](section-activation-es.context.json) | /native/user-guide/es; Detailed chapter with original activation screenshot; all images loaded; language es | WKWebView; 1100×491; element | 2200×982 | 2026-10-31T10:31:03.171000+00:00; `39a0cd1cdb333ffdf542890f516e720266ae6bfe5218c1dfd5e959ea37429df6` |
| [section-mobile-en](section-mobile-en.png) · [metadata](section-mobile-en.metadata.json) · [context](section-mobile-en.context.json) | /native/user-guide/en; Detailed chapter with original mobile screenshot; all images loaded; language en | WKWebView; 1100×517; element | 2200×1034 | 2026-10-31T10:31:00.373000+00:00; `cafbc03b7809cb44d6dc1f1af9d97e416f77be80a126cb658b9a586e14b845a9` |
| [section-mobile-es](section-mobile-es.png) · [metadata](section-mobile-es.metadata.json) · [context](section-mobile-es.context.json) | /native/user-guide/es; Detailed chapter with original mobile screenshot; all images loaded; language es | WKWebView; 1100×491; element | 2200×982 | 2026-10-31T10:31:03.422000+00:00; `68fac66b9a87d307f13eeeb6fc43648a64b62a5733399935ec679075ae5923cc` |
| [section-palette-en](section-palette-en.png) · [metadata](section-palette-en.metadata.json) · [context](section-palette-en.context.json) | /native/user-guide/en; Detailed chapter with original palette screenshot; all images loaded; language en | WKWebView; 1100×517; element | 2200×1034 | 2026-10-31T10:30:59.896000+00:00; `c7bfaeb70f2c45fb7849a712dd84703be16242892cec6542facefbefeebe7071` |
| [section-palette-es](section-palette-es.png) · [metadata](section-palette-es.metadata.json) · [context](section-palette-es.context.json) | /native/user-guide/es; Detailed chapter with original palette screenshot; all images loaded; language es | WKWebView; 1100×491; element | 2200×982 | 2026-10-31T10:31:02.938000+00:00; `ad17ed8febf5076b9012c390ebe257c922d8a91a7e7063fb902cdc81c7ae82e2` |

## Reproduce and limitations

Build/test using the repository compilation recorder, then from that unchanged
source checkout:

```sh
LEONARDO_VISUAL_EVIDENCE=/tmp/guide-review swift test --skip-build --filter 'BundledUserGuideTests|ExtensionRecommendationVisualTests'
```

Pass the real source SHA as `EVIDENCE_SHA` when collecting. Generate canonical
sidecars with the shared capture-metadata helper before editing the checkout.
The fixture captures observed viewport, browser signal and capture-start time.
WebKit needs a bounded post-scroll paint interval; immediate snapshots produced
two blank chapter captures that were rejected and recaptured. An attempted
requestAnimationFrame wait could pause on an occluded test window; it was removed
in favor of the bounded settling interval. No blank capture is included here.

The generic Welcome bitmap is excluded: native transparent/glass composition is
not reliable in that harness (existing #187). The authored Home pictures use the
proper appearance/background fixture and were separately inspected. These are
native component/WKWebView checks, not a fresh packaged-process launch, connected
device transfer, hosted install or release acceptance. No user app was terminated.

Local validation: 580 XCTest cases (30 opt-in/platform skips), 28 Swift Testing
cases, 52 Python script cases (7 optional engine skips), 38 agent-plugin cases
and 20 packaging cases passed. Focused guide tests passed after final copy and
capture-harness changes; the opt-in capture run passed 5 tests. CI must still
pass at the precise reviewed head. Local skill validation also passes.
