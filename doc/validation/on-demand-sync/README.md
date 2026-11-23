## Joint Mac/iOS acceptance — primary evidence

The current evidence is `joint-macos/`, `joint-ios/`, `joint-ios-help/`,
`joint-reader-spacing/`, `joint-preview-components/` and `joint-build-inputs.json`.
All older directories and checkpoints below are historical.

Product source25723d6587d902477edffbf2f3b66c94f5e6def3 includes accepted main1147
and the common on-demand iOS reader with compact first-heading spacing and
explicit source/document controls. Mac745 XCTest (38 skips),72 Swift Testing,
signed iOS build, spacing3/3, native on-demand1/1, independent pinned-TLS source
fixture1/1 and native bilingual demos/Help/About3/3 pass. The test-only ff20ce0
capture wait change passes both real-cache preview integration tests and retains
readable original pixels. Failed intermediate captures are not primary evidence.

Fresh packaged Mac QA PID77534 (baseline0.3.1147/build1147, Guide33) completed
actual EN/ES Help, Mermaid, inline/one-line/multiline mathematics, underbraces,
radicals/arrows/cancellation, tagged box-count equation, literal code, Math OFF
fallback, charts, local images and tables. Both separate practice forms were
filled with fictional values, saved, closed and reopened. Working guide hashes
match bundled originals. The process quit normally; all three owner originals
were restored byte-for-byte and physical helper67032 remained running.
See `joint-macos/validation.json` for hashes and restoration proof.

Native iOS audits show metadata-only initial browsing, a single requested body,
source/document switching without another fetch, folder retention with automatic
retry and future descendants, and clearing temporary cache preserving three
retained files166bytes outside the134217728-byte temporary budget. The common
reader has measured first-heading spacing16px with later headings spaced.
Captures preserve actual timestamps/source SHA; scoped Git object digests bind
unchanged build inputs to the final reviewed head. These simulator checks do not
claim a physical iPhone acceptance or an already published cache-enabled beta.
Exact-final-head hosted CI, independent review and publication are delivery gates.

# On-demand synchronization validation

Tracking: [#384](https://github.com/PinedaTec-EU/LeonardoMD/issues/384), [PR #385](https://github.com/PinedaTec-EU/LeonardoMD/pull/385).

## Current corrective checkpoint: final joint validation pending

The latest code additionally isolates transfers by exact catalogue entry and
transfer UUID. A new revision must not join an obsolete download or inherit its
progress cleanup/error. The real-cache controlled-fetch regression for
[#402](https://github.com/PinedaTec-EU/LeonardoMD/issues/402) fails four assertions
before correction and passes afterward with the existing cache/revocation tests.

Hosted CI exposed [#406](https://github.com/PinedaTec-EU/LeonardoMD/issues/406):
NSView bitmap OCR did not include WebKit's composited content on macos-15.
The real production-preview integration now checks actual WebKit DOM readiness
and visible heading geometry separately, while native OCR still requires the
warning and Retry. Author-owned visual captures must additionally include the
readable content pixels; blank/loading output is never acceptance evidence.
The corrected focused checks pass locally; current-head CI is pending.

The agreed integration order is405/397 first, then385 reconciled onto its
accepted main. The shared on-demand iOS preview must opt into405's compact
first-heading configuration so switching readers does not restore the old gap.
Final source-bound Mac/iOS/Help evidence and full checks will be repeated after
that reconciliation. All Guide32 evidence below is a bounded earlier checkpoint,
not acceptance of the later transfer correction or joint spacing integration.

## Earlier retained-preview correction and Guide32 acceptance (historical)

Product source `4da0d9aba33c7a95256b96311c04c66fb63efdb9` incorporates accepted
main0.3.1136. The failed-update result explicitly carries a retained copy and
its original failure. The production preview displays a previous-copy warning,
error and Retry above readable content, including failed referenced images.
Two native integration checks exercise the actual preview task, download library
and disk cache; both EN/ES old-copy states and the readable-image-error state
pass. `retained-preview-components/` contains inspected originals. Test-only
`72a9e2e4bf2dc7af1c6536fc6a5f7510083b83e1` waits for WKWebView content before
accepting the image-error capture; an earlier blank/loading capture was rejected
and is not review evidence.

Full validation on unchanged product inputs passes744 XCTest checks (38 skips,
zero failures) plus71 Swift Testing checks. The strengthened integration checks
pass2/2 afterward. Bilingual deterministic guide packaging passes3/3. The PR385
compilation ledger records successful invocations through delta61.

`guide32-macos/` records a fresh real packaged QA process52183, baseline numeric
version0.3.1136/build1136, ad-hoc QA identity. Both Guide32 locales opened through
the actual Help menu. Mermaid, inline/one-line/multiline Math, underscores and
underbraces, radicals/arrows/cancellation, box-counting equation tag(1), chart,
local images, table, Math OFF fallback and literal code passed. Both separate
practice forms were filled with fictional values, checkboxON, saved, closed
and reopened. Real Preferences Apply128MiB and Return256MiB passed; final disk
readback is268435456bytes. Both personal guide hashes equal the bundled guides.
`validation.json` records those identities and exact restoration of the three
latest original preferences/practice files after normal quit. Physical helper
67032 stayed unchanged. The ad-hoc QA helper is intentionally unavailable;
these checks do not claim a new physical-device connection test.

Signed iOS native acceptance on dedicated simulator926C886F passes4/4
(on-demand1/1, bilingual demo/practice and About/help3/3). The independent pinned
HTTPS source fixture passes1/1. `guide32-ios/` contains8 original native flow
captures, source audits and disk readback: zero bulk snapshots, only requested
or retained bodies, automatic retry and future descendants, three retained
files166bytes outside the134217728-byte temporary budget. `guide32-ios-help/`
contains6 original demo/practice/About/help captures. Earlier preview-* and
corrected-* directories below are historical for changed product inputs.

`guide32-build-inputs.json` lists complete Git objects and digests for the Mac
app/build inputs, iOS app/test driver and production preview/test driver. Compare
each group's `git ls-tree -r HEAD -- <input_scopes>` with its recorded revision
and digest. This is the shared evidence-only mapping contract: originals retain
their real source and timestamps. No application/build input changed after its
respective captured revision. The full-suite checkpoint and subsequent stronger
test-only check are distinguished explicitly.

To reproduce the warning component, run the recorder with source PR385 and
`swift test --filter RemoteDocumentPreviewIntegrationTests`; set
`LEONARDO_PREVIEW_EVIDENCE` to an owned output directory and `EVIDENCE_SHA` to
the checked-out source revision to retain original captures. Native Mac acceptance
uses `LEONARDO_SOURCE_PR=385 ./launch.sh --qa`, with normal saved-instance
handoff and the repository's real bilingual Help smoke workflow. The iOS flow
uses `OnDemandMobileAcceptanceFixtureTests` with its explicitly owned fixture
marker, then `OnDemandSyncUITests` against simulator926C886F/port46987; the fixture
and tests enforce the metadata-only/single-file/retry/cleanup audits. Do not
reuse the diagnostic helper or real user documents as fixtures.

Current-head CI, strict fresh judge, integration and beta publication remain
separate delivery gates; no385 beta or new physical iPhone acceptance is claimed
by these pre-merge checks.

## Earlier preview-revision acceptance (historical)

[#402](https://github.com/PinedaTec-EU/LeonardoMD/issues/402) fixes a separate presentation boundary: remote text/images/errors are keyed by project, path, catalogue and per-load generation. Four deterministic tests cover immediate revision invalidation, failed replacement, obsolete same-catalogue completions and cross-document/project isolation. The complete suite passes729 XCTest checks (37 skips,zero failures) plus28 Swift Testing checks. Current signed iOS native acceptance passes4/4 (bilingual demos, on-demand and populated-cache About/Help) with independent source fixture1/1. Original screenshots/contexts/metadata, source audits and cache readback are in `preview-ios/` and `preview-ios-help/`; `preview-components/` contains fresh production-component renders1/1. `preview-build-inputs.json` records scoped Git object/digest mapping for application and test-driver inputs. The source harness initially refused an unmarked temporary root; the explicit owned fixture marker was initialized before enrollment, and the final source audit passes. Actual macOS native acceptance completed8 November in fresh process53146 (real QA source861f579,version0.3.1113/build1113). Both Guide27 locales opened through Help; live Mermaid, inline and one-line/multiline Math, Markdown-sensitive TeX/underbraces, radicals/arrows/cancellation and tagged equation(1), chart, local image and table passed. Math OFF fallback and literal code passed in both locales. Both separate practices were filled with fictional values and checkboxON, saved, closed and reopened. Actual Mac budget Apply128/Return256 passed. New inspectable original screenshots are in `preview-macos/`; each is visually inspected with its original dimensions rather than accepting thumbnail/clipped capture output. The real editor quit normally, both personal/bundle guide hashes match and all three latest original preferences/practice files were restored exactly. Physical helper26651 remains unchanged; the earlier corrected-* images are historical for these changed application inputs. The English Math-disabled corrected-macos image was clipped and is not accepted visual proof.

## Earlier corrected acceptance (historical)

The primary evidence is now `corrected-macos/`, `corrected-components/`,
`corrected-ios/` and `corrected-ios-help/`. All earlier sections/directories are
historical checkpoints. Product correction a7759b2db562d2fea04c8e7d7b6c9c4997137a26
clears revoked-project task/progress/error state immediately. Two deterministic
regressions fail before correction and pass afterward: cached regrant while an
obsolete store completion remains suspended, and project-scoped error removal.
Focused validation passes17/17; full validation passes725 XCTest checks with37
opt-in/platform skips, zero failures, plus28 Swift Testing checks.

The real corrected Mac QA package launched fresh PID74063 and completed actual
Guide27 EN/ES Help, supported live examples, Math ON/OFF, literal code, practice
fill/save/close/reopen and Apply128/Return256 cache controls. Personal and bundled
guide hashes match. The editor quit normally; all three latest owner originals
were restored byte-for-byte, leaving physical helper26651 unchanged.

Signed iOS native acceptance passes About/Help1/1 on populated cache state, then
bilingual demos and on-demand3/3 with independent pinned source fixture1/1.
Test-only5284cab69df3e59453a52d800e8066486939b722 fixes the About smoke's lazy
settings navigation ([#401](https://github.com/PinedaTec-EU/LeonardoMD/issues/401)).
The earlier combined attempt failed that harness navigation and is not accepted.
Current audits show zero bulk snapshots, only explicitly requested/retained
bodies, automatic retry/future descendants, and temporary cleanup preserving
three offline files166bytes outside the134217728-byte temporary budget.

`corrected-build-inputs.json` records exact Git object lists/digests for Mac app,
iOS app and iOS test driver. Compare each group's `git ls-tree -r HEAD --` input
scopes with its recorded build revision. The final evidence-only head has the
same objects: captured revision/timestamps remain truthful instead of relabeling
originals. The About/navigation driver changed without changing either app.
The canonical PR comment binds this proof to the reviewed immutable head.
Physical no-manual-Retry validation of the later combined385→392→398 candidate
and beta publication remain separate delivery gates.

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
