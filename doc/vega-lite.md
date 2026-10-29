# Vega-Lite charts

LeonardoMD can render a Vega-Lite specification in a fenced `vega-lite` code
block. The chart engine is bundled with the application and is loaded only
when the extension is enabled and the document contains a chart. Documents do
not need an Internet connection to render charts.

````markdown
```vega-lite
{
  "$schema": "https://vega.github.io/schema/vega-lite/v6.json",
  "width": 480,
  "height": 260,
  "data": {
    "values": [
      {"category": "A", "value": 28},
      {"category": "B", "value": 55},
      {"category": "C", "value": 43}
    ]
  },
  "mark": "bar",
  "encoding": {
    "x": {"field": "category", "type": "nominal"},
    "y": {"field": "value", "type": "quantitative"}
  }
}
```
````

The first release accepts inline `data.values` and renders a static SVG. It
does not fetch CSV, JSON, images or other URLs, and it does not run interactive
selections, event handlers or generated links. A fenced block remains visible
as source when the extension is disabled. Invalid or out-of-policy
specifications stay in the document and show a bounded error in the preview.

Specifications are bounded to 256 KiB, 10,000 inline rows, 20,000 JSON nodes,
four composition levels, sixteen views per composition and 32 total leaf views,
and dimensions no larger than 4,096 pixels (256 pixels for a discrete `step`).
`repeat` and `facet` are rejected in this first release to avoid unbounded
multiplicative expansion. Rendered SVG is bounded to 4 MiB. These limits keep
preview and PDF export responsive when a document contains untrusted or
accidentally oversized data.

The rendering timeout covers the asynchronous SVG execution phase; it cannot
interrupt JavaScript compilation that is already running. Input size, depth
and composition bounds are therefore the memory and work guardrail.

The renderer uses Vega-Lite's compiler and Vega's SVG view with the
`vega-interpreter` expression evaluator. Parsing includes expression ASTs and
the interpreter is passed to every view, so the renderer does not need to
relax the WebKit content security policy with `unsafe-eval`. The preview CSP
also keeps `connect-src 'none'`; external resources are rejected before the
Vega runtime runs.

Charts are disabled by default and can be enabled globally or for an
individual project in Preferences → Extensions. Enabling the extension causes
the chart engine to load lazily. Disabling it leaves the fenced JSON readable
and removes the engine from the active WebKit context.

The vendored runtime is based on Vega 6.4.0, Vega-Lite 6.5.0 and
vega-interpreter 2.3.2. Exact package integrity and the generated bundle
fingerprint are recorded in `doc/validation/vega-build-package.json`,
`doc/validation/vega-build-lock.json` and the resource provenance manifest.
