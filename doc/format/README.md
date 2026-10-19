# Leonardo document format (MDLF v1)

MDLF (`.mdlf`) is Markdown with a typed JSON front matter block. The body
remains ordinary Markdown and is kept outside the metadata so an agent can
read, edit and diff it without a Leonardo application. The format deliberately
contains no executable code, template language or binary payload.

## Extensions and opening mode

| Extension | Meaning | Initial Leonardo mode |
| --- | --- | --- |
| `.md` / `.markdown` | Standard Markdown | The normal Markdown engine |
| `.mdlf` | Leonardo document or form definition | Edit/reading preference |
| `.mdlr` | Exported form response document | Fill fields |
| `.mdlz` | ZIP transport of one `.mdlf` or `.mdlr` and resources | Mode comes from the contained document |

The extension is an opening hint, not a security boundary. Renaming an MDLR
to MDLF permits editing its definition. An MD document is not run through the
MDLF renderer merely because it contains braces or ordinary front matter. A
warning is appropriate only when an explicit `"format": "mdlf"` marker is
present at the front of the file.

MDLR uses the same schema as MDLF. Exporting a form copies the field
definitions, body and layout and writes its current values (which may be
empty). The extension supplies the fill-mode hint; the metadata's
`document.kind: "form"` makes the intent visible to agents and other tools.

## File grammar

The file is UTF-8 text. The first line is exactly `---`. The next block is one
JSON object. It is closed by a line containing exactly `---` (a closing `...`
is accepted when reading). The body starts immediately after that delimiter.
The body is opaque to the metadata parser: blank lines, trailing spaces and
line endings are preserved by `LeonardoFormatParser`.

```text
---
{
  "format": "mdlf",
  "formatVersion": 1,
  "document": { "kind": "form", "id": "contact", "revision": 1 },
  "fields": {},
  "values": {},
  "layout": {}
}
---
# Markdown body
```

`format` and `formatVersion` are mandatory. Version `1` is the only version
currently supported. Readers must reject a future version instead of guessing
its meaning. The v1 structural vocabulary is closed: an unknown property is a
parse error with its JSON path, which prevents an editor from silently
discarding data it cannot preserve. Arbitrary JSON remains valid inside
`values` and `defaultValue`. Structural entries with an identity (`field.type`,
option `value`, image `source`, table `occurrence`, and dimension `value` plus
`unit`) are required. A future structural extension requires a new
`formatVersion`.

The public portable Swift contract is:

```swift
try LeonardoFormatParser.parse(source) -> LeonardoDocument
try LeonardoFormatParser.serialize(document) -> String
LeonardoFormatParser.detect(source) -> LeonardoFormatDetection
LeonardoFormatValidator.validate(document, context: .draft)
```

The machine-readable Draft 2020-12 schema is kept beside this document at
`doc/format/mdlf-v1.schema.json`. It describes the same closed structural
vocabulary and optional layout defaults as the Swift reader.

The app may save a draft with validation warnings. A final submission uses
`.submission`, which turns missing required values into errors.

## Metadata

`document` contains an optional stable `id`, human title, `kind` (`document`
or `form`), semantic template `revision` and BCP-47 `locale`. The semantic
revision is separate from `formatVersion`; changing a form's fields should
usually increment it.

`fields` is an object keyed by a stable field identifier. IDs match
`[A-Za-z][A-Za-z0-9_.-]{0,63}`. A body placeholder uses that identifier:

```markdown
Nombre: {{field:name}}

Comentario: {{field:comment}}
```

Whitespace inside a placeholder is allowed (`{{ field:name }}`). An unknown
placeholder is a validation error. Field values live in `values`, never in the
body. The same value can therefore be rendered in several places without
duplicating the response.

Supported field types are `text`, `multiline`, `number`, `date`, `checkbox`,
`select`, `email` and `url`. Definitions may contain `label`, `required`,
`readOnly`, `minLength`, `maxLength`, `pattern`, `minimum`, `maximum`,
`options`, `placeholder`, `helpText`, `validationMessage` and `defaultValue`.

Values are JSON primitives (`string`, finite `number`, `boolean` or `null`),
arrays and objects are retained for forward-compatible metadata but are not
valid values for the built-in scalar field types. `select` values must match an
option's `value`. A missing required value is a warning while editing and an
error on submission; an incomplete response can always be saved as a draft.

Patterns use ICU/`NSRegularExpression` syntax. To keep validation bounded,
v1 applies a 25 ms matching budget, limits expressions to 512 UTF-8 bytes, rejects backreferences, look-around
and quantified groups (including `(a|aa)+`), and caps a value checked by a
pattern at 32 KiB. Applications may impose stricter limits. A non-empty
`validationMessage` replaces the default message when a field value fails a
constraint. Dates use the proleptic Gregorian calendar in UTC and must be
real `YYYY-MM-DD` dates, including leap-year rules.

## Declarative layout

Layout is optional. Markdown flow remains the default; absolute placement is a
controlled exception for stationery, logos and overlays. Measurements use
points or percentages:

```json
"layout": {
  "page": {
    "size": "a4",
    "orientation": "portrait",
    "margins": { "top": 36, "right": 36, "bottom": 36, "left": 36 }
  },
  "background": {
    "color": "#F8F8F5",
    "image": "assets/letterhead.png",
    "opacity": 0.25,
    "fit": "cover",
    "position": { "placement": "absolute", "x": { "value": 50, "unit": "percent" }, "y": { "value": 50, "unit": "percent" } }
  },
  "images": [
    {
      "source": "assets/logo.svg",
      "occurrence": 1,
      "size": { "width": { "value": 28, "unit": "percent" }, "preserveAspectRatio": true },
      "position": { "placement": "relative", "x": { "value": -4, "unit": "percent" } },
      "fit": "contain",
      "opacity": 1
    }
  ],
  "tables": [
    {
      "occurrence": 1,
      "columns": [
        { "width": { "value": 32, "unit": "percent" } },
        { "width": { "value": 240, "unit": "points" } },
        {}
      ],
      "repeatHeader": true,
      "allowRowBreak": true
    }
  ]
}
```

`background.image` and `images[].source` are the portable resource keys used
by MDLZ. They are relative asset paths or `http`/`https` URLs; absolute paths,
`file:`, `data:`, traversal (`..`) and executable schemes are invalid. Image
occurrences and table occurrences are one-based document-order matches. A
missing image/table entry uses normal Markdown flow. An image's `position` can
be `flow`, `relative` or `absolute`; offsets may be signed. `width` and
`height` use positive dimensions, while a position offset may be negative.

Table width comments such as `<!-- leonardo:table widths=... -->` are not part
of MDLF v1 and Leonardo must not generate them. Existing `.md` files can still
be rendered as standard Markdown; conversion to MDLF is an explicit save or
export operation.

## MDLZ transport

MDLZ is an ordinary ZIP, not a second document format. It contains exactly one
document at the archive root and an optional `assets/` tree:

```text
request.mdlz
├── request.mdlr
└── assets/
    ├── letterhead.png
    └── logo.svg
```

The contained document keeps its extension and relative references. A package
reader must reject absolute paths, `..` components, duplicate normalized names,
symlinks and entries that escape the extraction directory. Extraction is an
explicit user choice; a package can also be worked on in an application-owned
temporary directory and rewritten on save. When a user chooses extraction,
Leonardo works on the extracted MDLF/MDLR and requires **Export package…** to
create a new MDLZ.

