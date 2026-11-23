# Large Home background beneath scrolling content

Tracking: [#158](https://github.com/PinedaTec-EU/LeonardoMD/issues/158). Supersedes the reserved header captured for beta 0.1.399 / PR #157 in `../home-tabs/`.

Native NSHostingView captures on macOS, 2026-10-17, synthetic preferences and local paths. Screen: document-free Home. Browser/URL: not applicable. `source-hashes.json` identifies exact source inputs independently of the evidence commit. These are native component captures, not a packaged-process launch.

Leonardo is a fixed decoration behind the complete ScrollView. There is no separate top region. The size target doubles beta 0.1.399 (1280-point cap and 36% of canvas height), bounded by canvas width minus 24 points to preserve the whole image on narrow canvases. Its 3:1 aspect ratio, original color/opacity, wing placement, favorites and recent tabs remain intact.

- `welcome-before-scroll-es.png` and `welcome-scrolled-es.png`: identical 1100×700-point light canvases and synthetic favorites. The second moves the real native NSClipView by 180 points, asserting the resulting offset. The material favorites panel passes over Leonardo while the watermark stays fixed in the background.
- `welcome-600x400-es.png`, `welcome-1260x687-es.png`: short and ordinary-height dark canvases, no reserved header.
- `welcome-narrow-dark-es.png`: 600×600-point dark canvas; width fitting preserves the full lettering.

Validation: full Swift suite passed without failures; final FavoritesTests passed all 10 cases with capture mode enabled after the fixture was made stable. The fixture persists its temporary preferences before capture so session polling cannot replace the long list during scroll validation. The first long-list capture attempt caught that fixture race; it failed and was corrected before recording final captures. Three successful compilation commands are recorded in PR #159's ledger; the failed attempt adds no delta.

Reproduce final captures with `LEONARDO_FAVORITES_CAPTURE=/tmp/leonardo-home-159 python3 scripts/compile-and-record.py --pr-number 159 -- swift test --filter FavoritesTests`.

No installed application was replaced or terminated. Fresh packaged-process startup remains outside this component validation; use the repository QA launch flow when single-instance ownership is available. These changes are not present in published beta 0.1.399 until integrated and distributed as a new build.
