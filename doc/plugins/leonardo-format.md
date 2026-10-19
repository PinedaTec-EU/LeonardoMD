# Leonardo Format agent plugin

`plugins/leonardo-format` is a skills-only plugin for agents that work with
the open Leonardo document contract. It teaches an agent to recognize `.mdlf`
editable documents, `.mdlr` form exports, and `.mdlz` ZIP transport while
keeping `.md` on the standard Markdown path. The format contract and schema in
[`doc/format`](../format) remain canonical; the plugin does not define a
second parser or a private document dialect.

The package contains one provider-neutral skill, a bundled copy of the v1
machine schema, and a dependency-free Python transport helper. The root
`plugin.json` is the portable manifest. The
`.claude-plugin/plugin.json` file supports direct Claude Code plugin loading,
and `.codex-plugin/plugin.json` supplies the Codex compatibility overlay. No
MCP server, credentials, hooks, or network service are required.

## Local installation

For Claude Code development, load the directory directly:

```bash
claude --plugin-dir ./plugins/leonardo-format
```

For a shared Claude installation, put the directory in a Claude Code
marketplace and install it at the desired user, project, or local scope. The
official plugin documentation describes marketplace entries and validation:
<https://code.claude.com/docs/en/plugins>.

Codex uses the portable root manifest or its `.codex-plugin` compatibility
manifest through the Codex plugin directory/marketplace workflow. The OpenAI
plugin documentation describes the supported package layout and local testing:
<https://developers.openai.com/plugins/build/plugins>.

The two hosts consume the same `skills/leonardo-format/SKILL.md`, the bundled
schema at `skills/leonardo-format/references/mdlf-v1.schema.json`, and the same
references/scripts. Repository tests check the bundled schema byte-for-byte
against the canonical `doc/format/mdlf-v1.schema.json`, so an installed plugin
can carry the v1 contract offline. Keep those files provider-neutral; do not
add Claude-only commands, settings, or hooks to the shared skill.

## Generate a package

An MDLZ package has one root document and local resources below `assets/`. The
following example is reproducible and leaves the source document untouched:

Create a small MDLF form with typed fields and empty values before adding
resources:

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

An exported response keeps that definition and body, replaces `values` with
the current answers, and uses `.mdlr`. Preserve the field IDs and leave
`document.kind` as `form` when generating a form. The extension gives agents
the fill-mode hint; readers still use the shared MDLF schema and accept a
valid `.mdlr` whose metadata kind is `document`.

```bash
mkdir -p ./request-package/assets
cp ./request.mdlf ./request-package/request.mdlf
cp ./images/logo.png ./request-package/assets/logo.png
```

Rewrite the copied document's Markdown image references and layout metadata
from the source path to `assets/logo.png`. This example changes only layout
resource keys and Markdown image destinations; it does not rewrite `values` or
arbitrary prose:

```bash
python3 - <<'PY'
import json
import re
from pathlib import Path

document = Path("./request-package/request.mdlf")
source_ref = "images/logo.png"
package_ref = "assets/logo.png"
lines = document.read_text(encoding="utf-8").replace("\r\n", "\n").splitlines(keepends=True)
if not lines or lines[0].strip() != "---":
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

Then validate and pack it:

```bash
python3 ./plugins/leonardo-format/skills/leonardo-format/scripts/mdlz.py \
  validate ./request-package/request.mdlf
python3 ./plugins/leonardo-format/skills/leonardo-format/scripts/mdlz.py \
  pack ./request-package ./request.mdlz
python3 ./plugins/leonardo-format/skills/leonardo-format/scripts/mdlz.py \
  inspect ./request.mdlz
```

For a fill-mode export, use a separate staging folder so the `.mdlr` is the
only root document. Copy its assets and run the same targeted rewrite above
with `document` set to `./request-form-package/request-form.mdlr`:

```bash
mkdir -p ./request-form-package/assets
cp ./request-form.mdlr ./request-form-package/request-form.mdlr
cp ./images/logo.png ./request-form-package/assets/logo.png
python3 ./plugins/leonardo-format/skills/leonardo-format/scripts/mdlz.py \
  validate ./request-form-package/request-form.mdlr
python3 ./plugins/leonardo-format/skills/leonardo-format/scripts/mdlz.py \
  pack ./request-form-package ./request-form.mdlz
python3 ./plugins/leonardo-format/skills/leonardo-format/scripts/mdlz.py \
  inspect ./request-form.mdlz
```

The helper refuses path traversal, absolute or ambiguous names, symlinks and
special files, duplicate case/Unicode paths, unsafe archive expansion, more
than one root document, files outside `assets/`, and accidental overwrites.
`inspect` is read-only. `extract` creates a new destination folder; saving that
folder does not update the original archive, so use `pack` (or Leonardo's
export action) to create a new `.mdlz`.

The helper has no third-party runtime dependency. Its default `validate`
command checks the UTF-8/front-matter envelope; when a host already provides
the optional `jsonschema` package, pass the bundled schema explicitly for
metadata validation:

```bash
python3 ./plugins/leonardo-format/skills/leonardo-format/scripts/mdlz.py \
  validate ./request-package/request.mdlf \
  --schema ./plugins/leonardo-format/skills/leonardo-format/references/mdlf-v1.schema.json
```

## Validation

Run the focused helper tests from the repository root:

```bash
python3 -m unittest discover \
  -s plugins/leonardo-format/tests -p 'test_*.py' -v
```

The tests cover deterministic packing, round-trip extraction, traversal and
symlink rejection, Unicode/case collisions, source-layout rules, destination
conflicts, and UTF-8 document checks. Semantic field and layout validation
belongs to `doc/format/mdlf-v1.schema.json` (or the bundled copy when the
plugin is installed) and the application parser. The helper's `validate`
command checks the UTF-8/front-matter envelope by default; `--schema` enables
optional metadata JSON Schema validation when `jsonschema` is available.

## Release discipline

Bump the plugin version when the skill, helper behavior, or supported format
contract changes. Keep the root and compatibility manifests aligned. A plugin
release must ship the same schema revision that the skill references, and the
archive helper must remain dependency-free so a host can inspect transport
before loading document content.
