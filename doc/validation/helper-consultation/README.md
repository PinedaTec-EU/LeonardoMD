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

Initial focused5/5, current focused8/8 (helper queue, bundled Help and native recovery), and complete tests are recorded in validation.json. Runtime physical
acceptance belongs to the combined signed main candidate, not this isolated branch
or the older physical result recovered with manual Retry. Do not infer the numeric
NSError mapping or claim every cause of the original delayed alert is reproduced.
The transport candidate's tested original TLS behavior and current helper26651
remain untouched during these local checks. No private drawing or pairing payload
is committed. Existing manual Retry remains available for persistent errors.

## Accepted-main reconciliation (8 November 2026)

The branch includes accepted/materialized main
`8e2af213c6208d471adf019a3c0d9869ed24505f` (0.3.1127), containing
[PR392](https://github.com/PinedaTec-EU/LeonardoMD/pull/392). The current complete suite at build source
`b9c5bb7a1cb46d5d989d78de833fae57e402a9c5` passes717 XCTest checks,
35planned skips, zero failures and71 Swift Testing checks (28 core and43 render).
The seven executable summaries and current log digest are in validation.json.
The source compilation allocation is9, including the focused recovery/Help
checks and actual packaged QA build.

The owner's selected beta includes connection and rubric corrections only;
[PR385](https://github.com/PinedaTec-EU/LeonardoMD/pull/385) is deferred. Final
Guide29 EN/ES live examples, Math ON/OFF, practice save/reopen and physical rubric
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
checks with7planned skips. The artifact recovery keeps the dependency pin unchanged. Current product, Help
and test inputs are covered by the complete build-source suite below; CI and
fresh strict review still target the new head.
The fixed asset identity intentionally fails closed on a future dependency pin
change until its immutable manifest/asset binding is reviewed together.

## Current native evidence and complete validation

At build/capture source `b9c5bb7a1cb46d5d989d78de833fae57e402a9c5`, the real
production RubricEditor/controller run in the configured SwiftPM XCTest runner
with an isolated synthetic runtime and store. The focused native test passes1/1;
the complete same-build suite (skip-build, no new compilation) passes717 XCTest,
35planned skips, zero failures, plus71 Swift Testing. The source allocation is now9; the new
summary includes both rubric recovery and the #403 CI dependency recovery.

Eight full-density EN/ES original PNGs in `native-recovery/` were visually inspected, alongside four separately captured logical-resolution guide originals. Six refreshed guide illustrations (two canvas and four recovery/error originals) were also inspected for legibility. Each has
its original capture-time context and generated shared metadata. Recovery uses
the same attached hosting view: first failure remains waiting without Retry or
error; the second same-ID read displays the received drawing and save actions.
Four persistent failures show the original error and Retry. The closing scenario
removes the real editor, exercises onDisappear cancellation, and observes no
second query or response. Six transition traces record synthetic original/query
UUIDs, zero create/manual-Retry calls and actual full-run XCTest PID78513.
The source version is0.3.1127, debug component build, not a packaged app. Native
viewport696x820points yields1392x1640original pixels; metadata's viewport_css field
records observed native points because CSS/browser versions do not apply.

`native-recovery/build-inputs.json` binds all production/test/packaging inputs to
the build source and test executable digest. Later evidence/docs/ledger-only
changes must leave every scoped object identical. Reproduce with
`EVIDENCE_SHA=$(git rev-parse HEAD) LEONARDO_RUBRIC_RECOVERY_CAPTURE=/tmp/leonardo-rubric-review python3 scripts/compile-and-record.py --pr-number 398 -- swift test --filter RubricRecoveryVisualTests`.
No test executable is placed inside an app or launched as a standalone GUI.
This component evidence does not replace final signed-main fresh-process Help29
EN/ES, physical no-manual-Retry and beta archive/feed acceptance.

## Packaged Guide29 smoke test

`packaged-help29/validation.json` records real QA PID81719, source b9c5bb7,
version0.3.1127 and the unique disposable QA bundle identity. The normal
`LEONARDO_SOURCE_PR=398 ./launch.sh --qa` workflow built the real executable and
verified its dependencies/signature; it did not launch an XCTest app. First-window
readiness was observed, followed by actual Help/Ayuda opening both bundled guides.
Personal copies matched both bundle hashes. Twenty original native JPEGs retain
their capture-time contexts and canonical metadata; 2520x1700 is the observed
native captured-pixel viewport, not a claim about browser CSS geometry.

Both locales passed Mermaid, inline/one-line/multiline math, Markdown-sensitive
underbraces, complete radical/arrow/cancel shapes, tagged box-counting equation(1),
Charts, local images, tables, literal code and Math-disabled fallback. Each real
separate practice form was filled with fictional data, saved, closed and reopened
through its guide action. Three prior originals (preferences and both practice
forms) were backed up and restored byte-for-byte after normal quit. Protected
helper26651, pairing, grants, corpus and saved physical rubric remained untouched.
This pre-merge ad-hoc QA does not replace final Developer-ID/notarized main or the
physical no-manual-Retry round trip.

For repeatable capture, activate the existing QA app via its own Finder bundle
before observing it: Stage Manager can otherwise return a tiny thumbnail of an
inactive window. Preserve native image bytes, detect PNG versus JPEG, and reject
thumbnails before publishing metadata. After ordinary Quit, verify PID absence
read-only; requesting native AX state can reactivate an empty instance and must
not be mistaken for a failed quit or new Help acceptance.
