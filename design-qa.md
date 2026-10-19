# Preferences scope design QA

Source visual truth: [owner-selected second Product Design mockup](doc/validation/preferences-scope/design-target.png).

Target surface: native macOS preferences, 580 × 620 points, Graphite Glass, Spanish; General selected. The generated target is approximately double density and includes window chrome; comparison must normalize content bounds and density. This is a scoped native implementation, preserving existing SwiftUI controls/themes rather than reproducing generated macOS chrome.

## Findings

Visual comparison is pending. The generated target includes copy and scope inaccuracies that are intentionally corrected: language affects LeonardoMD windows, not all macOS; frontmatter, external-link confirmation and hidden-file visibility have no project override and belong to the Mac-wide section; project-only Git is hidden for Global.

## Evidence and comparison history

- Implementation screenshot: pending native compositor capture.
- Full-view comparison: not yet performed.
- Focused header/tab/scope comparison: not yet performed.
- Native view bitmap capture is insufficient for the glass tab strip in this repository. The running installed app holds product-wide single-instance ownership. Owner permission to close it normally and run the packaged QA app is pending.
- Full local XCTest run: 392 cases, 15 optional skips, zero failures. Packaging/ledger script checks: 24 cases, 7 optional skips, zero failures. Release compilation and locally signed QA bundle verification pass; `CFBundleExecutable` is `LeonardoMD`, with Sparkle and no XCTest dependency. Successful source compilation delta: 2.
- Build/test evidence is recorded on [#173](https://github.com/PinedaTec-EU/LeonardoMD/issues/173) and [PR #174](https://github.com/PinedaTec-EU/LeonardoMD/pull/174), separately from visual evidence.

## Required fidelity surfaces

- Fonts and typography: pending native capture; existing SF/SwiftUI type styles retained.
- Spacing and layout rhythm: pending rendered comparison; title/scope is inside applicable panes.
- Colors and tokens: existing SessionAppearance, PremiumSelection and PremiumButtonStyle retained; rendered verification pending.
- Image quality and assets: no raster assets required by the implementation; native SF Symbols retained.
- Copy and content: English/Spanish keys added; misleading generated target copy corrected as described above.

## Implementation checklist

1. Complete native packaged visual comparison and exercise all five tabs, both scopes, English/Spanish and standalone mode.
2. Attach exact-head screenshots and provenance, then update this report.
3. Obtain required CI and independent judgment before integration.

final result: blocked
