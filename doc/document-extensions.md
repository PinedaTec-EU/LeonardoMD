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

## Recommendations and warning preferences

When the active document preview contains syntax for a disabled built-in extension,
Leonardo offers one grouped dialog. Literal fenced and inline code examples are
excluded. No disabled engine is loaded for detection. The dialog states whether
activation changes global preferences (standalone document) or creates/updates the
current project's override. Activation requires consent and preserves other flags.

Each extension has its own **Do not ask again for this extension** checkbox, stored
on this Mac. **Not now** defers the offered extensions for this document opening.
Dismissal also avoids repeatedly prompting while editing. Recommendations wait for
other document dialogs and inactive tabs. Changing the document, source or project
invalidates pending consent.

**Preferences → Extensions → Reset extension warnings** clears only these extension
suppressions and allows recommendations again, including for the current document
after leaving preferences. It does not reset enabled extensions or other app warnings.
The bundled guide demonstrates Mermaid, Math and Charts with local assets and data.
Tracking: [#310](https://github.com/PinedaTec-EU/LeonardoMD/issues/310).
