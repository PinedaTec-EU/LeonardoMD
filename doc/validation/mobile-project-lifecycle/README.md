# Mobile project lifecycle validation

> Current candidate after main integration: `de24b150fd3cb97ad40986d3945875e58a04791c`, Guide v36. The historical native-v35 evidence below does not establish current packaged acceptance. See the latest reconciliation section at the end.

Tracking: [#407](https://github.com/PinedaTec-EU/LeonardoMD/issues/407), [PR #408](https://github.com/PinedaTec-EU/LeonardoMD/pull/408).

## Behavior

One name-sorted project list includes the explicitly local Demo project. Its language files open within the project. Every row uses a trailing swipe action with full-swipe deletion disabled. Device-local removal intent is written atomically before corpus removal; reload and synchronization exclude removed IDs. Mac originals are unaffected. Settings restores Demo without resetting current-revision answers. Only a strictly newer `MobileDemoStore.contentRevision` restores it automatically; that same revision selects the personal-copy directory.

## Historical validation before the review correction

- iPhone 17 Pro, owned simulator `1A969A0F-D7E2-4C62-B288-CC893C3CBEEF`, iOS 27.0 (24A434), Classic light, synthetic demo/practice data.
- Expanded iOS run: 19 passed, no failures, including all mobile unit tests and all three demo UI scenarios.
- Final lifecycle run: 8 passed, no failures; deletion, restart, explicit restore, saved-answer retention, newer/older demo revisions, failed persistence, corpus-byte deletion, unrelated-project preservation and late-cache suppression.
- Full `swift test` passed; five focused `BundledUserGuideTests` passed again for Guide v34. Three deterministic guide-packaging tests passed.
- The first full Swift attempt caught an obsolete test expectation for the removed demo section title. The expectation was corrected to require both document filenames and the restoration instructions; the complete suite then passed.

The four captures in this directory are historical original `XCTAttachment` app captures exported from `lifecycle-merged.xcresult`. Current post-correction originals are in [current-ios](current-ios/). Their manifest supplied the actual capture timestamps. Sidecars use the canonical capture helper; native logical points are explicitly identified instead of claiming a browser/CSS viewport. The capture producer is `6f90bc00752a11e6e7709becf937303cb212d5e8`. Subsequent changes are evidence and the recorded compilation count only. Captures are review evidence, not instructional screenshots or physical-device acceptance.

| State | Original capture | Metadata |
|---|---|---|
| Ordinary project row | [library](library.png) | [sidecar](library.metadata.json) |
| Swipe reveals a button; row remains | [swipe](swipe-delete.png) | [sidecar](swipe-delete.metadata.json) |
| Settings recovery completed | [restored](restored.png) | [sidecar](restored.metadata.json) |
| English document opened inside Demo | [document](document.png) | [sidecar](document.metadata.json) |

## Historical packaged Help v34

Fresh real QA process PID 66019, version/build `0.3.1136/1136`, producer `fa95ce6ce991336f3523c4cd5d5dba5e0455f8ab`; identity and startup evidence are in [help-instance.json](help-instance.json) and [startup.json](startup.json). `launch.sh --qa` validated the real executable, dependencies and signatures before launch. Both Help-opened v34 personal packages matched their bundled bytes exactly.

English and Spanish guides were opened through the real Help menu in that same instance. AX showed inline/display equations, underbraces and tagged box-counting equation (1), chart/local-image nodes and tables. Disabling Math showed literal source notation in both guides; source code examples remained literal. Separate practices in both locales were filled, saved, closed and reopened, then their initially empty names were restored. Initial English interface and enabled Math were restored; the owned QA app quit normally.

**Historical v34 limitation:** `cua.getAXStateAndScreenshot` failed with `-10005 stageManagerProcessNotRunning`. Those AX/component checks did not establish visual acceptance. The current v35 fresh-process visual run below supersedes that pending state. No physical iPhone, TestFlight or release claim.

The first Help opening found an unrelated personal v31 copy (existing #378 signature). It was retained intact. v34 was allocated instead; this is mitigation for this task, not a fix for general working-copy identity.

## Retention

The task-owned worktree `.worktrees/407-mobile-projects` and its internal `.build/407-derived`/Swift caches are retained for the current regression checks and review. No shared/other-thread caches were removed. The owned simulator is retained for reproducing the gesture test. It is not a user device.

## Final synchronization with main

Integrated `origin/main` through `38208529`, preserving #405's compact reader and its bilingual help. Current packages are Guide v35, combining that text and #407 without overwriting tested v34 personal copies. Guide v35 has now completed its own packaged visual acceptance below; v34 evidence above remains historical component/workflow evidence only. The post-integration mobile run passed 19 tests with no failures; `ios-merged-summary.json` records the device and exact counts.

Post-integration full `swift test` passed with no failures. Deterministic Guide v35 packaging passed all three tests. This checkpoint recorded nine successful compilation invocations. The current entry records thirteen after the fresh v35 packaged build, focused correction regression, full Swift suite and final iOS run. Failed commands were not counted. The two earlier disposable QA bundles were removed after their owned processes quit; the v35 bundle and worktree-local caches are retained for the current review.

## Fresh packaged v35 visual acceptance

On 2026-11-10, `LEONARDO_SOURCE_PR=408 ./launch.sh --qa` built and verified the real executable, then launched fresh PID 5393. The QA bundle reports `0.3.1147/1147`, the unmaterialized source baseline rather than a new release. Its producer is `782154361512b31ea3837616c30303cf2a013743`; [instance.json](native-v35/instance.json) records the unique bundle identity, executable hash, no-XCTest dependency check and production input objects.

Both v35 locales opened through the actual Help menu. Their source, packaged and Help-opened personal copies matched byte-for-byte. Eleven [original CUA screenshots](native-v35/) cover English/Spanish Mermaid, inline/display math, complete underbraces/radicals/arrows/cancellation, the tagged box-counting equation (1), charts, local images, tables, the updated mobile workflow, Math-disabled source fallback, and both separate practices saved/closed/reopened with fictional values. Initial blank practice names were restored and saved; English and enabled Math were restored. Normal application quit and disappearance of the owned bundle were observed.

The early capture attempts still encountered ScreenCaptureKit/window-position errors and Stage Manager thumbnails. Raising/zooming the owned QA window and using the document-outline controls produced full native captures without changing host settings or controlling another application. Each original has capture context and a canonical image hash/dimension sidecar. CUA does not expose CSS/native-point viewport geometry or its WKWebView engine version; those fields are explicitly unavailable. The shared helper's image/source collectors are used, with this native-schema limitation recorded rather than fabricated browser geometry.

## Final cache-correction and iOS validation

Review found [LMB-410](https://github.com/PinedaTec-EU/LeonardoMD/issues/410): a malformed cache recreated after deletion could be decoded before the removal filter and abort the library reload. The correction excludes removed UUIDs before cache decoding and direct synchronization cleanup, preserving authorization and unrelated recovery archives. Regression tests cover malformed late bytes, missing credentials, unrelated recovery and independent personal Demo copies across content revisions.

- Deterministic Guide v35 packaging: **3 passed**, no failures.
- Focused `MobileDemoStoreTests` and `MobileRevocationTests`: **16 passed**, no failures.
- Final iOS mobile units plus all `MobileDemoUITests`: **23 passed** (20 unit, 3 UI), no failures or skips. The compact-reader geometry tests from main remain included.
- Full `swift test`: **694 XCTest**, 35 expected skips, zero failures; **72 Swift Testing** cases, zero failures.
- [Final result summary](current-ios/validation-summary.json), [source mapping](current-ios/production-inputs.json), [final debug app hashes](current-ios/final-ios-bundle.json) and four original passed-test captures are retained in [current-ios](current-ios/). Producer: `8bc2122cf52c05c316b762bbb565c322dd5b6e67`. The document capture records navigation before content finishes rendering; the separate offline-demo UI test proves render readiness and saved-answer persistence, rather than that early image.

The Mac production inputs recorded for producer `78215436` and iOS production inputs for `8bc2122c` must equal the final reviewed head. Later changes contain validation evidence, wiki synthesis and the recorded compilation count only. Native logical viewport/engine geometry is unavailable and explicitly null. The simulator was shut down before the read-only installed-container comparison, so the signed build-product hashes do not claim a post-run installed digest match. No physical-device, TestFlight or distribution acceptance is claimed.

Current-head CI and the complete strict independent report are recorded on PR #408 after publication. The general release-cleanup inventory encounters an unrelated stale `/private/tmp/leonardo-129-final-judge` worktree registration; that script is not reported as passed. The selected main/408 checkouts were audited separately, preserving the unrelated user cache and other tasks' worktrees.

## On-demand merge reconciliation

The owner authorized resolving the in-progress main merge at `945d05aa` (on-demand sync #384/#385). The resolution retains one project list, restores Demo from Settings, keeps cache settings and the new on-demand reader, and moves removal guards into the sole downloads synchronization path. Local deletion now denies active download access and purges downloaded/offline files as well as the corpus record. A regression populates and reads the real on-demand cache before deletion, then verifies both storage boundaries and blocked reads. Both locale sources include the main on-demand chapter and project lifecycle chapter; new Guide v36 packages avoid overwriting earlier personal copies. Prior v35 screenshots are historical until current-candidate acceptance is recorded.

## Received-project deletion after integration

The main merge is fully resolved and committed at `8b893299`; the deleted-project guards now live in `MobileLibrary+Downloads.swift`, preserving the incoming on-demand architecture. The later producer `de24b150fd3cb97ad40986d3945875e58a04791c` rechecks durable deletion after both catalogue fetch and cache update suspension, purges a late catalogue when necessary and continues with unrelated descriptors. File delivery checks deletion before and after its authenticated request.

Validation after resolution:

- Full host suite: **745 XCTest**, 38 expected skips, zero failures; **72 Swift Testing** cases, zero failures.
- Mobile units and all three Demo UI scenarios: **24 passed**, zero failures or skips. The reset test now waits for and targets the actual confirmation sheet ([#411](https://github.com/PinedaTec-EU/LeonardoMD/issues/411)), preserving saved practice instead of wiping the simulator.
- On-demand native UI flow: **1 passed**, zero failures/skips, against the independent pinned HTTPS fixture: **1 passed**. The full flow verifies catalogue-only enrollment, a single requested body, separate offline retention, automatic retry/future descendants, then received-project swipe + explicit Delete, relaunch, authenticated refresh and persistent absence while Demo stays visible.
- The source audit has **zero bulk snapshots**; no remote reference body was fetched. `test-without-building` reused the exact build-for-testing product and did not add another compilation count. The accumulated source-PR entry now records **18 successful compiling commands**; failed runs were not counted.

The [before](on-demand-reconciliation/project-before-delete.png), [revealed Delete](on-demand-reconciliation/project-swipe-delete.png) and [after relaunch/refresh](on-demand-reconciliation/project-deleted-after-refresh.png) captures were visually inspected. Their contexts use measured `app.frame` native points and `viewport_css: null`, without a hardcoded hardware model. [Input groups](on-demand-reconciliation/source-inputs.json), result summaries, source request audits and original images/metadata bind the evidence to the producer.

### Current packaged Guide v36 acceptance

After explicit owner approval, the official additional-instance workflow opened fresh QA PID 56776 with `--new-instance`, while installed principal PID 41520 remained running. Both Guide v36 locales opened through Help and matched the source and packaged resources byte-for-byte. The real executable reports baseline 0.3.1215/1215 and has no XCTest linkage; this is not a release.

Eleven original full-size native captures in [native-v36](native-v36/) cover Mermaid, inline and display math (one-line, multiline, Markdown-sensitive TeX and tagged equation), charts, local images, tables, literal examples, disabled-Math fallback and the updated project workflow. Both separate practice forms were filled with fictional names, saved, closed and reopened; original bytes were restored after closing QA. English and enabled Math were restored. QA quit normally, Allow multiple instances returned to false, and the installed application's original Synchronization preferences remained open. Initial Stage Manager thumbnails are isolated under diagnostics and are not acceptance evidence. Native geometry limitations are explicit in each metadata file.

The final current-source mobile unit rerun passed **21 tests**, no skips or failures, without another compilation. Compilation delta remains 18. Another owner-authorized thread owns the final independent judgment and merge; this implementation thread does not duplicate those actions.
