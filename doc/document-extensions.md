# Document extensions

Implementation tracked in [#277](https://github.com/PinedaTec-EU/LeonardoMD/issues/277).

Preferences → Extensions provides a global selection and a portable project
override. Projects inherit the global selection until an override is created;
**Inherit global extensions** restores inheritance. All extensions start off.
Existing Mermaid and mathematics selections are preserved.

| Extension | Document syntax and purpose | Details |
| --- | --- | --- |
| Mermaid | Fenced `mermaid` diagrams | Existing diagram engine |
| Mathematics (KaTeX) | Mathematical expressions between `$…$` or `$$…$$` | A subset of LaTeX mathematics, not complete `.tex` compilation |
| Charts (Vega-Lite) | Fenced `vega-lite` JSON with inline data | [Syntax and limits](vega-lite.md), [example](../Examples/VegaLite.md) |
| Citations (Citation.js) | `[@key]` and fenced `bibtex` or `csl-json` records | [Syntax and limits](citations.md), [example](../Examples/Citations.md) |
| Markdown extras | `[^note]` footnotes and `> [!NOTE]` callouts | [Syntax](markdown-extras.md), [example](../Examples/MarkdownExtras.md) |

## What disabling changes

An enabled extension interprets its syntax in the preview. Disabling preserves
the document source and falls back to ordinary Markdown or fenced code. This
can help inspect unfamiliar documents and keeps existing documents from changing
interpretation when a new extension is added.

Disabled engines are absent from the WebKit resource allowlist. Toggling an
extension rebuilds the execution context, releasing the old engine state. For
Vega-Lite and Citation.js, enabling only permits the engine: the bundled runtime
loads when the document contains a corresponding source block. A plain document
does not load either heavy engine. The lightweight Markdown extras parser loads
only when enabled. Bundled resources still occupy disk space when disabled.

## Offline preview and PDF

Chart data and bibliography records belong in the document. No CDN, external
data source or DOI lookup is needed or enabled. The existing no-network and
no-eval security policy stays in place. Generated chart SVG and bibliography HTML
are sanitized before insertion; errors appear beside the authored document.
PDF export waits for charts and bibliography rendering before capture.

Footnote and citation output and chart graphics are derived from source. Edit
their source through the raw Markdown editor. Existing HTML `details`/`summary`
blocks need no additional plugin; custom tabs are outside this extension set.
