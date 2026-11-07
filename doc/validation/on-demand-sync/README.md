# On-demand synchronization validation

Tracking: [#384](https://github.com/PinedaTec-EU/LeonardoMD/issues/384), [PR #385](https://github.com/PinedaTec-EU/LeonardoMD/pull/385).

## Original checkpoint checks

- Full macOS `swift test`: 704 XCTest checks, 35 opt-in/platform skips, zero failures. Compiler invocation is recorded in PR #385's own ledger entry.
- Final focused checks: catalogue authority, 1,000-file metadata index, LRU eviction, separate retention/cleanup, restart, future folder descendants/child exclusions, image dependencies, stale retained fallback, late-download revocation, empty folders/symlink exclusion, controller interval and bilingual bundled help. Zero failures.
- iOS simulator generic build succeeds with signing disabled. This proves compilation, not physical-device transport, installation or background execution.
- Deterministic user-guide packaging: three Python checks pass. Guide v19 and personal-copy namespace advance together; previous user copies remain untouched.

## Original checkpoint component evidence

`downloads-en.png` and `downloads-es.png` capture the actual shared SwiftUI components using a synthetic project. They show independently accounted temporary/offline bytes, the configurable temporary limit, cleanup, retained-folder management, cached/remote files, complete offline files, a partially retained project, and an interrupted retained folder. The context/metadata files bind original PNG bytes, dimensions, capture time and source. Native viewport: 1180 × 640 points; bitmap: 2360 × 1280 pixels. These are component captures, not packaged-process or physical synchronization acceptance.

Source for the original checkpoint component captures and packaged QA compilation: `278fa8f5df3102c4cf48b932cc8ba9937dbdd9f2`. The original evidence-only commit was mapped to this source. Subsequent source refreshes change product/build inputs and require new acceptance; these captures are historical.

## Original checkpoint packaged native acceptance

The owner's saved instance was closed with explicit permission. The repository's `./launch.sh --qa` built and verified the real executable, dependencies, signatures and helper before launching a fresh process. Final fresh PID: 16394; QA bundle: `eu.pinedatec.LeonardoMD.qa` with the unique suffix recorded by the bundle metadata. Baseline display version: 0.3.1022; this source PR does not materialize or publish a new version.

**Pending:** real preferences interaction, both Help locales, live Mermaid/math/charts/images/tables, Math-disabled fallback and practice open/fill/save/reopen in the final packaged process. Computer Use reported that the Mac was locked and required manual owner unlock. Component/XCTest evidence does not replace this acceptance.

An earlier QA attempt exposed the same stale personal help-copy signature as [#378](https://github.com/PinedaTec-EU/LeonardoMD/issues/378): the bundle contained updated v18 help but an existing personal v18 copy contained older content. That attempt is not accepted help validation. This PR uses unused v19 and must compare the actual Help working copy with the bundle during final acceptance.

No real device pairing, source sharing, helper registration, release publication or proposal acceptance was performed for these fixtures. Source and receiving applications need the new catalogue/file endpoints; older sources do not silently fall back to bulk downloads.

## Refreshed branch (7 November 2026)

The branch incorporates main99ac320 (accepted math/outline fixes and offline demo) and advances its own help to Guide v24. The refreshed source checkpoint is d956445; 19 focused tests, generic iOS simulator build and three guide-packaging checks pass. It adds an actionable source-update error for missing catalogue/file routes, persistent desktop catalogue access after offline restart, and live-preview invalidation when files/images leave the catalogue.

Current full tests, new exact-source captures and the real packaged bilingual Help/preferences smoke are pending the diagnostic #382 GUI slot and any further source refresh. The older figures and images above are retained as historical evidence and must not be used to approve the current head. No helper update, pairing change or live-source compatibility claim has been made.

## Full-suite and retention-removal regression

After including accepted demo materialization (main e9d73cd / 0.3.1057), the full local suite passed 712 XCTest checks, with 36 opt-in/platform skips and zero failures. During the review a separate cache invariant was registered as [#390](https://github.com/PinedaTec-EU/LeonardoMD/issues/390): a stale retained fallback must be discarded if retention is removed, instead of persisting an unreadable temporary-cache record.

The new restart regression failed against the previous implementation with `invalidSnapshot`. After normalizing unretained stale records before LRU eviction, the complete `OnDemandCacheTests` suite passed. That focused run uses no native UI fixtures. Full current-head CI and native acceptance still apply to the corrective commit; the earlier full-suite result is not asserted as a run of that later source. No product app, helper or CUA operation was performed during this CLI turn.

## Cross-project cache indicators

[#391](https://github.com/PinedaTec-EU/LeonardoMD/issues/391) was reproduced before native acceptance: a global LRU eviction correctly removed the first project’s cache record but left its observable downloaded flag true after opening a file in another project. The new regression failed before correction; refreshing every authorized project snapshot after mutations makes it pass. The complete cache suite passes 12 tests after correction. Help already describes downloaded indicators and global temporary limits; no new control or behavior is introduced by this consistency fix. The previously prepared package is superseded and must be rebuilt for final native acceptance.

## Coordinated diagnostic integration and packaged Guide24

The owner confirmed the Mac unlocked. The diagnostic thread completed its own Help checks, restored its settings/practice files and explicitly ceded GUI. Source d8487bc incorporates its frozen product head47581657 while PR382 completes evidence/CI/judgment; PR385 must wait for382 main integration and numeric materialization before merging. Both help bodies include the diagnostic and the on-demand chapter, retaining unused Guide24. Deterministic packaging passes three checks.

A real package built successfully (PR385 compilation delta20), passed canonical executable/dependency/signature verification and launched as fresh PID41918. The package inspection and partial real-process captures are in `packaged-guide24/`. English Help opened through the actual Help menu; diagrams, single/multiline display equations, inline notation, complete underbraces/radicals/arrows/cancellation marks, tag(1), embedded chart, local image and table were inspected. Code examples remain literal. English practice was filled with fictional QA385 English, saved, closed and reopened with the answer intact. Its original bytes and the Spanish original are backed up for restoration after the instance closes. The English Help copy matches bundled SHA256 `a51b4d69d13de9c929e7dc360b9398ab3fb40070167b664fc2b9dbc6bbf61b12`.

The consumer preferences page displayed separate offline storage, temporary budget256MiB and pending counts. Changing to128MiB and clearing the empty temporary cache worked. The ad-hoc QA package correctly reports that its helper signature cannot register the service; no helper, trust pin, device grant or pairing was changed.

**Still pending:** the Mac locked again while reopening cache preferences. The QA instance remains open, the limit is128MiB and needs restoration to256; Spanish Help, Math-disabled fallback, Spanish practice, completed restore/capture acceptance, exact-head CI and strict judge remain outstanding. The second unlock request is centralized in the385 thread. This is partial evidence, never a full native acceptance claim. Native CUA screenshots are original JPEG bytes; metadata explicitly uses measured screenshot pixels as the viewport equivalent because CUA exposes no CSS/native-point dimensions.

### Joint-source CLI follow-up

The complete local suite on the joint product source d8487bc passed719 XCTest checks (36 skips, zero failures), plus28 Swift Testing checks. Generic iOS Simulator compilation also succeeded; neither result claims a physical iOS run, installation or transport acceptance. Successful invocations are recorded in the385 ledger through delta22. Post-d848 commits contain evidence and ledger updates only; no application/build source changed. The blocked native checks and pending restoration above remain open.

## Accepted Classic integration (7 November)

The branch reconciles accepted Classic PR387 (`6e9f40a5fe94ae76b316023b3a8983a6dc35da5c`),
including startup fix393: the local library becomes ready before awaiting network
rubric recovery. Its About screen, rotating rubric canvas and Classic styling
remain. The shared catalogue accepts presentation row colour and the shared
remote preview accepts the existing renderer appearance so iOS selects Classic
without changing macOS defaults or duplicating the cache/retention flow.

Guide26 combines the accepted Guide25 with on-demand synchronization guidance,
LL1 diagnostics and the offline demo. Guide26 had no existing personal-copy
directory at allocation. Combining the old conceptual cache PNG with Classic's
illustration exceeded the existing128MiB conservative image envelope. The cache
explanation now uses an accessible bilingual table; the old illustrative PNGs
are retained under `cache-diagrams/` as historical evidence. No image budget was
raised. Existing packaged images and supported live examples remain.

Deterministic guide checks3/3, cache tests12/12 and focused native guide tests5/5
pass. The full local suite passes719 XCTest checks (36 opt-in/platform skips, zero failures) plus28 Swift Testing checks. Generic iOS Simulator compilation also passes. Fresh packaged native/Help acceptance and independent exact-head review remain pending for this combined candidate.
Physical connection work392 is a separately frozen runtime experiment, not a
claimed fix or a prerequisite for Classic publication.

A real package was subsequently built from published `b24087574b32eadb1c14f55d9a467dc1507d340f` on baseline0.3.1113. Canonical release-note identity/dependency/signature inspection passes. A separate QA bundle is prepared and passes executable/dependency/signature checks; removing signatures from scratch copies confirms equal executable payloads (the distinct QA identity necessarily changes embedded signature bytes). The canonical release-identity report applies only to the canonical bundle; it must not be requested for a deliberately different QA identity. Neither385 bundle has been launched. Native acceptance waits for the diagnostic thread to release its physical-test GUI lease.


## Combined Guide26 native acceptance

This section supersedes earlier pending native checkpoints. A fresh QA process
53729 ran the real packaged executable from `b24087574b32eadb1c14f55d9a467dc1507d340f`,
baseline0.3.1113, with unique identity
`eu.pinedatec.LeonardoMD.qa.436aa7936fa24284949752f547efc6a1`.
The handoff and package inspection above bind the canonical/QA build.
Later commits add evidence and compilation ledger only, with no app/build-input changes.

Actual Help menus opened Guide26 EN/ES in that same process. Both locales passed
Mermaid, inline and single/multiline display math, Markdown-sensitive underbraces,
radicals, tagged equation(1), charts, local images, tables and literal code.
Math-disabled fallback was inspected separately in both languages. Both separate
practice forms were filled with fictional QA names, saved, closed and reopened;
the answers persisted. Both new cache chapters were inspected. Personal Help
copies match bundled bytes: EN SHA256
`100515756813b363209241392d42db3e930c3c1c3c70acf7d5e7f4cd1359f01e`,
ES SHA256 `e86cf6fc34b70e25fa7936fff95a180dd2e0479c7963b94026d596db3f58657e`.

Preferences showed independent temporary/offline usage and pending counters.
Changing temporary budget256→128MiB and clearing the empty temporary cache
worked;256MiB was restored. Populated retention/catalogue states are covered by
shared production-component fixtures and cache tests, not this empty native cache.
The ad-hoc QA helper signature cannot register the service, as expected; no service
registration, pairing, grant, trust pin, source corpus or external helper changed.
The signed physical-test helper26651 remained under the diagnostic chat's control.

The QA process quit normally. All three scoped originals (preferences and both
practice forms) were restored with exact SHA256 verification. English and Math ON
were restored before quitting. Original unmodified CUA JPEGs and canonical sidecars
are in `classic-native-guide26/`. CUA exposes no native-point/CSS viewport or engine
version; the context explicitly records screenshot-pixel equivalent dimensions and
unavailable version rather than fabricating them. Captures show packaged UI/help;
they do not claim physical iPhone transport acceptance or beta publication.

Fresh shared production-component captures in `classic-components/` were generated from c1fac112ab0f78f1c8307569b54c76524e22b02c with the existing DownloadViewsCaptureTests fixture (1/1 PASS, recorded delta27). Both locales show remote, cached, retained and pending/error states, independent usage, cleanup and the retention list. Native viewport1180×640points; bitmap2360×1280pixels. These are synthetic component captures, not a running product or physical-device acceptance. Application/build inputs are unchanged from b240875.


## Post-review revocation correction

[#395](https://github.com/PinedaTec-EU/LeonardoMD/issues/395) records a late-return
race within #384's existing authorization criterion. Two deterministic tests
suspend the real persistence boundary during final usage refresh and stale
fallback read, remove authorization/cache, then release completion. Both failed
before correction by returning bytes. The shared client now rechecks the captured
authorization generation and cancellation at every asynchronous delivery path,
including shared task results. Superseded usage replies cannot overwrite newer
post-revocation accounting. The RemoteDownloadCache port keeps scheduling doubles
in tests and the real atomic persistence unchanged. The focused cache/revocation
suite passes14 tests after correction. The complete local suite passes722 XCTest
checks (37 opt-in/platform skips, zero failures), plus28 Swift Testing checks.
Current-source native captures are being finalized. Earlier b240875 packaged acceptance is historical for this
corrective source and must not be reused as its fresh-process acceptance.

The iOS acceptance harness uses the real Little Leonardo interface and a separate
opt-in pinned loopback source on127.0.0.1:46987, with synthetic files/identity/grants.
OnDemandSyncUITests exercises metadata-only enrollment, one-file reading, native
context retention, independent128MiB cache controls/cleanup, a pending response,
automatic retry and a future retained-folder descendant. The source fixture
records body-request counts and requires no aggregate snapshot or unrequested
file transfer. The accepted Classic simulator926C886F-52D8-4766-B84D-1A5D8C218080
was explicitly ceded with disposable synthetic state. Physical-test helper26651,
source corpus, grants and trust remain outside this fixture. Runtime capture
results are pending; code alone is not claimed as iOS acceptance.


The first iOS test attempt used CODE_SIGNING_ALLOWED=NO (compilation-only setup).
HTTPS pairing reached the synthetic server, but the app did not persist its
connection and no catalogue/file request followed. The test failed and is not
accepted. The accepted Classic runtime recipe uses local ad-hoc signing enabled
and Xcode's generated application-identifier entitlement; that existing path is
being applied to this fixture. No distribution profile or manual Keychain group
is introduced, and this simulator setup observation does not explain #380.


## Native budget-edit regression and Guide27

The signed iOS run reached all flow stages but was **not accepted**: replacing
256 with128 read back256.128, recorded in [#396](https://github.com/PinedaTec-EU/LeonardoMD/issues/396).
Original real-app screenshot/context/metadata are retained in `cache-limit-before/`.
Its isolated source audit observed two catalogues, no aggregate snapshot, one
requested reference file, one retained agenda, two decisions attempts and one
future retained descendant; the other remote file was not requested. That is
historical diagnostic evidence, not new-source runtime acceptance.

The cache field now edits a separate plain-text draft with a persistent MiB
label. Apply/Return commits a validated integer once; background usage updates
cannot rewrite active input. Native acceptance tests both Apply and Return,
including replacement64→128, before the catalogue flow. Bilingual Guide27
explains the explicit action; its personal-copy namespace was absent at allocation.
Guide26 personal documents are preserved. Deterministic packages pass3/3 and the
complete local corrected suite passes722 XCTest checks (37 skips, zero failures)
plus28 Swift Testing checks. Fresh native iOS/macOS capture acceptance is pending.


## Reauthorization isolation

A third deterministic #395 regression holds completion of an actual store,
removes the grant/cache, grants the same project again and opens a new revision.
Before correction the new open joined the obsolete task and the old completion
purged the newly authorized project (the test failed with revoked and a missing
cache project). Active tasks now carry their authorization generation; old
cleanup cannot remove a newer task/progress indicator, and only the host owns
revocation purge. Obsolete completions cannot purge a later grant.
All15 focused cache/revocation tests pass. Full corrected local validation passes
723 XCTest checks (37 opt-in/platform skips, zero failures), plus28 Swift Testing
checks. Current-source iOS/macOS native evidence and exact-head review remain
pending; earlier capture attempts are not acceptance of this corrective code.


## Final source native iOS acceptance (2026-11-07)

The current product source is `66c9e644a3203e1725f466973e1940acff61e61f`.
Subsequent evidence/compilation-ledger commits do not alter product/build inputs.
The locally signed Simulator app reports version0.3.1113/build1113 in About;
this is a test candidate, not a distributed release. Simulator926C886F-52D8-4766-B84D-1A5D8C218080
runs iPhone18Pro/iOS27.0 at402×874 points (original PNG1206×2622).

The versioned native About/Help/privacy/licenses test passes1/1. The combined
bilingual demo tests and complete on-demand UI test pass3/3. The real pinned
source fixture also passes. The cache field passes Apply128, Return64 and
Return128 before synchronization. The source audits prove catalogue-only enrollment,
exactly one requested reference-file read, zero aggregate snapshots, contextual
file/folder retention, preserved offline bytes after temporary cleanup, and
automatic recovery including a newly added descendant. Final state contains
three retained files (166bytes), zero temporary files and a134217728-byte budget.
The untouched remote reference file is never requested.

Primary original captures, source contexts and canonical metadata are in
`final-ios/`; `final-ios-help/` retains actual XCTest About, Help and bilingual
practice/gallery attachments. `accepted-source-ios/` is an earlier functional
pass whose Debug package omitted CFBundle version keys; it is historical and
superseded by the explicitly versioned repetition. `accepted-source-components/`
contains current-source macOS production-component renders, not packaged-app Help acceptance.

Runtime results: `/tmp/leonardo385-versioned-about.xcresult` and
`/tmp/leonardo385-versioned-ios-flow.xcresult`; source fixture log
`/tmp/leonardo385-versioned-ios-fixture.log`. Reproduction uses the existing
OnDemandMobileAcceptanceFixtureTests and OnDemandSyncUITests with the owned
LEONARDO_ON_DEMAND_QA_ROOT, loopback46987 and source SHA. Build-for-testing uses
local ad-hoc signing (CODE_SIGNING_ALLOWED=YES, CODE_SIGN_IDENTITY=-), canonical
MARKETING_VERSION=0.3.1113 and CURRENT_PROJECT_VERSION=1113; runtime uses
test-without-building. No physical-device acceptance is inferred.

The real macOS QA bundle was built from the same source, checked for proper
executable/dependencies and launched as fresh PID35533. Its identity and hashes
are in `final-native-handoff.json` and `final-package-inspection.json`. The Mac
locked before first-window inspection. **Current packaged macOS Guide27 EN/ES
acceptance remains pending**, including live math/extensions and practice round-trip;
process existence and component captures do not substitute for it. The physical
#380 retry remains owned by the diagnostic chat. No merge or beta publication is claimed.


## Completed packaged macOS acceptance (2026-11-07 evening)

The preserved real QA executable was relaunched after the physical rubric test
ceded GUI ownership. The new process displayed its first window and opened both
Guide27 locales through the actual Help menu. `final-macos/` contains original
CUA screenshots, capture-time contexts and canonical metadata. The build source
remains66c9e644a3203e1725f466973e1940acff61e61f; subsequent commits only record
validation/accounting. The window reports0.3.1113/build1113, unique QA identity
as recorded in final-native-handoff.json. Native point dimensions/engine version
were not exposed; metadata explicitly uses image-pixel equivalent dimensions.

Both EN/ES live examples were inspected: Mermaid, inline and single/multiline
display math, complete underbrace/radical/arrow shapes, tagged box-counting
formula(1), Vega-Lite chart, packaged local images and tables. Math-off fallback
was checked after declining the activation recommendation, and literal code
examples stayed literal. The separate practice form in each locale was opened,
filled with fictional answers, saved, closed and reopened; the actual fields
retained their values and checkbox. Bundle/personal Guide27 SHA-256 hashes match
in both locales (identity-and-restoration.json). No existing guide was overwritten.

Actual Mac cache preferences accepted128MiB with Apply and256MiB with Return,
restoring the original budget. This ad-hoc QA identity correctly cannot authenticate
to the signed physical helper; no sharing/enrollment/helper action was attempted.
The tested editor quit normally, the latest preferences and two practice originals
were restored byte-for-byte, and helper26651 remained running unchanged. These
checks supersede the earlier locked-Mac pending note, not the separate #394 fix.
The physical #380 image/rubric round-trip is recorded by the diagnostic chat;
PR398 separately fixes the manual status-query recovery observed there.
