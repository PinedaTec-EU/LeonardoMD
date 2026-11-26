# Leonardo Format agent plugin

`plugins/leonardo-format` is a skills-only plugin for agents that work with
the open Leonardo document contract. It teaches an agent to recognize `.mdlf`
editable documents, `.mdlr` form exports, and `.mdlz` ZIP transport while
keeping `.md` on the standard Markdown path. The format contract and schema in
[`doc/format`](../format) remain canonical; the plugin does not define a
second parser or a private document dialect.

The package contains one provider-neutral skill, bundled MDLF v1 and v2
schemas, and dependency-free Python transport helpers. The runtime
modules are `mdlf_schema.py`, `mdlf_semantics.py`, `mdlz.py`, and
`mdlz_extract.py` under `skills/leonardo-format/scripts/`; the latter owns the
descriptor-relative extraction boundary. The root
`plugin.json` is the portable manifest. The
`.claude-plugin/plugin.json` file supports direct Claude Code plugin loading,
and `.codex-plugin/plugin.json` supplies the Codex compatibility overlay. No
MCP server, credentials, hooks, or network service are required.

## Preview in Codex

Add the public PinedaTec Leonardo marketplace using the Codex CLI:

```bash
codex plugin marketplace add PinedaTec-EU/LeonardoMD --sparse .agents/plugins --sparse plugins/leonardo-format
```

In Codex desktop, open **Plugins**, choose **PinedaTec Leonardo**, and install
**Leonardo Format**. If the catalog is already installed, run
`codex plugin marketplace upgrade pinedatec-leonardo` and refresh the app.
With a real Python 3.9 or newer interpreter already installed on the same
computer and Leonardo Sync enabled, open a chat with access to your file and
ask **“Preview this Leonardo document in Codex”**, including its path. On
macOS, `/usr/bin/python3` may be a developer-tools installation shim; the Sync
helper never invokes it and never prompts to install it. If preview is
unavailable, install Python 3.9+ from a trusted source such as Homebrew or
python.org, restart Leonardo or its Sync helper, and retry. Ordinary Sync
continues to work without Python. The plugin opens an in-app browser tab for
any supported v1 or v2 `.mdlf`, `.mdlr` or `.mdlz`.

The preview uses Leonardo's bundled renderer for form values, Mermaid,
KaTeX, charts, citations, tables and local images. Standalone inputs resolve
images below the document folder, while packages resolve them from their
`assets/` entries. The viewer is read-only and blocks remote resources.
Each preview is registered with the persistent Sync helper, runs on loopback
for up to one hour, and serves only the document's referenced resources. Direct
registration rejects files below Leonardo's managed `DesktopPeers` and
`MobileSync` directories, including cached or revoked remote content. Use the
authorized native Leonardo preview for managed remote documents; copying cache
bytes to another path is not a way to bypass project access or revocation. Ask
again after editing the document to open a fresh view.

### Automatic preview links in chats

After installing or updating Leonardo Format, review and trust its
`Stop` hook in Codex. In the Codex CLI, use `/hooks` to review it.
This is a one-time step for the current hook definition. When the plugin is enabled and a response delivers a local
Leonardo file as a Markdown link, the hook can request one continuation
to add **Vista previa de Leonardo** next to that file. Click the preview
link while its local server is active. The source link still opens the
ordinary Codex file viewer.

This works in local Codex sessions that support trusted plugin hooks and can
register the preview with the Sync helper on the computer with the browser. A
remote, unavailable, or Sync-disabled file can still be delivered with its
original link.

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

The two hosts consume the same `skills/leonardo-format/SKILL.md` and bundled
schemas at `skills/leonardo-format/references/mdlf-v1.schema.json` and
`skills/leonardo-format/references/mdlf-v2.schema.json`. Repository tests compare
them byte-for-byte against the canonical schemas in `doc/format`, so the
installed plugin can validate both versions offline. Keep those files provider-neutral; do not
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
Each ZIP member is limited to 64 slash-separated components, including its
filename. The transport envelope is 64 MiB for the ZIP and 32 MiB for expanded
content in total or for any one member, with at most 2,048 entries. Directory
records are validated for safe paths but are nonsemantic transport noise:
`pack` omits them, while `inspect` and `extract` ignore them. `inspect` is
read-only.

`extract` atomically claims a new destination directory with POSIX
descriptor-relative `mkdir`, traverses each component with `O_NOFOLLOW`, and
writes files with descriptor-relative exclusive creation. Failure cleanup is
ownership-aware and leaves preexisting, injected, or replacement entries
intact. If `dir_fd` or no-follow support is unavailable, extraction fails
closed; `inspect`, `validate`, and `pack` remain usable and MDLZ remains a
conventional ZIP. This boundary does not claim isolation from arbitrary
privileged or same-UID processes that can modify the filesystem. Saving an
extracted folder does not update the original archive, so use `pack` (or
Leonardo's export action) to create a new `.mdlz`.

On macOS, the descriptor walk recognizes only the root-owned `/tmp` and `/var`
aliases to `/private/tmp` and `/private/var`; user-controlled symlink
components are rejected.

The helper has no third-party runtime dependency. Every command validates the
UTF-8/front-matter envelope, the bundled schema for the declared MDLF version
and the bundled definition and layout rules before reporting or writing
anything. For v2 forms it also validates the signing declaration and signer
references. Those
semantic checks reject unsafe metadata asset references, invalid definition
ranges or options, non-portable or unsafe regular expressions, and invalid
layout bounds while leaving current draft values opaque. Field patterns use the
common Python `re`/ICU subset and reject engine-specific escapes such as
`\p`, `\X` and `\z`, named/conditional/atomic groups, look-around,
backreferences and quantified groups. Pass `--schema` only when an additional
explicit JSON Schema constraint is needed:

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
file/symlink/directory conflicts, descriptor-relative parent-symlink races,
atomic root-claim replacement, ownership-aware failure cleanup, the 64-component
limit, duplicate keys, unknown metadata, unsupported versions and UTF-8/front-
matter checks. The bundled evaluator and semantic checks apply the
shared field and layout contract from the canonical v1 and v2 schemas
(or the corresponding bundled copy when the plugin is installed). The application parser remains
authoritative for host rendering and body behavior. The helper stays
dependency-free; `--schema` adds an explicit second schema constraint.

## Release discipline

Refresh the offline renderer archive with
`python3 plugins/leonardo-format/package-renderer.py` whenever the shared renderer
resources change. Plugin tests compare the archive contents with the
canonical renderer, including its license notices.

Bump the plugin version when the skill, helper behavior, or supported format
contract changes. Keep the root and compatibility manifests aligned. A plugin
release must ship the same schema revision that the skill references, and the
archive helper must remain dependency-free so a host can inspect transport
before loading document content.

MDLZ validation also limits distinct implicit parent directories to 2,048, rejects differently spelled parent paths with the same NFC/casefold key, and verifies the claimed destination and extracted tree before returning. These limits apply to native reading/writing and plugin inspection/extraction/packing.
