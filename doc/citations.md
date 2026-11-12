# Citations and bibliographies

LeonardoMD can render local bibliographies in Markdown previews and PDF exports
when the Citation.js extension is enabled. Rendering is offline: the extension
does not resolve DOI, ISBN, Crossref, Wikidata or arbitrary URLs. Markdown
export keeps the original source blocks unchanged.

## Syntax

Put a BibTeX source in a fenced `bibtex` block and cite its keys in prose with
`[@key]`. Multiple keys may be separated with a comma or semicolon. Citation
references inside code spans, code fences and links remain literal text.

````markdown
The result is reproducible [@smith2024].

```bibtex
@article{smith2024,
  author = {Smith, Jane},
  title = {An Offline Example},
  year = {2024},
  journal = {Journal of Examples}
}
```
````

CSL-JSON is also accepted in a fenced `csl-json` block. The first release uses
the APA style. Inputs use explicit local parsers; URL/identifier autodetection is disabled. A bibliography is inserted after the source block; the source
block remains in the DOM as hidden provenance and remains available in the raw
editor.

The extension is disabled by default in the rendering API. When enabled, the
Citation.js engine is loaded only after a source block is present. Invalid
sources, duplicate keys and unknown citation keys produce a visible diagnostic
while preserving the source block. Total source input is bounded to 512 KiB, 2,000 records
and 1,000 in-text references.

The renderer exposes the feature-owned API as
`window.LeonardoCitations.prepare(root, payload)` and
`window.LeonardoCitations.render(root, payload, { loadEngine })`. The loader is
owned by the application so document text never chooses a script URL.

The vendored engine is built from `@citation-js/core`,
`@citation-js/plugin-bibtex` and `@citation-js/plugin-csl` 0.9.0 with the
reproducible manifest and lock file in `doc/validation/citation-build-*`.
`plugin-csl` includes `citeproc` 2.4.63. Its npm metadata declares
`CPAL-1.0 OR AGPL-1.0`; the package `LICENSE` offers CPAL version 1 or later
or AGPL version 3 or later. This integration selects the CPAL-1.0 route and
does not select AGPL. The complete CPAL text, the unmodified citeproc source
and its package notice are shipped under
`Sources/LeonardoRender/Resources/licenses/`; the release bundle must keep
those resources alongside the executable to satisfy the source/notice path
described by CPAL Section 3. The citeproc package has no populated CPAL
Exhibit B attribution values, so no invented UI attribution is added; this is
based on the package notice and is not a substitute for a release compliance
review.
