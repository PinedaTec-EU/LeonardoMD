# Optional document extensions

Tracking: [#277](https://github.com/PinedaTec-EU/LeonardoMD/issues/277).

`MarkdownFeatures` owns five opt-in flags, merged field by field through one
`ConfigurationStore.mergeMarkdownFeatures` path for global/project settings.
`SessionRendering` passes the resolved selection to `MarkdownPreviewConfiguration`.
Changing any engine flag rebuilds the WebKit context and its resource allowlist.

- `extension-engines.js` loads only application-owned chart/citation script names
  through the bundled scheme. Engines load only when an enabled document contains
  source fences; enabling empty documents loads only the small adapters.
- `vega-charts.js` owns `vega-lite` JSON → static sanitized SVG with an AST
  interpreter, inline data and complexity limits. Do not add unsafe-eval or remote
  loaders. CSS paint-resource functions are rejected before compilation; final
  SVG accepts only generated local fragment references and a safe root background
  color. Regression: [#280](https://github.com/PinedaTec-EU/LeonardoMD/issues/280).
  `LeonardoCharts.render` returns its current readiness promise.
- `leonardo-citations.js` owns local BibTeX/CSL-JSON and `[@key]` → sanitized APA.
  It must guard asynchronous replacement and remove edit mappings from generated
  citation text. It deliberately has no DOI resolver.
- `markdown-extras.js` extends the existing `LeonardoTables` Marked instance via
  install/beginDocument/finish, preserving table/edit annotations. No second parser.
  Footnotes and GitHub callouts share one toggle; details is existing HTML.
- `renderer-runtime.js` waits for feature work before publishing ready and before
  PDF preparation. Source fences for enabled generated output are not editable
  through preview; use the raw editor.

Human syntax/examples: [document extensions](../doc/document-extensions.md).
Vendoring: resource `THIRD_PARTY_SOURCES.json`, license files and pinned build
manifests/locks in `doc/validation/`. Do not overwrite the existing Mermaid/KaTeX
choices or load chart/citation engines eagerly when adding new flags.

Extension preference cards use the switch as their state indicator, without a
redundant Enabled/Disabled caption. The shared card covers global and project
settings; `PremiumSwitchStyle` retains its accessible state value. Tracking:
[#285](https://github.com/PinedaTec-EU/LeonardoMD/issues/285).

Recommendations ([#310](https://github.com/PinedaTec-EU/LeonardoMD/issues/310)):
`extension-detection.js` inspects the sanitized ordinary Markdown DOM before engines
transform it; no disabled engine loads. Ready messages carry the exact source and
allowlisted IDs, checked against the current host/frame/buffer. The app's
`BuiltInExtension` maps these IDs to existing preference flags.
`ExtensionRecommendations` owns grouped consent, per-opening offered IDs and stale
context checks; `ExtensionWarningPreferences` owns global per-extension suppression
and reset revision. The presenter waits for active-tab/dialog eligibility. Reset in
Extensions re-arms recommendations without changing flags. Guide v3 is a separate
personal copy and packages the approved About banner plus real engine examples.
