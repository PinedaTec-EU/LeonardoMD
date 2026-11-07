# Little Leonardo Classic visual verification

final result: passed

This is a native-app design check, not release, physical-device or full bundled-Help acceptance.

## Sources and comparison

The owner-selected Product Design reference is retained at `doc/validation/mobile-classic/approved-reference.png`. `design-comparison.png` places that source and real full-display landscape/restored portrait captures in the same comparison input. Originals and sidecars remain separate; only the comparison is uniformly scaled. The generated reference is a conceptual three-state board, not a pixel-exact device screenshot. Its illustrative signature is replaced with synthetic test strokes. Native viewports are 402×874 and 874×402 points at 3×; OS chrome/safe areas are preserved, rather than copied from the concept.

## Iteration

The first native comparison found two P2 issues: inherited dark text on oxide primary buttons and compression wrapping the ink-color label. Explicit parchment primary-label colors and intrinsic selector sizing resolve these. The outlined label field and oxide secondary actions now follow the selected reference. Post-fix native captures verify the result. A navigation-bar transition overlapping rotation also left XCTest waiting for animation completion; the rubric layout now changes without a competing SwiftUI animation. The final native rotation test completes successfully.

## Five fidelity surfaces

- Typography: native system type, readable body, burgundy content headings; no substituted raster text.
- Spacing: full-window landscape canvas, compact horizontally scrollable tools, normal portrait page restored. Safe areas account for the device's hardware; there is no modal-sized drawing surface in landscape.
- Colors: MobileClassic reads PaletteCatalog.leonardoClassic. Paper, burgundy, oxide, ink and borders follow the existing tokens; primary labels have light/dark contrast.
- Images: existing real Leonardo brand asset, no invented logo. Canvas is live vector ink in portable 3:1 coordinates, not a mock image. Original captures remain unmodified.
- Copy/content: Spanish actions, explicit request consent and Send, manual expansion, offline About/help/privacy/licenses; no Premium or theme selector.

## Functional evidence

Final signed iOS Simulator acceptance verifies manual expansion/collapse, portrait→landscape→portrait, unchanged stroke count across rotation, additional landscape ink, visible restored ink, undo/clear/preview, durable recovery after relaunch and explicit response confirmed by the actual Mac TLS fixture. About/help/privacy/licenses routes pass. Separate direct-reader acceptance verifies enrollment, refresh, offline retention/retry and revocation.

Residual P3 differences: the concept's decorative paper texture is replaced by the canonical flat native paper surface; the Markdown renderer retains its own Classic parchment effect. Native navigation chrome and safe-area insets follow iOS. These do not change the selected palette or interaction.

## Final accepted-main refresh (2026-11-07)

Final product checkpoint11a6ddd combines accepted math/demo/diagnostics. `final/design-comparison.png` places the same selected reference and fresh native full-display landscape/restored portrait together; inspected actual pixels confirm palette, spacing, visible restored two-stroke ink, readable compact tools and explicit Send only on the portrait page. `final/` also supplies current library/project/Markdown/source/pairing/settings/About/demo and both packaged Help locales. Product/build hashes bind these to the evidence-only reviewed head. Real Help and practices now pass; historical pending statements in checkpoint-history are superseded. Scoped visual result remains passed. Physical transport380 is outside this design verdict.
