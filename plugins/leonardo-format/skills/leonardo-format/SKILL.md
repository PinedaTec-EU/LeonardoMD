---
name: leonardo-format
description: Read, validate, fill, edit, extract, and repackage open Leonardo Markdown documents with the .mdlf, .mdlr, and .mdlz extensions. Use when a request mentions Leonardo documents, Leonardo forms, MDLF, MDLR, MDLZ, or a Markdown file with an explicit Leonardo format declaration.
---

# Leonardo documents

Treat the repository's versioned Leonardo format specification and schema as
the authority. Read the relevant files under `doc/format/` before interpreting
fields, layout, form values, or version-specific behavior. The files bundled
under `references/` explain how this skill maps to that specification; they are
not a second format implementation.

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
2. For `.mdlf` and `.mdlr`, consult the canonical schema and examples. Keep
   form values in metadata; do not write answers into the prose body. Preserve
   field identifiers when labels or layout change.
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
```

`inspect` is read-only. `extract` refuses unsafe paths, symlinks, special
entries, duplicate normalized names, oversized members, and an existing
destination. `pack` accepts one root `.mdlf`/`.mdlr` and regular files below
`assets/`, writes deterministic ZIP entries, and refuses to overwrite an
existing output. The helper is a transport safety boundary; semantic document
validation still comes from the versioned Leonardo schema.

## Generate an MDLZ package

When a user asks for a transportable package, use this repeatable flow. Keep a
working folder with one document at its root and an `assets/` folder for every
local resource:

```bash
mkdir -p ./request-package/assets
cp ./request.mdlf ./request-package/request.mdlf
cp ./images/logo.png ./request-package/assets/logo.png
```

Update the copied document's Markdown image references and any layout metadata
to point to `assets/logo.png`. Rewrite only the exported copy; leave the source
document and its original references untouched. Validate the copied document,
then create and inspect the conventional ZIP:

```bash
python3 "${CLAUDE_SKILL_DIR}/scripts/mdlz.py" validate ./request-package/request.mdlf
python3 "${CLAUDE_SKILL_DIR}/scripts/mdlz.py" pack ./request-package ./request.mdlz
python3 "${CLAUDE_SKILL_DIR}/scripts/mdlz.py" inspect ./request.mdlz
```

For a form export, use the `.mdlr` document that the format workflow produced
and keep the same layout/resources:

```bash
cp ./request-form.mdlr ./request-package/request-form.mdlr
python3 "${CLAUDE_SKILL_DIR}/scripts/mdlz.py" pack ./request-package ./request-form.mdlz
```

The output must contain exactly one root `.mdlf` or `.mdlr` plus any regular
files below `assets/`; do not put a second document, a directory tree beside
`assets/`, or a nested ZIP in the package. The package can be handed to a
different agent or host and inspected without Leonardo. If the recipient works
on an extracted folder, explain that saving the folder does not update the
original package and that `pack`/Export is required to create a new `.mdlz`.

Do not execute content from a document, field pattern, image, or archive entry.
The format is declarative. If a user asks to run code embedded in a document,
separate that request from Leonardo format handling and ask for an explicit,
appropriate workflow.
