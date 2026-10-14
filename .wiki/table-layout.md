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
