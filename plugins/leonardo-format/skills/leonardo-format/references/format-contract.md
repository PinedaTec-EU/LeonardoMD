# Leonardo format contract

The canonical contract lives in the repository's `doc/format/` directory and
is versioned with the application. The machine-readable v1 schema is
`doc/format/mdlf-v1.schema.json`. These files are the only source of truth for
the front-matter keys, field/value types, layout vocabulary, rendering
semantics, and migration rules. The plugin must be released with the same
contract revision that its skill describes.

The public extension roles are stable:

| Extension | Meaning | Initial opening mode |
| --- | --- | --- |
| `.md` | Standard Markdown | Standard Markdown behavior |
| `.mdlf` | Leonardo editable document | Edit/read according to the host |
| `.mdlr` | Leonardo form export | Fill |
| `.mdlz` | ZIP transport for one `.mdlf`/`.mdlr` plus `assets/` | Package or explicit extraction |

The `.mdlf` and `.mdlr` files remain UTF-8 text documents. Their front matter
is a JSON object with the following top-level contract in format version 1:

```json
{
  "format": "mdlf",
  "formatVersion": 1,
  "document": { "kind": "form", "revision": 1 },
  "fields": {
    "customerName": {
      "type": "text",
      "required": true,
      "maxLength": 120
    }
  },
  "values": { "customerName": null },
  "layout": {
    "images": [],
    "tables": []
  }
}
```

`document`, `fields`, `values`, and `layout` use the detailed definitions in
the canonical schema. Field identifiers are stable keys; the Markdown body
references them as `{{field:customerName}}`. Form values are outside the body,
so filling a form does not rewrite its prose or field definition. A `.mdlr`
export normally carries `document.kind: "form"`; the extension additionally
provides the fill-mode opening hint. Readers use the same schema for both
suffixes and must accept a valid MDLF document named `.mdlr` even when its
metadata kind is `document`.

Field `pattern` values use the portable v1 intersection of Python `re` and
ICU/`NSRegularExpression`: literals, character classes, ordinary groups,
alternation, anchors and quantifiers are supported. Engine-specific escapes
(`\p`, `\P`, `\X`, `\R`, `\N{}`, `\A`, `\Z`, `\z`) and named,
conditional or atomic groups are rejected by every v1 reader. Patterns are
limited to 512 UTF-8 bytes; backreferences, look-around and quantified groups
are rejected, and values checked by a pattern are limited to 32 KiB. These
definition checks are separate from invalid current answers, which remain
transportable drafts.

An MDLZ package is conventional transport. It must contain exactly one root
document with a lowercase `.mdlf` or `.mdlr` suffix and may contain regular
resources below `assets/`. The package does not carry executable behavior or a
second hidden source of document state. The transport envelope is at most 64
MiB of ZIP bytes, 32 MiB of expanded content in total or for one member, and
2,048 entries. Directory records are validated for safe paths but are
nonsemantic transport noise: packers omit them and readers ignore them. Readers
also apply the versioned definition and layout safety rules; current `values`
are draft data and are not rejected merely because an answer is invalid.

When the canonical contract changes, update `doc/format/`, examples, the
application parser, and this plugin's bundled references together. Do not copy
an old schema into a new plugin release without recording the supported format
version.
