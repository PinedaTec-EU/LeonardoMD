# Welcome watermark

Tracking: [#75](https://github.com/PinedaTec-EU/LeonardoMD/issues/75), [PR #76](https://github.com/PinedaTec-EU/LeonardoMD/pull/76).

The welcome background uses three transparent notebook sketches, all tinted ochre (#A87832): Leonardo at lower left (30% opacity), a Vitruvian study close to the right edge (24%), and flying-machine wings at upper left (22%). The native view appears only with no document and at least 740 points of available height. Assets scale with width, decoration clips to the document area, and neither participates in accessibility or hit testing. A shared image-loading helper omits unavailable decorative assets instead of crashing.

Built-in ImageGen generated the asset from `AboutBanner.png` as a style reference. Prompt: exact word “Leonardo”, softer fine Renaissance pencil calligraphy, sparse circle/construction geometry on either side, monochrome graphite, transparent margins; no paper, border, books, portrait, or other words. The generated original remains in the Codex image library; the project resource is the committed copy.

Native SwiftUI `WorkspaceView` captures in English and Spanish use the existing `LocalizationVisualTests` empty-session harness, at 1260 × 850 points / 2520 × 1700 pixels, on 2026-10-08. They use synthetic empty sessions and do not launch or replace the owner's running app. Captures under `welcome-watermark/` demonstrate the actual native view, not a composited mockup. Runtime code in these captures matches the source committed with this document.

Command: set `LEONARDO_LOCALIZATION_EVIDENCE` to an output directory, then run `scripts/compile-and-record.py --pr-number 76 -- swift test --filter LocalizationVisualTests`.

Visual review confirms readable text/actions and separate understated decoration in the captured light parchment palette. Dark palette and short-window live checks remain pending before acceptance, along with CI and independent judgment.

Owner refinement: add an ochre Vitruvian figure behind the welcome at 8% opacity, offset left of the controls. `WelcomeVitruvian.png` uses built-in ImageGen, transparent fine pencil line art in #A87832, recognizable circle/square and superimposed limbs. The classical anatomical request was rejected by the generator; the generated educational variant wears fitted shorts and omits intimate details. The original generation is retained in the Codex image library. Both decorations share the short-window hiding, input and accessibility exclusions.

Latest owner refinement: stronger visibility, all motifs in ochre, left-aligned Leonardo with margin, right-edge Vitruvius, and an additional wing-invention sketch. Built-in ImageGen prompt for `WelcomeWings.png`: transparent Renaissance notebook sketch of an ornithopter, paired bat-like mechanical wings, ribs/cables/frame, fine irregular exploratory pencil strokes and construction ticks, monochrome ochre; no paper, backdrop, fills, border or readable text. Native captures were refreshed after final source edits; full Swift tests pass.
