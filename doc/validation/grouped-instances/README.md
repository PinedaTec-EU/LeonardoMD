# Grouped independent-instance QA — 13 November 2026

Canonical feature: [#440](https://github.com/PinedaTec-EU/LeonardoMD/issues/440).
Candidate menu correction: [#443](https://github.com/PinedaTec-EU/LeonardoMD/issues/443).
Cleanup convention: [#438](https://github.com/PinedaTec-EU/LeonardoMD/issues/438).

## Automated checks

- Initial focused preference, process-policy, IPC and Help tests: 38 passed.
- After native-menu correction: full Swift suite passed 817 XCTest cases
  (41 optional skips), plus 72 Swift Testing cases; zero failures.
- Deterministic guide packaging: 3 Python tests passed.
- Seven successful compiler-bearing commands are recorded in PR 441's entry:
  initial focused/full tests, initial package, QA launch build, correction focused
  tests, final full suite and final QA launch build. Failed/metadata queries add no count.

## Packaged observations

The real app was built/launched through `./launch.sh --qa --args --new-instance`.
The packaging verifier checked the executable, dependencies and signatures.
Packaged metadata remains 0.3.1371/build 1371; source-PR deltas have not been
materialized into a published release. `runtime-identity.json` binds the final
executable and both personal Help copies to the bundled templates.

Initial product source: `66320a934b2bf9eec50891842649e41f19735331`.
Final built product source: `34c132755081857f534c5ff862f09e4319a81e71`.
Only evidence and compilation-ledger records are added after that source commit;
compare the final reviewed head against it before consuming these captures.

- The grouping toggle is disabled when multiple instances are off; switching
  multiple instances back on restores availability. No processes were closed by
  changing the preference.
- Two same-bundle independent QA processes were listed by PID in the selector.
  The additional process logged accessory policy (1), success=true.
- After representative PID 93693 exited, PID 94752 logged regular policy (0).
  A separate QA bundle PID 12924 logged accessory policy, then regular policy
  after PID 94752 exited. Presentation election left sync/update ownership alone.
- CUA could not reliably address the remaining process after the first of two
  processes with the same bundle identity exited. This is a validation-tool
  limitation, not evidence that its window or process crashed. A separate bundle
  identity could be inspected after replacement.
- The first synchronous Application menu popup dismissed immediately. The final
  native pull-down correction remained open, displayed the application commands,
  and opened English and Spanish Guide v70 through its real Help submenu.
- Final packaged Help rendered inline and display math, underscored fractions,
  underbraces, radicals/arrows and the tagged box-counting equation without KaTeX
  errors. Both guides opened as personal copies; hashes match the candidate.
- During the earlier candidate's live inspection, Mermaid, local images, charts
  and tables were present; Math-disabled Spanish fallback preserved literal TeX,
  and Math was restored. Code examples remained literal. These observations are
  historical and do not establish complete final-instance Help acceptance.

## Remaining acceptance

**The PR is not ready for acceptance.** Both language practice forms are already
owned by pre-existing LeonardoMD instances. Real Help-link attempts returned the
normal document-in-use warning. Their open/fill/save/reopen smoke tests remain
pending, together with the complete per-instance ES/EN enabled/disabled example
matrix, final multi-process visual recheck and independent review after CI.
No existing session or answer was overwritten or forcibly closed.

## Evidence

`final-*` captures show the final built product source, native preference UI and
both Help locales. Files without that prefix are historical captures of the
initial candidate (Guide v69), retained to distinguish the earlier observations.
The original bytes are JPEG and use `.jpg`; no conversion or alteration was made.
Capture sidecars use the common helper. Because these are native AppKit captures,
CSS viewport and browser version do not apply: the compatibility viewport fields
explicitly contain screenshot pixels, not measured CSS or window points.

## Teardown

All four task-created processes exited: 93693, 94752, 12924 and 29348. The first,
third and final process used ordinary app Quit; PID 94752 used Activity Monitor's
normal Quit after exact PID selection (not Force Quit) because same-bundle CUA
addressing was unavailable. No unsaved edits were made. A process-table check and
CUA app inventory confirmed no remaining task-owned instances. Shared grouping
was restored off, multiple instances remains on, and Math remains on.
No Device Hub session was created. Pre-existing processes and device sessions
were preserved. The disposable QA bundles remain available as build evidence;
they are not installed releases.
