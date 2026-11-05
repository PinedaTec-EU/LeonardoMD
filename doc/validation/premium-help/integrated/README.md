# Combined Guide v11 validation

Tracking: [#334](https://github.com/PinedaTec-EU/LeonardoMD/issues/334).

These are current combined-guide component captures after integrating main's
sync helper PR #320, preserving its chapters and original helper UI screenshots.
Build/capture source: `8023b38` (full SHA in observed contexts). The evidence
commit adds only records, allocation and documentation; no native fixture input
changes. Earlier captures in the parent folder are historical, not current
acceptance evidence.

The complete Swift suite passed after integration. BundledUserGuideTests passed
all five cases in English and Spanish: all fifteen images loaded within the
unchanged standard policy, old personal copies were preserved, and standalone
AgentImport v2 opened/deduplicated correctly. Main help advances to Guide v11
because main already allocated v10 to the sync helper help. The 1200×400 generated
artwork is preserved; only the decorative cover uses a 768×512 packaging
derivative. The original About artwork and current main's UI screenshots remain
unchanged. A conservative whole-guide 128 MiB assertion also passes before
native testing.

Captured Mermaid SVG remains a live teaching example; its source is unchanged.
All other explanatory illustrations are localized PNGs with separate generated
art provenance. Captures use production WorkspaceView/WKWebView and synthetic
content; contexts and shared metadata record observed viewport, engine, time,
image dimensions/hashes and source. No retouching, installed-app replacement or
fresh packaged-process startup claim is made.
