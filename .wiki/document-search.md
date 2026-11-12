# Find in open documents

The project sidebar search finds filenames and repository content. In-editor
Find is separate: it scans source text held by open `AppSession` instances and
never reads unopened project files.

- `DocumentTabs.search` owns per-window query, scope, literal/regex and current
  match state. `DocumentTabsSearch` refreshes it when tab selection, session
  content or search settings change. `DocumentSearchExecutor` serializes regex
  work away from the main actor and publishes only the latest request.
- Current-document scope follows the active tab. All-open scope follows tab
  order and includes documents in that `DocumentTabs` window.
- `DocumentSearchBar` is opened from the tab bar or Edit menu. Find Next/Previous
  wraps, activates the matching tab and selects its source range.
- `MarkdownEditor` applies temporary `NSLayoutManager` background attributes;
  these highlights never enter the document text or undo history.
- Navigating from Preview/Fill flushes renderer edits before exposing the source
  editor. Regex compilation failure clears matches and reports an inline error.

The bundled Spanish and English Guide v62 packages document the literal/regex
modes, window scope, result navigation and keyboard shortcuts. Native package
acceptance and a captured highlighted result are recorded in
[in-editor search validation](../doc/validation/in-editor-search/README.md).

Canonical feature: [#39](https://github.com/PinedaTec-EU/LeonardoMD/issues/39),
[#434](https://github.com/PinedaTec-EU/LeonardoMD/issues/434).
