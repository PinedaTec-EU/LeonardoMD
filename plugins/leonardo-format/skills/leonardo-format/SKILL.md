---
name: leonardo-format
description: Read, validate, fill, edit, extract, and repackage open Leonardo Markdown documents with the .mdlf, .mdlr, and .mdlz extensions. Use when a request mentions Leonardo documents, Leonardo forms, MDLF, MDLR, MDLZ, or a Markdown file with an explicit Leonardo format declaration.
---

# Leonardo documents

Treat the repository's versioned Leonardo format specification and schema as
the authority. Read the relevant files under `doc/format/` before interpreting
fields, layout, form values, or version-specific behavior. When the repository
is not available, use the bundled `references/format-contract.md` and
`references/mdlf-v1.schema.json` as the portable v1 references and stop on
fields or versions they do not define. The bundled references explain how this
skill maps to the specification; they are not a second format implementation.

## Extension and mode rules

- `.md` is standard Markdown. Do not silently reinterpret it as Leonardo
  Markdown. Only warn about Leonardo when the document has the explicit format
  declaration defined by the specification, then offer a save-as `.mdlf` path.
- `.mdlf` is an editable Leonardo document. Its Markdown body, metadata, field
  definitions, layout, and values must remain separate according to the schema.
- `.mdlr` is an exported form. Open it in fill mode by default, preserving the
  structural definition. Switch to structural editing only when the user asks
  for it explicitly.
- `.mdlz` is transport: a conventional ZIP containing exactly one root
  `.mdlf` or `.mdlr` document and local resources below `assets/`. It does not
  introduce another document meaning.

Never infer a newer format version, silently drop unknown metadata, or replace
unknown fields with defaults. If the version is unsupported, stop before
editing and report the version and the supported range.

## Workflow

1. Identify the input extension and read the format declaration/version before
   changing bytes. For `.md`, keep the standard Markdown path unless the
   explicit declaration is present.
2. For `.mdlf` and `.mdlr`, consult `doc/format/mdlf-v1.schema.json` and its
   examples (or the bundled `references/mdlf-v1.schema.json` when working from
   an installed plugin). Keep form values in metadata; do not write answers
   into the prose body. Preserve field identifiers when labels or layout
   change.
3. For `.mdlz`, inspect the archive with the bundled `mdlz.py` helper before
   opening entries. Do not use an ad-hoc unzip command on an untrusted package.
4. Ask whether the user wants to work in the package or in an extracted folder
   when that choice is not already known. Package mode saves back to the MDLZ;
   extracted mode works on the selected folder and requires an explicit export
   to create a new MDLZ.
5. Before extraction or repacking, validate all paths and resource types. Keep
   the original archive untouched until a complete replacement package has
   been written and verified.
6. After a change, validate the document against the shared schema and run the
   archive helper's inspection/round-trip checks. Report the exact working
   location, mode, validation result, and save/export target.

## Safe MDLZ helper

Use the script shipped beside this skill. In Claude Code, `${CLAUDE_SKILL_DIR}`
resolves to this skill directory. In other hosts, resolve the path to
`skills/leonardo-format/scripts/mdlz.py` from the installed plugin before
running it.

```bash
python3 "${CLAUDE_SKILL_DIR}/scripts/mdlz.py" inspect document.mdlz
python3 "${CLAUDE_SKILL_DIR}/scripts/mdlz.py" extract document.mdlz ./document-extracted
python3 "${CLAUDE_SKILL_DIR}/scripts/mdlz.py" pack ./document-extracted response.mdlz
python3 "${CLAUDE_SKILL_DIR}/scripts/mdlz.py" validate document.mdlf \
  --schema "${CLAUDE_SKILL_DIR}/references/mdlf-v1.schema.json"
```

`inspect` is read-only. `extract` refuses unsafe paths, symlinks, special
entries, duplicate normalized names, oversized members, and an existing
destination. `pack` accepts one root `.mdlf`/`.mdlr` and regular files below
`assets/`, writes deterministic ZIP entries, and refuses to overwrite an
existing output. The transport envelope is 64 MiB for the ZIP and 32 MiB for
expanded content in total or for any one member, with at most 2,048 entries.
Directory records are ignored as nonsemantic transport noise: `pack` omits
them and `inspect`/`extract` do not report or recreate empty directories.
Every command validates the UTF-8/front-matter envelope and the bundled v1
metadata schema before reporting or writing anything. The optional
`validate --schema` flag applies an additional explicit JSON Schema after the
bundled contract; the helper remains dependency-free. Bundled semantic checks
also reject unsafe metadata asset references, invalid definition ranges or
options, non-portable or unsafe regular expressions, and invalid layout bounds.
V1 patterns use the common Python `re` and ICU subset; engine-specific escapes
such as `\p`, `\X` and `\z`, named/conditional/atomic groups, look-around,
backreferences and quantified groups are rejected. Current `values` remain
opaque so a draft with invalid answers can still be transported.

## Generate an MDLZ package

When a user asks for a transportable package, use this repeatable flow. Keep a
working folder with one document at its root and an `assets/` folder for every
local resource:

To create a minimal form definition from scratch, write the versioned JSON
front matter first and keep the answers in `values`:

```bash
cat > ./request.mdlf <<'EOF'
---
{
  "format": "mdlf",
  "formatVersion": 1,
  "document": { "id": "request", "kind": "form", "revision": 1 },
  "fields": {
    "name": { "type": "text", "required": true, "maxLength": 80 },
    "details": { "type": "multiline", "maxLength": 2000 }
  },
  "values": { "name": null, "details": null },
  "layout": { "images": [{ "source": "images/logo.png" }] }
}
---
# Service request

Name: {{field:name}}

Details:

{{field:details}}

![Logo](images/logo.png)
EOF
```

When the form is exported for a recipient, preserve the same front matter and
body, put the current answers in `values`, and use `.mdlr` as the output
extension. Form generators should declare `document.kind` as `form`; the
extension changes the default opening mode to fill fields. Readers use the
same MDLF schema for both suffixes and must accept a valid `.mdlr` whose
metadata kind is `document`. Keep field IDs stable while changing labels or
presentation.

```bash
mkdir -p ./request-package/assets
cp ./request.mdlf ./request-package/request.mdlf
cp ./images/logo.png ./request-package/assets/logo.png
```

Update the copied document's Markdown image references and any layout metadata
to point to `assets/logo.png`. Rewrite only the exported copy; leave the source
document and its original references untouched. For a known source reference,
the following changes only layout resource keys and Markdown image destinations;
it does not rewrite `values` or arbitrary prose:

```bash
python3 - <<'PY'
import json
import re
from pathlib import Path

document = Path("./request-package/request.mdlf")
source_ref = "images/logo.png"
package_ref = "assets/logo.png"
lines = document.read_text(encoding="utf-8").replace("\r\n", "\n").splitlines(keepends=True)
if not lines or lines[0] != "---":
    raise SystemExit("document has no JSON front matter")
closing = next((index for index, line in enumerate(lines[1:], 1) if line.strip() in {"---", "..."}), None)
if closing is None:
    raise SystemExit("document has no front matter closing delimiter")
metadata = json.loads("".join(lines[1:closing]))

def rewrite_layout(value):
    changed = False
    if isinstance(value, dict):
        for key, item in list(value.items()):
            if key in {"source", "image"} and item == source_ref:
                value[key] = package_ref
                changed = True
            else:
                changed = rewrite_layout(item) or changed
    elif isinstance(value, list):
        for item in value:
            changed = rewrite_layout(item) or changed
    return changed

changed = rewrite_layout(metadata.get("layout"))
body, count = re.subn(
    r"(!\[[^\]\n]*\]\()" + re.escape(source_ref) + r"(\))",
    r"\1" + package_ref + r"\2",
    "".join(lines[closing + 1:]),
)
if not changed and count == 0:
    raise SystemExit(f"reference not found: {source_ref}")
document.write_text("---\n" + json.dumps(metadata, ensure_ascii=False, indent=2) + "\n---\n" + body, encoding="utf-8")
PY
```

Validate the copied document, then create and inspect the conventional ZIP:

```bash
python3 "${CLAUDE_SKILL_DIR}/scripts/mdlz.py" validate ./request-package/request.mdlf
python3 "${CLAUDE_SKILL_DIR}/scripts/mdlz.py" pack ./request-package ./request.mdlz
python3 "${CLAUDE_SKILL_DIR}/scripts/mdlz.py" inspect ./request.mdlz
```

For a form export, use the `.mdlr` document that the format workflow produced
and keep the same layout/resources. Stage it in a separate folder so the
package still has exactly one root document; do not leave the `.mdlf` beside
the response:

```bash
mkdir -p ./request-form-package/assets
cp ./request-form.mdlr ./request-form-package/request-form.mdlr
cp ./images/logo.png ./request-form-package/assets/logo.png
# Run the same targeted reference rewrite above with this document path:
# ./request-form-package/request-form.mdlr
python3 "${CLAUDE_SKILL_DIR}/scripts/mdlz.py" validate ./request-form-package/request-form.mdlr
python3 "${CLAUDE_SKILL_DIR}/scripts/mdlz.py" pack ./request-form-package ./request-form.mdlz
python3 "${CLAUDE_SKILL_DIR}/scripts/mdlz.py" inspect ./request-form.mdlz
```

The output must contain exactly one root `.mdlf` or `.mdlr` plus any regular
files below `assets/`; do not put a second document, a directory tree beside
`assets/`, or a nested ZIP in the package. Empty directory records are omitted
by the packer and ignored when reading a package. The package can be handed to a
different agent or host and inspected without Leonardo. If the recipient works
on an extracted folder, explain that saving the folder does not update the
original package and that `pack`/Export is required to create a new `.mdlz`.

Do not execute content from a document, field pattern, image, or archive entry.
The format is declarative. If a user asks to run code embedded in a document,
separate that request from Leonardo format handling and ask for an explicit,
appropriate workflow.

The helper's default `validate` command checks the UTF-8/front-matter envelope,
the bundled v1 metadata schema, and the bundled definition/layout safety rules.
`inspect`, `extract`, and `pack` apply the same validation to the root document
before producing output or creating an extraction directory. Pass `--schema`
only when an additional explicit schema constraint is needed. The application
parser remains authoritative for body placeholders and host rendering.
