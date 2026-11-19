# Bundled user guide

The macOS app ships `Guide-v100-en.mdlz` and `Guide-v100-es.mdlz`. Help and Welcome
open a user-owned copy in
`~/Library/Application Support/LeonardoMD/User Guides/v100/<language>/` through
normal document tabs in package mode. Ordinary package-opening preferences
remain unchanged. Existing guide copies and practice answers are never overwritten.

Guide v100 includes the historical release notes guidance from v99 and carries forward visible selection counts and checkmarks for mixed multi-selection,
and carries forward v96's same-target move no-ops and destination collision behavior,
v95's project-tree multi-selection, and v94's drag/drop guidance. Existing personal
copies and practice answers through v99 remain untouched. Revisions v97, v98, and
v99 already exist in the task account with different contents from this candidate;
v100 is the first unused personal-copy directory. Fresh packaged Help acceptance
for v100 is pending in a task-owned QA app `0.3.1884 stable`.
Earlier packaged Help acceptance for v96 passed in task-owned QA app `0.3.1884 stable`
(build ledger entry 12, PID 9666). Help → Leonardo user guide opened both v96 locales.
Mermaid, Math, Charts, local images, and tables rendered. With Math enabled, inline
notation and one-line/multiline equations—including underbraces and the tagged
box-counting equation `(1)`—rendered without KaTeX errors or raw display delimiters.
With Math disabled, source notation and `\tag{1}` stayed literal; the inline-code
formula example also stayed literal. The English practice form was filled with
synthetic values, saved, closed, reopened, and verified; its prior values were
restored. Math and the original English interface preference were restored. The app
quit normally and PID 9666 was confirmed exited. Manual project-row move/copy drop
acceptance remains unverified. Tracking: [issue #261](https://github.com/PinedaTec-EU/LeonardoMD/issues/261).
Guide v96 EN SHA-256: `722e956dc62552995ebdb4b05e69c91e0bc2f5dfa96c667274d496bfaabf4e87`
and ES SHA-256: `c0be641188e7ec9da86559bd5baf8891f953318bddbf0f67f5f2b4adad64c2a5`.
Guide v97 EN SHA-256: `a1eed2094f9ff3c0f8b42577976498fa439c89a40eb274f40b6b730c7c364105`
and ES SHA-256: `97a170c53555657fde2820c8abce4d5ab7c6b7b191d18e65aa65ee0a45d83448`.
These hashes describe superseded candidates; those revision directories already held
different personal guides. The v100 candidate hashes are recorded after packaging.
Guide v98 EN SHA-256: `e1a0496cda013821d04a9dffbf9b417a58de816f0ed0e2252da4fbcc6c1f0a2e`
and ES SHA-256: `60dd50195ea44fd85f469c96cc576667bd3f9090c3e5196f5e1359bf79d11de7`.
Guide v100 EN SHA-256: `7114204a9969fb418409fe4b9950b0579b15b23594a075ed46174c9f234e0d15`
and ES SHA-256: `90fbb14f002625cc207dae05fbf1084edacb8efc4e92034d99dbee77d494bbec`.
Guide v95 EN SHA-256: `4b96b84bc89f83fd3347e6ccb6e621e21e8d3b73abfbe54c7ccedc5f30e65848`
and ES SHA-256: `cdfbe9adbe90ef95402636c6171243cd25643fb48feada5de3a6e7136b6fb0df`.
Guide v94 EN SHA-256: `151bda467f3bdf81965d2f961ed31031eba5b9a1b0d59be32785e927f47dbb4e`
and ES SHA-256: `10259c7f5a7c64f4a738704e398481d7965b738c3fb25a95f6742bd4110cb8fb`.

Guide v93 EN SHA-256: `619699672c50a5295b7f6a968f9952a86b9d4f2cfd0389c322e4ec081e9a494c`
and ES SHA-256: `ea512ab338ad8f269fdd650f29d8520e0a8378baa96309f2151abf1b79a9e519`.

Guide v87 previously passed packaged Help acceptance in a fresh macOS QA
process. The bundle/opened-copy hashes, rendered examples, Math fallback,
practice-form round trips and teardown are recorded in
[packaged-help-v87-qa-20261116-pr435.json](../validation/little-leonardo/packaged-help-v87-qa-20261116-pr435.json).
That acceptance does not cover the superseded Guide v93 package; its Help/practice
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
historical review record. The current app resources use Guide v100 with a new
resource name and personal-copy directory; no existing guide copy is overwritten.

Guide v86 is historical. Its fresh packaged Help acceptance passed against
source `47858f19e1c612a6e5beba34d76f0fa9ff7c6054`; the candidate-specific
record is in
[packaged-help-v86-20261116.json](../validation/little-leonardo/packaged-help-v86-20261116.json).
It does not establish acceptance for the current Guide v100 package. The
previous iOS capture bundles are historical; refreshed simulator evidence is
recorded separately under `doc/validation/`.

`en/body.md` and `es/body.md` are the editorial sources. The 19 chapters cover
macOS workflows and Little Leonardo's host → project → file library, with live Mermaid/KaTeX/Vega examples, literal citation
and Markdown-extras examples, a separate practice form, generated diagrams, the
approved About banner and original localized UI screenshots. See the
[source-backed feature inventory](feature-coverage.md).

Guide v93 introduced the current document-search, remote-project review and offline-catalogue guidance, grouped Dock/app-switcher instances, synchronization status and helper recovery. Guide v94 carried that guidance forward alongside project-tree drag/drop instructions; Guide v95 adds mixed multi-selection. Guide v96 clarifies same-target move no-ops and destination collision behavior. Guide v97 adds a visible count and row marks for multi-selection. Guide v100 carries that behavior forward under an unused personal-copy directory. Existing guide copies and their separate practice answers remain preserved.

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
