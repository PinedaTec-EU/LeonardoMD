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
transform it and reuses `LeonardoTables.documentTokens` from the existing parser
for footnotes/callouts (including consumed reference definitions); no disabled engine loads. Ready messages carry the exact source and
allowlisted IDs, checked against the current host/frame/buffer. The app's
`BuiltInExtension` maps these IDs to existing preference flags.
`ExtensionRecommendations` owns grouped consent, per-opening offered IDs and stale
context checks; `ExtensionWarningPreferences` owns global per-extension suppression
and reset revision. The presenter waits for active-tab/dialog eligibility. Reset in
Extensions re-arms recommendations without changing flags. Guide v4 is a separate
personal copy and packages the approved About banner plus real engine examples.

Display math ([#272](https://github.com/PinedaTec-EU/LeonardoMD/issues/272)) is protected by custom block/inline tokens in the existing Marked parser before Markdown transforms TeX. Tokens stay opaque to preview editing; disabled Math preserves literal notation. The current bilingual guides contain underbrace and tagged multiline regressions; [the canonical guide inventory](../doc/guide/feature-coverage.md) records their current revision. Use the [native visual QA scope](../AGENTS.md#scope-native-visual-qa-to-affected-screens) for live Help checks. Native component checks supplement that evidence.

Extensible math ([#274](https://github.com/PinedaTec-EU/LeonardoMD/issues/274)) permits SVG geometry only in sanitized KaTeX output, with trust disabled and active/external SVG content rejected. Raw document SVG remains outside the HTML profile. Outline navigation ([#364](https://github.com/PinedaTec-EU/LeonardoMD/issues/364)) uses parser-bound source lines with per-render identities; it does not derive preview position from source length. The host waits for current rendering and rejects stale/replaced navigation requests. Only editor-originated scrolling drives preview fractions; programmatic outline jumps retain their rendered destination.

Little Leonardo parity ([#464](https://github.com/PinedaTec-EU/LeonardoMD/issues/464)) reuses the shared `BuiltInExtension` catalog for Mermaid, Math, Charts, Citations and Markdown extras. Device-local `MarkdownFeatures` settings feed the on-demand remote reader, offline corpus reader and bundled Demo. `extension-detection.js` still reports allowlisted IDs; mobile offers only detected, disabled built-ins, checks the exact current source before responding, and applies only explicitly selected switches. Warning suppression/reset stays on-device. The Demo v2 practice copy includes all five extension examples and uses the same consent flow; existing v1 copies and answers remain in place. Remote documents remain read-only and remote images remain blocked. The mobile implementation is `fd7b8b116f36e2bec360ffccecf2d0992387a3cd`, now reconciled with current `origin/main` `38c0a7841cbded7a0620ffe67fe364c23339a6ed`, which includes the Finder/icon chapter-1 guidance from #415. The preserved iOS captures and macOS Help smoke were observed against historical Guide v147; the records remain linked as historical evidence in [PR #465 iOS evidence](../doc/validation/pr-465/current-ios-qa/README.md) and [PR #465 macOS evidence](../doc/validation/pr-465/current-macos-qa/README.md). The current bundled bilingual packages are Guide v160, which combines the merged Finder and Little Leonardo help with the project-tree transfer guidance: EN `03aeef497d89f20826bf689c106064f26b7968371c39b9fe340ad6bcd4702241`, ES `2e165b15744ae41e7080bdf9808fa9554cb3eedff1d5d571d5a34f742d861729`. The #415 Finder evidence is retained in `doc/validation/document-icons-415/`; the older recommendation captures remain historical and retain their original sidecars (`doc/validation/little-leonardo/mobile-extension-recommendation-full/` and `doc/guide/en/assets/mobile-extension-recommendation.context.json`). No new GUI run is claimed here; owner-directed beta/stable validation remains the place for fresh distribution/runtime acceptance, including physical-device/TestFlight and remote/on-demand flows.

Little Leonardo's synchronization interval (#469) is localized beside the
extension settings in English and Spanish. The picker persists
`directSyncIntervalMinutes` on-device; its positive values repeat synchronization
while the app is active. Returning to the active state triggers one sync before
the repeated interval begins. Guide v160 documents both labels and this lifecycle.
