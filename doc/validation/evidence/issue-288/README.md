# Active file sidebar

Native SwiftUI/AppKit component captures from `SidebarFollowVisualTests` via the XCTest runner, using a synthetic project with 60 preceding notes and a nested active MDLF file. These are component evidence, not packaged startup validation.

Viewport: 340 × 460 points; PNGs: 680 × 920 pixels. macOS native dark appearance; Spanish interface. No browser is involved.

- `sidebar-follow-disabled.png`: disabled preference leaves the list at its initial scroll position.
- `sidebar-follow-enabled.png`: enabling reveals the nested active file and selected text/background.
- `sidebar-manual-scroll-preserved.png`: background tree refresh respects manual scrolling.
- `sidebar-tab-reactivated.png`: tab activation reveals the active file again.

Reproduce with `LEONARDO_VISUAL_EVIDENCE=/tmp/sidebar-follow swift test --filter SidebarFollowVisualTests` using the repository compilation recorder for compiler-bearing commands. Use `--skip-build` for an already compiled matching checkout. The test asserts actual native scroll offsets and retains one window through preference and tab transitions.
