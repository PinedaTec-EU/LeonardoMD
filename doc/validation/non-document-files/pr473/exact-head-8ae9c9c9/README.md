# PR #473 packaged macOS evidence

Captured on 2026-11-20 from the task-owned QA copy of LeonardoMD, bundle ID `eu.pinedatec.LeonardoMD.qa.pr473.8ae9c9c9`, version `0.3.1896` (build `1896`), on macOS `27.2.1` (build `26B131`). The bundle was launched with an isolated temporary HOME and synthetic sample files. Its process was PID `47887` (started at 01:51 local time) and exited normally after capture.

The bundle corresponds to PR source `8ae9c9c94662c389e9b3149d54aa76c4f2255be2`; the bundle identifier carries the same short source hash. Images were captured from LeonardoMD-owned windows with macOS `screencapture -l`; no desktop capture is included. English and Spanish guides and practice forms were open in the same QA session. The form screenshots contain fictional data only.

## File visibility

- [Global preference off by default](macos-preferences-default-off.png) and [enabled](macos-preferences-opt-in.png).
- [Project files with the setting off](macos-project-files-off.png) and [on](macos-project-files-on.png). `.mdlf` and `.mdlr` remain visible in both states.
- [Markdown-linked image still renders while its standalone row is hidden](macos-markdown-image-visible.png).

## Bundled Help and forms

- [English Guide v103](macos-help-en-guide-v103.png), [Spanish Guide v103](macos-help-es-guide-v103.png), and the [English chapter 4 practice-form action](macos-help-en-practice-cta.png).
- With extensions enabled for this isolated QA profile: [English Mermaid and math](macos-help-en-mermaid-math.png), [English tagged equation and chart](macos-help-en-tagged-equation-chart.png), [Spanish Mermaid and math](macos-help-es-mermaid-math.png), [Spanish tagged equation and chart](macos-help-es-tagged-equation-chart.png), [Spanish guide table/image section](macos-help-es-table-image.png), and [Spanish practice field/validation table](macos-help-es-practice-table.png).
- With Math disabled: [English Help preserves literal TeX source and code examples](macos-help-en-math-disabled.png).
- [English practice form reopened from its saved local MDLR](macos-practice-en-reopened.png) retains the synthetic answer and shows “Guardado · archivo local”. [Spanish practice form](macos-practice-es-saved.png) shows its saved synthetic answers and status.

Mermaid, Math, and Charts were returned to off in the isolated profile before the QA process exited. Their temporary preference changes did not touch the user's normal application settings.

`captures.metadata.json` records per-image dimensions and SHA-256 hashes.
