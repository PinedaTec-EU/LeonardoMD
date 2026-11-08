# Helper consultation correction

Issue [#394](https://github.com/PinedaTec-EU/LeonardoMD/issues/394),
PR [#398](https://github.com/PinedaTec-EU/LeonardoMD/pull/398).

The suspended-settings regression fails with the previous `guard !configuring`
reload behavior: a concurrent read immediately returns busy instead of waiting.
The corrected helper uses a FIFO barrier and each queued command re-reads consent.
Queue cancellation is cooperative, not a promise of prompt interruption: the cancelled command remains suspended until the active configuration owner releases the FIFO barrier. If that predecessor stays suspended, its waiters also stay suspended. Once resumed, a cancelled command skips its configuration read and releases its turn; subsequent live commands still read current consent. The regression holds the predecessor suspended while checking that cancellation neither completes early nor reads preferences, then releases it and verifies the next live command.
The poll runner is read-only and always receives the same UUID; one transient
failure recovers automatically, four consecutive failures surface the original
error, and cancellation neither retries nor delivers. No retry path invokes create.

The recovery changes the visible waiting/error flow without adding controls.
The bilingual bundled guide describes automatic waiting/recovery, persistent
error/Retry and closing the editor; source/component evidence remains separate
from the required final packaged Help and physical acceptance. The public preferences-read port allows a real suspended
boundary in the helper test. Production still uses ConfigurationStore.

Focused5/5 and complete tests are recorded in validation.json. Runtime physical
acceptance belongs to the combined signed main candidate, not this isolated branch
or the older physical result recovered with manual Retry. Do not infer the numeric
NSError mapping or claim every cause of the original delayed alert is reproduced.
The transport candidate's tested original TLS behavior and current helper26651
remain untouched during these local checks. No private drawing or pairing payload
is committed. Existing manual Retry remains available for persistent errors.

## Accepted-main reconciliation (8 November 2026)

The branch includes accepted/materialized main
`8e2af213c6208d471adf019a3c0d9869ed24505f` (0.3.1127), containing
[PR392](https://github.com/PinedaTec-EU/LeonardoMD/pull/392). The complete suite
at source `b8390736ef68ee8cc2105d5a5311bdd79e58085e` passed: 716 XCTest checks,
35 planned skips, zero failures, plus 71 Swift Testing checks (28 core and 43
render). The seven executable summaries and log digest are in validation.json.
The successful recorder invocation increased this PR's compilation delta to 5.
Subsequent validation/context and CI cache-preparation edits do not change
Swift product/test inputs.

The owner's selected beta includes connection and rubric corrections only;
[PR385](https://github.com/PinedaTec-EU/LeonardoMD/pull/385) is deferred. Final
Guide25 EN/ES live examples, Math ON/OFF, practice save/reopen and physical rubric
without manual Mac Retry remain post-merge gates on the exact signed main app.
This source validation neither activates a helper nor publishes a release.

## CI dependency recovery (#403)

[Issue403](https://github.com/PinedaTec-EU/LeonardoMD/issues/403) records repeated
HTTP504/92-byte failures from the pinned Sparkle browser-download endpoint.
`scripts/prime-sparkle-cache.py` fetches the same official asset through GitHub's
asset API before SwiftPM runs. It requires the reviewed Package.resolved version,
revision and repository and verifies the exact upstream Package.swift SHA-256 and
asset length before atomically publishing a cache entry. SwiftPM retains its own
normal checksum verification. It never edits a manifest, upgrades a dependency,
executes downloaded code, skips a test or adds a secret. CI's ephemeral GitHub
token has contents:read only and is passed through the environment to gh.

The real CLI downloaded and verified the official artifact into a fresh isolated
cache; a fresh `swift package resolve` fetched the binary from that cache despite
the browser endpoint outage. Six security regressions cover checksum tampering at
the correct length, wrong length, changed pin, interrupted downloads, verified
reuse and symlink/other-file protection. The complete Python suite passes118
checks with7planned skips. Swift product/test inputs remain unchanged from the
recorded716/35/71 full run; CI and fresh strict review still target the new head.
The fixed asset identity intentionally fails closed on a future dependency pin
change until its immutable manifest/asset binding is reviewed together.

## Current native evidence and complete validation

At build/capture source `0ba23aa41121d20f3b7adb945e2080389df05c73`, the real
production RubricEditor/controller run in the configured SwiftPM XCTest runner
with an isolated synthetic runtime and store. The focused native test passes1/1;
the complete same-build suite (skip-build, no new compilation) passes717 XCTest,
35planned skips, zero failures, plus71 Swift Testing. This supersedes the earlier
716-check run for current validation. The source allocation is now6; the new
summary includes both rubric recovery and the #403 CI dependency recovery.

Eight EN/ES original PNGs in `native-recovery/` were visually inspected. Each has
its original capture-time context and generated shared metadata. Recovery uses
the same attached hosting view: first failure remains waiting without Retry or
error; the second same-ID read displays the received drawing and save actions.
Four persistent failures show the original error and Retry. The closing scenario
removes the real editor, exercises onDisappear cancellation, and observes no
second query or response. Six transition traces record synthetic original/query
UUIDs, zero create/manual-Retry calls and actual full-run XCTest PID40146.
The source version is0.3.1127, debug component build, not a packaged app. Native
viewport696x820points yields1392x1640original pixels; metadata's viewport_css field
records observed native points because CSS/browser versions do not apply.

`native-recovery/build-inputs.json` binds all production/test/packaging inputs to
the build source and test executable digest. Later evidence/docs/ledger-only
changes must leave every scoped object identical. Reproduce with
`EVIDENCE_SHA=$(git rev-parse HEAD) LEONARDO_RUBRIC_RECOVERY_CAPTURE=/tmp/leonardo-rubric-review python3 scripts/compile-and-record.py --pr-number 398 -- swift test --filter RubricRecoveryVisualTests`.
No test executable is placed inside an app or launched as a standalone GUI.
This component evidence does not replace final signed-main fresh-process Help25
EN/ES, physical no-manual-Retry and beta archive/feed acceptance.
