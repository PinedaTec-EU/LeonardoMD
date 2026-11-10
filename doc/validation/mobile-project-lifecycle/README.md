# Mobile project lifecycle validation

Tracking: [#407](https://github.com/PinedaTec-EU/LeonardoMD/issues/407), [PR #408](https://github.com/PinedaTec-EU/LeonardoMD/pull/408).

## Behavior

One name-sorted project list includes the explicitly local Demo project. Its language files open within the project. Every row uses a trailing swipe action with full-swipe deletion disabled. Device-local removal intent is written atomically before corpus removal; reload and synchronization exclude removed IDs. Mac originals are unaffected. Settings restores Demo without resetting current-revision answers. Only a strictly newer `MobileDemoStore.contentRevision` restores it automatically; that same revision selects the personal-copy directory.

## Validation

- iPhone 17 Pro, owned simulator `1A969A0F-D7E2-4C62-B288-CC893C3CBEEF`, iOS 27.0 (24A434), Classic light, synthetic demo/practice data.
- Expanded iOS run: 19 passed, no failures, including all mobile unit tests and all three demo UI scenarios.
- Final lifecycle run: 8 passed, no failures; deletion, restart, explicit restore, saved-answer retention, newer/older demo revisions, failed persistence, corpus-byte deletion, unrelated-project preservation and late-cache suppression.
- Full `swift test` passed; five focused `BundledUserGuideTests` passed again for Guide v34. Three deterministic guide-packaging tests passed.
- The first full Swift attempt caught an obsolete test expectation for the removed demo section title. The expectation was corrected to require both document filenames and the restoration instructions; the complete suite then passed.

Screenshots are original `XCTAttachment` app captures exported from `lifecycle-merged.xcresult`. Their manifest supplied the actual capture timestamps. Sidecars use the canonical capture helper; native logical points are explicitly identified instead of claiming a browser/CSS viewport. The capture producer is `6f90bc00752a11e6e7709becf937303cb212d5e8`. Subsequent changes are evidence and the recorded compilation count only. Captures are review evidence, not instructional screenshots or physical-device acceptance.

| State | Original capture | Metadata |
|---|---|---|
| Ordinary project row | [library](library.png) | [sidecar](library.metadata.json) |
| Swipe reveals a button; row remains | [swipe](swipe-delete.png) | [sidecar](swipe-delete.metadata.json) |
| Settings recovery completed | [restored](restored.png) | [sidecar](restored.metadata.json) |
| English document opened inside Demo | [document](document.png) | [sidecar](document.metadata.json) |

## Packaged Help

Fresh real QA process PID 66019, version/build `0.3.1136/1136`, producer `fa95ce6ce991336f3523c4cd5d5dba5e0455f8ab`; identity and startup evidence are in [help-instance.json](help-instance.json) and [startup.json](startup.json). `launch.sh --qa` validated the real executable, dependencies and signatures before launch. Both Help-opened v34 personal packages matched their bundled bytes exactly.

English and Spanish guides were opened through the real Help menu in that same instance. AX showed inline/display equations, underbraces and tagged box-counting equation (1), chart/local-image nodes and tables. Disabling Math showed literal source notation in both guides; source code examples remained literal. Separate practices in both locales were filled, saved, closed and reopened, then their initially empty names were restored. Initial English interface and enabled Math were restored; the owned QA app quit normally.

**Pending visual acceptance:** `cua.getAXStateAndScreenshot` failed with `-10005 stageManagerProcessNotRunning`. AX content and component tests do not establish rendered image/diagram/stroke appearance. Complete the required visual Help smoke before readiness/judgment/merge. No physical iPhone, TestFlight or release claim.

The first Help opening found an unrelated personal v31 copy (existing #378 signature). It was retained intact. v34 was allocated instead; this is mitigation for this task, not a fix for general working-copy identity.

## Retention

The task-owned worktree `.worktrees/407-mobile-projects` and its internal `.build/407-derived`/Swift caches are retained for pending visual acceptance and review. No shared/other-thread caches were removed. The owned simulator is retained for reproducing the gesture test. It is not a user device.

## Final synchronization with main

Integrated `origin/main` through `38208529`, preserving #405's compact reader and its bilingual help. Current packages are Guide v35, combining that text and #407 without overwriting tested v34 personal copies. Guide v35 requires its own packaged visual acceptance; v34 evidence above is historical component/workflow evidence only. The post-integration mobile run passed 19 tests with no failures; `ios-merged-summary.json` records the device and exact counts.

Post-integration full `swift test` passed with no failures. Deterministic Guide v35 packaging passed all three tests. PR #408 records nine successful compilation invocations (failed commands were not counted). Both disposable native QA bundles were removed after their owned processes quit; current worktree-local build caches total approximately 1.4 GiB and are retained for the pending checks.
