# Markdown table widths

An optional standalone comment immediately before a GFM table sets its column
widths without changing standard Markdown table syntax:

```markdown
<!-- leonardo:table widths="10ch 15ch auto" -->

| Fecha | Prueba | Resultado esencial |
| :--- | :--- | :--- |
| 14/10/2026 | Analítica | Sin alteraciones |
```

Use one value per column: an integer from `1ch` to `200ch`, or `auto`. `ch` is
approximately the width of the font's zero character, not a count of arbitrary
letters; the specified width is for content, with cell padding added. `auto`
columns share remaining space, with a readable minimum of 12ch each. Without
`auto`, the table keeps the specified widths rather than stretching to fill the
preview. Narrow viewports scroll horizontally. Headers wrap onto multiple lines;
unbroken tokens wrap only when necessary inside explicitly sized columns.

Blank lines are allowed between the comment and table, but intervening content
ends its scope. It applies only once, including inside a list or block quote.
Invalid directives or a column-count mismatch are ignored; fenced code examples
are never interpreted. Other Markdown viewers ignore the comment and render the
ordinary table. Tables without a directive use natural widths and preserve whole
words, scrolling horizontally when necessary.
