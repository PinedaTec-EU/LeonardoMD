# Bundled user guide

The macOS app ships `Guide-v4-en.mdlz` and `Guide-v4-es.mdlz`. Help and Welcome
open a user-owned copy in
`~/Library/Application Support/LeonardoMD/User Guides/v4/<language>/` through
normal document tabs in package mode. Ordinary package-opening preferences
remain unchanged. Existing v2/v3 copies and practice answers are never overwritten.

`en/body.md` and `es/body.md` are the editorial sources. The 19 chapters cover
current macOS workflows, with live Mermaid/KaTeX/Vega examples, literal citation
and Markdown-extras examples, a practice form, three generated diagrams, the
approved About banner and original localized UI screenshots. See the
[source-backed feature inventory](feature-coverage.md).

The repository's [help maintenance skill](../../.skills/leonardo-user-guide/SKILL.md)
and PR template require feature-changing PRs to update both locales in the same
PR, including relevant images/examples and regenerated packages. Internal-only
changes explain their lack of help impact.

Run `python3 scripts/package-user-guide.py` after content or asset edits. The
canonical plugin helper validates and deterministically packages one `guide.mdlf`
plus local assets. Only PNGs from locale `assets/` folders are copied; capture
contexts/metadata stay in Git for provenance and never enter the user package.
The approved banner and three SVG diagrams are supplied by the builder.

For a published guide revision, advance metadata revision, resource names and
personal-copy directory together. Remove superseded application resources;
preserve historical evidence and existing user working copies. Every supported
`AppLanguage` needs a matching package. Native tests verify both locales,
all packaged images, live outputs and practice/save behavior. Python tests
verify deterministic bytes, complete image references and exclusion of QA files.

Instructional screenshots are original production-component captures with
synthetic data. Their sidecars identify their capture source and time; they
are content assets, not a claim of device sharing, update installation or fresh
packaged-process acceptance. New review captures must use the current source
and be recorded separately under `doc/validation/`.

Revision 3's recommendation UI evidence remains historical at
[extension recommendations](../validation/extension-recommendations/README.md).
Revision 2's packaged-process acceptance remains historical at
[user guide validation](../validation/user-guide/README.md).

Tracking: [#290](https://github.com/PinedaTec-EU/LeonardoMD/issues/290),
[#310](https://github.com/PinedaTec-EU/LeonardoMD/issues/310).
