# Reconciled candidate acceptance — completed 13 November 2026

Built product source: `29b8493f97a4747068b02ae8c9111a61164e9a66`, based on main
`2542a940c2b7c964ab4ed29cb72fefefb53f9c64`. Packaged version 0.3.1587/build 1587,
Guide v71. Later PR commits change only evidence and compilation allocation;
compare Sources, Tests, Package.swift and scripts against that build commit.
The release ledger entry records 9 successful compiler-bearing invocations:
7 from the original candidate, then the reconciled full test and release build.
No release has been published by this validation.

## Automated validation

- Full reconciled Swift suite: 902 XCTest cases (41 optional skips), plus
  72 Swift Testing cases; zero failures.
- Deterministic guide packaging: three Python tests passed.
- The reconciled source head passed macOS CI. Final review must use green CI
  and a strict fresh-agent verdict for the final PR head, not that older head.

## Live packaged acceptance

| Process | Identity | Help and practice |
| --- | --- | --- |
| B / 95948 | eu.pinedatec.LeonardoMD.qa.a794635da723448fb60b33db6cd0860f | ES and EN real Help; enabled examples; disabled Math fallback; form fill/save/close/reopen |
| A2 / 7354 | eu.pinedatec.LeonardoMD.qa.3a0bffd58ffc421f82471e787b12a646 | Same complete bilingual matrix; ordinary Quit cancellation preserves the unsaved form |

Both profiles inspected local images, Mermaid, tables and charts, inline and
display equations, underscores, underbraces, radicals/arrows and the tagged
box-counting equation. With Math enabled, actual display equations and tag (1)
rendered without KaTeX errors. With Math disabled, literal TeX was retained;
code examples stayed literal in both states. Math was restored after checking.
Each separate practice form was filled with synthetic data, saved, closed and
reopened with the same answer. `identity.json` records original/copy guide hashes
and saved practice values; AX transcripts record reopened controls and state.

A2 ordinary Quit showed Save / Discard / Cancel with an unsaved form. Cancel
kept the process, document and exact answer open; Save followed by close/reopen
preserved that answer. The corresponding capture and transcript are included.

The grouping preference was unavailable with multi-instance off and retained its
stored choice. Re-enabling multi-instance restored availability. Both independent
processes appeared by PID in the selector; selecting another process activated
its actual window. B initially logged accessory policy (1). Closing initial
representative A / 94348 normally promoted B to regular policy (0); A2 then
logged accessory policy. The native application-menu control remained usable in
accessory mode and its real Help submenu opened each guide. Presentation election
did not change sync/update ownership. Unit coverage separately exercises actual
principal ownership release/claim and default ungrouped policy.

## Fixture isolation and chronology

The first A/B startup used a shared temporary home. A's Help attempt correctly
refused B's process-lifetime document reservation even after B closed its tabs.
A exited normally. That shared-home attempt is superseded by the complete B/A2
per-process-home matrix above, not reported as successful A Help acceptance.
No source or ownership rule was changed to bypass the reservation.

CFFIXED_USER_HOME isolates Foundation home and Application Support/document data;
per-Mac instance defaults remain shared with the account. The existing app's own
settings were not treated as an isolated suite. The process-specific temporary
homes contain only synthetic QA data. Reproduction uses a real bundle built by
`LEONARDO_SOURCE_PR=441 ./launch.sh --qa --env CFFIXED_USER_HOME=<temporary-home> --args --new-instance`.
Prepare a second distinct QA copy with scripts/qa-bundle.py, preserving the app
executable/dependencies, and pass a distinct temporary home through open --env.
Enable the three built-in example engines in that profile through Preferences.
Do not launch a second same-home process against an already reserved guide.

The Mac locked during initial A2 connection; the owner manually unlocked it and
all pending checks were completed. A CUA timeout interrupted a later multi-action
call; the saved file was checked and its real UI reopen was completed before
counting persistence as passed. Those events are resolved, not acceptance waivers.

## Evidence provenance

All captures and AX records were produced from the running packaged candidate,
not fixtures or generated design images. Original bytes are JPEG (`.jpg`), with
common-helper sidecars. Native screenshot pixels occupy the compatibility
viewport fields; CSS viewport/browser version are not applicable or exposed.
Previous captures outside this directory are historical candidates only.
No third-party/user documents appear in this synthetic profile evidence.

## Teardown

PIDs 94348, 95948 and 7354 exited normally; process-table checks confirmed their
exact bundle paths absent. Shared grouping was restored off and multi-instance
restored on (the pre-test baseline). B's Math setting was restored on, and A2's
Math setting was restored on before teardown. No task-created Device Hub session
exists. Pre-existing and other-task app/device sessions were preserved. No force
quit was used. The temporary checkout/cache is removed after merge verification;
synthetic profile data and disposable bundles can be retained as QA artifacts.
