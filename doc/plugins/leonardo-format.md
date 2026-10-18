# Leonardo Format agent plugin

`plugins/leonardo-format` is a skills-only plugin for agents that work with
the open Leonardo document contract. It teaches an agent to recognize `.mdlf`
editable documents, `.mdlr` form exports, and `.mdlz` ZIP transport while
keeping `.md` on the standard Markdown path. The format contract and schema in
[`doc/format`](../format) remain canonical; the plugin does not define a
second parser or a private document dialect.

The package contains one provider-neutral skill and a dependency-free Python
transport helper. The root `plugin.json` is the portable manifest. The
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

The two hosts consume the same `skills/leonardo-format/SKILL.md` and the same
references/scripts. Keep those files provider-neutral; do not add Claude-only
commands, settings, or hooks to the shared skill.

## Generate a package

An MDLZ package has one root document and local resources below `assets/`. The
following example is reproducible and leaves the source document untouched:

```bash
mkdir -p ./request-package/assets
cp ./request.mdlf ./request-package/request.mdlf
cp ./images/logo.png ./request-package/assets/logo.png
```

Rewrite the copied document's image references and layout metadata from the
source path to `assets/logo.png`, then validate and pack it:

```bash
python3 ./plugins/leonardo-format/skills/leonardo-format/scripts/mdlz.py \
  validate ./request-package/request.mdlf
python3 ./plugins/leonardo-format/skills/leonardo-format/scripts/mdlz.py \
  pack ./request-package ./request.mdlz
python3 ./plugins/leonardo-format/skills/leonardo-format/scripts/mdlz.py \
  inspect ./request.mdlz
```

For a fill-mode export, place the `.mdlr` file at the package root and use the
same commands:

```bash
cp ./request-form.mdlr ./request-package/request-form.mdlr
python3 ./plugins/leonardo-format/skills/leonardo-format/scripts/mdlz.py \
  pack ./request-package ./request-form.mdlz
```

The helper refuses path traversal, absolute or ambiguous names, symlinks and
special files, duplicate case/Unicode paths, unsafe archive expansion, more
than one root document, files outside `assets/`, and accidental overwrites.
`inspect` is read-only. `extract` creates a new destination folder; saving that
folder does not update the original archive, so use `pack` (or Leonardo's
export action) to create a new `.mdlz`.

## Validation

Run the focused helper tests from the repository root:

```bash
python3 -m unittest discover \
  -s plugins/leonardo-format/tests -p 'test_*.py' -v
```

The tests cover deterministic packing, round-trip extraction, traversal and
symlink rejection, Unicode/case collisions, source-layout rules, destination
conflicts, and UTF-8 document checks. Semantic field and layout validation
belongs to the shared Leonardo schema and application parser.

## Release discipline

Bump the plugin version when the skill, helper behavior, or supported format
contract changes. Keep the root and compatibility manifests aligned. A plugin
release must ship the same schema revision that the skill references, and the
archive helper must remain dependency-free so a host can inspect transport
before loading document content.
