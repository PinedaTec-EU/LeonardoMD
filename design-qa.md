# Preferences scope design QA

## Result and findings

No actionable P0/P1/P2 issue remains for the scoped redesign. The header and tab strip stay stationary across General, Extensions, Little Leonardo, Linked Macs and Updates. Global / This project appears only inside General and Extensions. The selected scope survives navigation away and back. Standalone General has no project selector. Native controls, existing themes and persistence are preserved.

## Source and implementation evidence

- Source visual truth: [owner-selected second Product Design mockup](doc/validation/preferences-scope/design-target.png), 1213 × 1297 pixels.
- Implementation: [General / Global, Spanish](doc/validation/preferences-scope/general-global-es.png) and [General / This project, Spanish](doc/validation/preferences-scope/general-project-es.png), 1160 × 1240 pixels, a 580 × 620 point native sheet at 2× density.
- Full-view comparison: [normalized target and actual Global state together](doc/validation/preferences-scope/design-comparison.png). Generated outer canvas/window margins cropped at `(44,47)-(1170,1244)`, then normalized to 580 × 620; implementation downsampled from 2× to that same point size. Runtime sample palette/paper values differ from mock values; no user global palette was changed to mimic sample data.
- Focused comparison: [pane heading and scope](doc/validation/preferences-scope/scope-comparison.png).
- Cross-tab comparison: [five Spanish header/tab strips](doc/validation/preferences-scope/navigation-comparison.png). The title/Done region `(35,40)-(1125,130)` is pixel-identical across all five captures; [metrics](doc/validation/preferences-scope/geometry-comparison.json). The tab strip occupies the same y=160–204 pixel band throughout; only selection styling changes.
- [Scrolled Mac-wide settings](doc/validation/preferences-scope/general-mac-settings-es.png) confirms lower controls are reachable while the header, tabs and scope stay fixed.
- English captures: General, Extensions, Updates, Little Leonardo, Linked Macs; light/standalone captures also included in the evidence folder.

## Intentional product constraints relative to the generated target

The generated mock includes scope and copy inaccuracies. Language affects LeonardoMD windows, not all macOS. Frontmatter, external-link confirmation and hidden-file visibility have no project override, so they sit in the Mac-wide section. Git is project-only and absent in Global. Existing Markdown association status/startup consent controls remain, instead of the mock's simplified button. These additional controls scroll inside the original 580 × 620 point sheet; persistent navigation never clips. Existing native tab controls and PremiumSelection are retained rather than recreating generated OS chrome or introducing a parallel design system. These corrections were disclosed before implementation.

## Required fidelity surfaces

- Fonts/typography: existing system SwiftUI fonts, title2/title3/headline/caption hierarchy; Spanish and English are readable with no tab or scope truncation. Native wrapping is retained for long association copy.
- Spacing/layout rhythm: 24-point outer padding, 16-point interior scope header, left title/right scope composition; scoped form first and Mac-wide settings below. Native grouped rows and scrolling accommodate the real setting inventory. No nested decorative cards were added.
- Colors/tokens: existing SessionAppearance, PremiumSelection, PremiumButtonStyle and PremiumSwitchStyle; Graphite Glass cyan selection and light Leonardo Classic verified. The mock's cooler neutral background is not substituted for the application's existing material/theme behavior.
- Image/assets: no new raster asset is needed in the UI; native SF Symbols and existing controls are retained. The generated target is comparison material only.
- Copy/content: localized Appearance, On this Mac and Project: %@; correct language applicability and actual scope-dependent values verified.

## Interaction and startup evidence

Owner authorized normal exit of the installed app. It exited without a save prompt. A new packaged QA process (PID 15400, distinct from installed PID 49477) opened its first window and the synthetic notes.md document. Bundle verification confirms real executable LeonardoMD, Sparkle present, no XCTest dependency, and valid local signature. This is fresh packaged startup plus native settings QA, not signed release/updater distribution acceptance.

The synthetic project was `/private/tmp/LeonardoMD-Preferences-QA`. Changing its palette persisted `graphite-glass` in `.leonardomd/project.json`. Disabling Mermaid created only its project override (`mermaidEnabled: false`, `mathEnabled: true`); restoring Inherit global extensions removed that override. Switching General to Global showed the unchanged global Leonardo Classic/Parchment values. Service and pairing controls were not enabled. Language was switched both directions in the QA bundle's separate defaults domain.

## Comparison history and capture workflow

Initial blocked checkpoint: native bitmap hosting cannot faithfully capture the glass tab strip, and the installed app held product-wide single-instance ownership. Owner authorization enabled a real packaged run. CUA initially captured Stage Manager thumbnails; use the app's **Window → Bring all to front** action before capturing. AX Raise or selecting the window menu entry alone does not activate the app. After activation, CUA returned full 1160 × 1240 pixel sheet captures. Full and focused comparisons were then inspected together; no implementation change was required after visual review.

## Validation and remaining limits

Full local XCTest: 392 cases, 15 optional skips, zero failures. Script checks: 24 cases, 7 optional skips, zero failures. Release packaging passes; recorded successful compilation delta is 2. The product source has not changed since those checks or the QA build. Exact-head CI and independent review are PR delivery gates, separate from this visual result. No merge or distribution publication is claimed.

## Implementation checklist

- Native selected-target comparison and five-tab stability: verified.
- Project/Global interactions, inheritance and standalone mode: verified.
- English/Spanish and existing light/dark themes: verified.
- Exact-head CI and independent judgment before integration: pending final evidence commit.

final result: passed
