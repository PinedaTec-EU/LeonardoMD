# Helper consultation correction

Issue [#394](https://github.com/PinedaTec-EU/LeonardoMD/issues/394),
PR [#398](https://github.com/PinedaTec-EU/LeonardoMD/pull/398).

The suspended-settings regression fails with the previous `guard !configuring`
reload behavior: a concurrent read immediately returns busy instead of waiting.
The corrected helper uses a FIFO barrier and each queued command re-reads consent.
Cancellation skips that command's configuration read and releases its turn.
The poll runner is read-only and always receives the same UUID; one transient
failure recovers automatically, four consecutive failures surface the original
error, and cancellation neither retries nor delivers. No retry path invokes create.

The owning source commit introduced only these recovery internals, not UI controls
or a new help workflow. The public preferences-read port allows a real suspended
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
