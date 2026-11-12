# Markdown extras

LeonardoMD's optional Markdown extras extension adds footnotes and GitHub-style
callouts. Enable **Markdown extras** in Preferences (globally or for the current
project). The extension is local and offline; it does not fetch a service or
execute authored HTML or JavaScript.

## Footnotes

Put a reference in the document body and define the note elsewhere, usually at
the end of the document:

```markdown
The exported report uses the local data set.[^dataset]

[^dataset]: The data set was supplied with the project archive.
```

Definitions support inline Markdown such as emphasis, links, and code spans.
Indented continuation lines are included in the same note. Leonardo numbers
notes in order of first reference and adds a return link for every repeated
reference. A reference without a definition remains visible as literal text.

The generated footnote list is preview output. Its source definition remains in
the Markdown editor, so disabling the extension or editing the raw document
never removes authored bytes.

## Callouts

Callouts use the GitHub-compatible blockquote marker:

```markdown
> [!WARNING]
> Changing this value requires a migration.
```

The supported kinds are `NOTE`, `TIP`, `IMPORTANT`, `WARNING`, and `CAUTION`.
The marker becomes an accessible note panel with a visible title. With the
extension disabled, the same source remains a regular blockquote.

## Disclosure blocks

No extension is needed for a collapsible section. Markdown already permits the
portable HTML form below, and Leonardo keeps the native `details`/`summary`
semantics:

```markdown
<details>
<summary>Implementation details</summary>

The section starts collapsed.

</details>
```

Tabs are intentionally not part of this extension. There is no interoperable
Markdown syntax for tabs, and a private syntax would make editing, accessibility,
deep links, and export less predictable.
