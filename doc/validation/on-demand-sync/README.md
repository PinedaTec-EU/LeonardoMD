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
