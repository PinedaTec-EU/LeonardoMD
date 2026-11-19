# Bundled user guide

The macOS app ships `Guide-v102-en.mdlz` and `Guide-v102-es.mdlz`. Help and Welcome
open a user-owned copy in
`~/Library/Application Support/LeonardoMD/User Guides/v102/<language>/` through
normal document tabs in package mode. Ordinary package-opening preferences
remain unchanged. Existing guide copies and practice answers are never overwritten.

Guide v102 adds the project file deletion shortcut to chapter 11. The v99 evidence below applies to that earlier revision.

Guide v99 carries forward Guide v92's HTTP rejection, uncertain-delivery and
remote-project recovery guidance, along with Little Leonardo host aliases,
connection-detail addresses and project-count boundaries. Chapter 10 adds the
Preview synchronization retry warning and close-time recovery choices. Existing
personal guide copies and practice answers through v92 remain untouched. Fresh
packaged Help and practice-form acceptance for v99 remains pending under
[issue #447](https://github.com/PinedaTec-EU/LeonardoMD/issues/447) until the
authorized Beta validation is complete.
Guide v99 EN SHA-256: `619699672c50a5295b7f6a968f9952a86b9d4f2cfd0389c322e4ec081e9a494c`
and ES SHA-256: `ea512ab338ad8f269fdd650f29d8520e0a8378baa96309f2151abf1b79a9e519`.

Guide v87 previously passed packaged Help acceptance in a fresh macOS QA
process. The bundle/opened-copy hashes, rendered examples, Math fallback,
practice-form round trips and teardown are recorded in
[packaged-help-v87-qa-20261116-pr435.json](../validation/little-leonardo/packaged-help-v87-qa-20261116-pr435.json).
That acceptance does not cover the Guide v99 package; its Help/practice
acceptance remains pending under PR #448.

The terminal-retry screenshots and result bundle were captured from product
and test source `5e751df2` before integrating the follow-up #459/#460 evidence
commits. The current simulator fixture also includes the #460 host-environment
correction. Guide v87 EN has
SHA-256 `ae96797ee8db8799e66060bde6f731a436bef446e6f278ca20c0714b64baf33f`
and ES has SHA-256
`487560caac7f729445cbb32b3bb3b8c67e154169bc001c2f7144c1e55541be09`.

Guide v88 EN and ES hashes and the exact test/source manifest are recorded in
`doc/validation/little-leonardo/rubric-explicit-rejection-20261116/`.

The former PR #369 Guide v89 EN and ES package hashes are retained in the
historical review record. Guide v99 used with a new
resource name and personal-copy directory; no existing guide copy is overwritten.

Guide v86 is historical. Its fresh packaged Help acceptance passed against
source `47858f19e1c612a6e5beba34d76f0fa9ff7c6054`; the candidate-specific
record is in
[packaged-help-v86-20261116.json](../validation/little-leonardo/packaged-help-v86-20261116.json).
It does not establish acceptance for the Guide v99 package. The
previous iOS capture bundles are historical; refreshed simulator evidence is
recorded separately under `doc/validation/`.

`en/body.md` and `es/body.md` are the editorial sources. The 19 chapters cover
macOS workflows and Little Leonardo's host → project → file library, with live Mermaid/KaTeX/Vega examples, literal citation
and Markdown-extras examples, a separate practice form, generated diagrams, the
approved About banner and original localized UI screenshots. See the
[source-backed feature inventory](feature-coverage.md).

Guide v99 carries forward current document search, remote-project review and offline-catalogue guidance with grouped Dock/app-switcher instances, synchronization status and helper recovery. It explains project download failures and transfer limits, distinguishes removed project grants from revoked devices with the correct recovery steps, clarifies that explicit access denials cannot open older cached content, and documents reference-coded sync and invalid or expired scanned-invitation errors. On macOS it explains how project-level authorization changes hide editable copies while preserving local work, and how to recover when Preview edits cannot be synchronized during tab, window or app closing. Temporary connection failures may still offer a retained offline copy. Its English route labels match the app. Existing guide copies and their separate practice answers remain preserved.

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

Guide v90 preserves the combined project-download, authorization, offline-recovery
and sync guidance from v87 while carrying forward the latest localized QR/error
messages, reference codes and local-log route. It also avoids raw math delimiters
in explanatory prose. The log remains bounded, local-only and excluded from
backups. Existing personal guide copies and practice answers remain untouched.
