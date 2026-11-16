# Bundled user guide

The macOS app ships `Guide-v88-en.mdlz` and `Guide-v88-es.mdlz`. Help and Welcome
open a user-owned copy in
`~/Library/Application Support/LeonardoMD/User Guides/v88/<language>/` through
normal document tabs in package mode. Ordinary package-opening preferences
remain unchanged. Existing guide copies and practice answers are never overwritten.

Guide v88 shows the different messages and recovery paths for a known HTTP
rejection of a mobile rubric response and a connection loss without an
acknowledgement. Existing v87 and older personal copies and practice answers
remain untouched. Fresh bilingual packaged Help acceptance is tracked in
`doc/validation/little-leonardo/` for PR #435.

Guide v87 previously passed packaged Help acceptance in a fresh macOS QA
process. The bundle/opened-copy hashes, rendered examples, Math fallback,
practice-form round trips and teardown are recorded in
[packaged-help-v87-qa-20261116-pr435.json](../validation/little-leonardo/packaged-help-v87-qa-20261116-pr435.json).
That acceptance does not cover the new Guide v88 package; its Help/practice
acceptance remains pending for the owner-authorized Beta validation.

The terminal-retry screenshots and result bundle were captured from product
and test source `5e751df2` before integrating the follow-up #459/#460 evidence
commits. The current simulator fixture also includes the #460 host-environment
correction. Guide v87 EN has
SHA-256 `ae96797ee8db8799e66060bde6f731a436bef446e6f278ca20c0714b64baf33f`
and ES has SHA-256
`487560caac7f729445cbb32b3bb3b8c67e154169bc001c2f7144c1e55541be09`.

Guide v88 EN and ES hashes and the exact test/source manifest are recorded in
`doc/validation/little-leonardo/rubric-explicit-rejection-20261116/`.

Guide v86 is historical. Its fresh packaged Help acceptance passed against
source `47858f19e1c612a6e5beba34d76f0fa9ff7c6054`; the candidate-specific
record is in
[packaged-help-v86-20261116.json](../validation/little-leonardo/packaged-help-v86-20261116.json).
It does not establish acceptance for the current Guide v88 package. The
previous iOS capture bundles are historical; refreshed simulator evidence is
recorded separately under `doc/validation/`.

`en/body.md` and `es/body.md` are the editorial sources. The 19 chapters cover
macOS workflows and Little Leonardo's host → project → file library, with live Mermaid/KaTeX/Vega examples, literal citation
and Markdown-extras examples, a separate practice form, generated diagrams, the
approved About banner and original localized UI screenshots. See the
[source-backed feature inventory](feature-coverage.md).

Guide v74 combines current document search and remote project workflows with the latest synchronization status and helper-recovery guidance, plus optional grouped-instance instructions. Its distinct revision ensures installations with a saved v68, v71, v72 or v73 guide receive this content while preserving earlier guide copies and their separate practice answers; opening Help never replaces a saved copy.

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

Guide v74 documents optional grouping of independent processes in Dock and the app switcher, with per-window instance selection and a native application menu. Existing personal copies remain untouched.

Guide v86 clarifies that invalid or expired scanned pairing QR codes have a
short alert with a reference code and a matching entry in the local log. Its
English route labels match the app's accessible settings and log labels. It
retains the diagnostic log limits, cache location, backup exclusion and iOS
cache-purge guidance. Earlier personal guide copies and practice answers remain
untouched.
