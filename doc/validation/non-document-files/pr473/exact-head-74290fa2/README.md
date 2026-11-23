# PR #473 macOS packaged QA evidence

This record documents packaged macOS validation for the off-by-default
non-document-file preference and the bilingual bundled Help.

## Source and app identity

- The QA bundle was created at `2026-11-19T09:47:23+01:00` from product source
  `74290fa2e0006d4eb4bd38fd24bddf6b97a94e0b`. The PR branch was at
  `81a97478cc8abd2517841d07e46c176e71187b76` when captured. The only difference
  between those revisions is `deploy/version/entries/473.yaml`, which records
  build delta 39; no product source changed after the QA executable was built.
- LeonardoMD QA version/build: `0.3.1889` / `1889`, macOS `27.0.1` build
  `26A434`, bundle `eu.pinedatec.LeonardoMD.qa.02a2dadba04745dfb261fc9c0ebaed61`.
- The bundle names the real `LeonardoMD` executable. Its SHA-256 is
  `7fe09c6e9125327504ca90720a0c4a03c89913edb5240d9a187a42798470edd5`; its
  dependencies were inspected and it does not link `XCTest.framework`.
- Fresh QA process PID `44300` started at `2026-11-19T10:06:38+01:00`. The first
  window opened successfully. The process was quit through the app menu after
  evidence collection and verified absent.
- Captures are native app-window screenshots at 2520 × 1700 pixels (2× scale).
  The project and document content is synthetic.

## Preference and project-list behavior

| Capture | Result |
| --- | --- |
| [Global preference off](macos-preferences-off.png) · [metadata](macos-preferences-off.metadata.json) | The saved setting is off by default. |
| [Global preference on](macos-preferences-on.png) · [metadata](macos-preferences-on.metadata.json) | The user can opt in. |
| [Image row hidden; Markdown image still renders](macos-image-row-hidden-image-visible.png) · [metadata](macos-image-row-hidden-image-visible.metadata.json) | With the setting off, the project lists `README.md` only and continues rendering its local image. |
| [Image row visible](macos-image-row-visible.png) · [metadata](macos-image-row-visible.metadata.json) | With the setting on, the project lists both `README.md` and the image; the Markdown image remains rendered. |

## Bilingual Help and practice

Guide v101 Spanish and English were opened through the real Help workflow in
the same packaged QA instance. With Math enabled, Mermaid, inline and display
math, the tagged box-counting equation `(1)`, charts, local images and tables
were inspected. No KaTeX errors or literal display-math delimiters appeared.
With Math disabled, the formulas and Markdown-sensitive TeX remained literal,
and code examples stayed literal; Math was restored to enabled afterward.

| Capture | Result |
| --- | --- |
| [Spanish Help and Mermaid](macos-help-es.png) · [metadata](macos-help-es.metadata.json) | Spanish guide v101 is open in Preview and its Mermaid example renders. |
| [Spanish tagged equation](macos-help-es-tagged-equation.png) · [metadata](macos-help-es-tagged-equation.metadata.json) | Display equations render, including the visible tag `(1)`. |
| [English tagged equation](macos-help-en-tagged-equation.png) · [metadata](macos-help-en-tagged-equation.metadata.json) | The same equation and tag render in English Help. |

The separate Spanish and English practice forms were each opened, filled with
synthetic QA data, saved, closed and reopened. The original user practice files
were restored byte-for-byte afterward:

- English original SHA-256:
  `12c375b7b6889d1a86a05efa76d51b67119acd359760105ae504ccc9ef48b662`
- Spanish original SHA-256:
  `180e4ca34a225d36003a1311b2eddb4fbc1b48acdc1e43b528617037c41ff10f`

Final QA preferences were restored to English interface language, Math on,
Show non-document files off, and Allow multiple instances off. No user practice
answers are included in these captures or this record.
