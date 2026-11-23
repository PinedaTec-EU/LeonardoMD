# Current guide capture bundle

These six original, synthetic captures were produced from clean source
`30c589c30413a1f5c6174c235656fbe47a211668` by:

```sh
EVIDENCE_SHA=30c589c30413a1f5c6174c235656fbe47a211668 LEONARDO_VISUAL_EVIDENCE=/tmp/leonardo-291-sidecar-captures swift test --skip-build --filter BundledUserGuideTests
```

The preceding recorded compiler-bearing focused run passed all four tests;
`--skip-build` uses those same committed test and product sources. Each
`.context.json` was written alongside its PNG, with capture-start UTC time,
measured viewport, engine observation, language and synthetic state.

Each `.metadata.json` was generated with the canonical shared
`pr-judge-delivery/scripts/capture_metadata.py` helper, supplying this checkout,
original PNG and its original context. The helper binds image dimensions and
SHA-256 to the context and clean capture-source revision. Its `collected_at`
is deliberately distinct from the original `capture.captured_at`.

WebKit contexts contain JavaScript-measured `innerWidth`/`innerHeight` and
`navigator.userAgent`. The AppleWebKit token is an engine compatibility
identifier; no Safari version or actual OS version is inferred from it.
Native Welcome has no browser or CSS viewport: `native_viewport_points` records
its measured bounds, and the common helper's required `viewport_css` field
contains that explicitly labeled native-point equivalent. Its browser fields
say that a browser engine is not applicable. Raw context retains this distinction
and the directly reported host OS; these are native component snapshots, not
browser-page or fresh packaged-process captures.

The commit adding this bundle changes only documentation/evidence. Product
code, test code, resources and build inputs are unchanged from the capture
source. Later evidence-only heads must preserve and explicitly verify that
mapping; otherwise regenerate the bundle. CI also records original per-image
contexts in its current-head visual artifact, avoiding metadata reconstruction.
