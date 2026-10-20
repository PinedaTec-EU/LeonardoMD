# Table layout

Tracking: [#130](https://github.com/PinedaTec-EU/LeonardoMD/issues/130).

`LeonardoRender/Resources/table-layout.js` associates a standalone
`<!-- leonardo:table widths="10ch 15ch auto" -->` HTML token with only the next
GFM table in that block scope. Marked tokens avoid interpreting fenced examples.
Strict numeric `ch` validation precedes generated colgroup/style markup;
DOMPurify still sanitizes the complete rendered document. Width-count mismatches
and malformed directives fall back to normal tables.

The shared runtime wraps sanitized tables in keyboard-scrollable viewports.
Normal tables preserve words; fixed-layout opt-in tables wrap headers and reserve
explicit content widths plus padding. `auto` columns share spare space with a
12ch minimum. Full syntax is documented in README.

Interactive sizing ([#208](https://github.com/PinedaTec-EU/LeonardoMD/issues/208))
uses `table-resizing.js`/CSS after sanitization and MDLF layout application.
Controls live outside cells in the scroll viewport; transient geometry never
changes source until pointer-up. `LeonardoTableResize` owns validated point
geometry. `SessionTableResizing` guards identity/protection/mode and reuses
`migrateMarkdownToLeonardo(tableResize:)` for exclusive sibling creation with
geometry already serialized. The host tracks the async transaction; flush
cancels unfinished gestures and joins commits. Resize migration skips recursive
flush to avoid awaiting its own transaction. Save/export/navigation settle the
bridge; retired document callbacks cannot target byte-identical siblings.

V1 table metadata now includes optional `height`, `rowHeights` and `source`.
All schema copies and the plugin semantics match; earlier strict readers reject
the new properties. `source` mismatch at the recorded occurrence disables stale
geometry. See the canonical format README for interaction and identity limits.
`TableResizingTests` exercises native WebKit gestures, migration, save/reopen,
PDF, cancellation and rejection paths. This is component/runtime evidence, not
fresh packaged startup acceptance.

The editing bridge normalizes both source and original body before calculating
the body boundary for resize lookup; mixing raw CRLF length with normalized LF
length truncates leading tables. The native resize matrix covers CRLF both
with and without front matter. Outer handles reserve separate viewport padding
so even header-only/narrow tables keep hit-testable width/height controls.
