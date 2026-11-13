# Bundled user guide

The macOS app ships `Guide-v73-en.mdlz` and `Guide-v73-es.mdlz`. Help and Welcome
open a user-owned copy in
`~/Library/Application Support/LeonardoMD/User Guides/v73/<language>/` through
normal document tabs in package mode. Ordinary package-opening preferences
remain unchanged. Existing guide copies and practice answers are never overwritten.

`en/body.md` and `es/body.md` are the editorial sources. The 19 chapters cover
macOS workflows and Little Leonardo's host → project → file library, with live Mermaid/KaTeX/Vega examples, literal citation
and Markdown-extras examples, a separate practice form, generated diagrams, the
approved About banner and original localized UI screenshots. See the
[source-backed feature inventory](feature-coverage.md).

Guide v73 combines current document search and remote project workflows with the latest synchronization status and helper-recovery guidance, plus optional grouped-instance instructions. Its distinct revision ensures installations with a saved v68, v71 or v72 guide receive this content while preserving earlier guide copies and their separate practice answers; opening Help never replaces a saved copy.

File → Import with your agent opens `AgentImport-v3-en.mdlz` or
`AgentImport-v3-es.mdlz` in the same tab/package flow, with personal copies under
`~/Library/Application Support/LeonardoMD/Agent Import Guides/v3/<language>/`.
The standalone guide is generated from the marked agent-import section of
chapter 6 in the same bilingual body sources. Its illustrative PNG requires no
optional extension. This help entry does not select, send or convert a PDF;
the user supplies a copy to their external agent using the Leonardo Format skill.

The repository's [help maintenance skill](../../.skills/leonardo-user-guide/SKILL.md)
and PR template require feature-changing PRs to update both locales in the same
PR, including relevant images/examples and regenerated packages. Internal-only
changes explain their lack of help impact.

Run `python3 scripts/package-user-guide.py --web-output doc` after content or asset edits. The
canonical plugin helper validates and deterministically packages one `guide.mdlf`
plus local assets. Only PNG content assets from locale `assets/` folders are copied; capture
contexts/metadata stay in Git for provenance and never enter the user package.
The builder supplies a lightweight `cover.png` derivative of the approved banner
(the original About artwork is unchanged); locale `assets/` folders supply the
transparent Leonardo Classic PNG illustrations. Artwork provenance is stored beside each locale’s assets.
The four 1200×400 illustrations bound decoded memory without altering renderer limits.
The optional `--web-output doc` also regenerates both web manuals and their
localized PNG illustration links from the same sources, adapting image paths and showing
field placeholders as literal source rather than nonfunctional form controls.

For a published guide revision, advance metadata revision, resource names and
personal-copy directory together. Remove superseded application resources;
preserve historical evidence and existing user working copies. Every supported
`AppLanguage` needs a matching package. Native tests verify both locales,
all packaged images, live outputs and practice/save behavior. Python tests
verify deterministic bytes, complete image references and exclusion of QA files.

Instructional screenshots are original production-component captures with
synthetic data. See [instructional image provenance](screenshots.md). Their sidecars identify their capture source and time; they
are content assets, not a claim of device sharing, update installation or fresh
packaged-process acceptance. New review captures must use the current source
and be recorded separately under `doc/validation/`.

Revision 3's recommendation UI evidence remains historical at
[extension recommendations](../validation/extension-recommendations/README.md).
Revision 2's packaged-process acceptance remains historical at
[user guide validation](../validation/user-guide/README.md).

Tracking: [#290](https://github.com/PinedaTec-EU/LeonardoMD/issues/290),
[#310](https://github.com/PinedaTec-EU/LeonardoMD/issues/310).

Revision 5 is a reading document with no exercise fields. Chapter 4's fixed
practice link is recognized only in the guide opened through Help/Welcome.
`Practice-v1-en/es.mdlr` provides a separate user-owned form under
`Practice Forms/v1/<locale>/`, opening in Fill mode and retaining saved answers.
The linked web copies are generated at `doc/guide/<locale>/practice.mdlr`.
No system URL protocol or general document-command facility is introduced.
Tracking: [#312](https://github.com/PinedaTec-EU/LeonardoMD/issues/312).

Illustrations use real alpha transparency and the Classic red/oxide/ochre palette. Keep explanatory captions in the localized Markdown rather than baking them into artwork; the four artwork files are shared across locales. Verify transparency and readability on the document background when refreshing them. Tracking: [#375](https://github.com/PinedaTec-EU/LeonardoMD/issues/375).

Guide v73 documents optional grouping of independent processes in Dock and the app switcher, with per-window instance selection and a native application menu. Existing personal copies remain untouched.
