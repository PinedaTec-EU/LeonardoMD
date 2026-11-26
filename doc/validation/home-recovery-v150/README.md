# Home recovery and Guide v150 native QA

Tracking: [PR #516](https://github.com/PinedaTec-EU/LeonardoMD/pull/516) and
[#514](https://github.com/PinedaTec-EU/LeonardoMD/issues/514).

## Packaged process

The candidate was built from exact source `724390f75e36e923866efee9857e8b9dc2c5e963`
with `LEONARDO_SOURCE_PR=516 ./launch.sh --qa`. The package reported version
`0.3.2318`, build `2318`, and the compilation ledger entry recorded build delta
20. The QA bundle was the real `LeonardoMD` executable at
`/tmp/leonardo-516-qa-final.rBC6Gq/tmp/leonardo-native-qa-89mzr1xg/LeonardoMDQA.app`.
Startup reached `application_ready` in fresh process PID `94241`, started at
`2026-11-26T09:52:47+01:00`; the bundle executable is `LeonardoMD`, has no
`XCTest.framework` linkage, and used the disposable home
`/tmp/leonardo-516-qa-final.rBC6Gq/home`.

The fixture contained only synthetic folders. No user project was opened or
modified, and no real Sync grant, pairing, helper or preference was changed.

## Home relocation flow

| State | Native result |
| --- | --- |
| Fresh Home | No saved items; the synthetic project was opened through `Open project…`, producing a Recent row for `Old Project`. |
| Missing saved location | After the fixture folder was moved, the row became disabled and showed the checked old path plus the warning that the saved location was not found. Its warning menu exposed `Retry saved location` and `Locate moved item…`. |
| Intentional cancel | `Locate moved item…` opened the native folder chooser. `Cancel` left the row disabled and preserved the old path. |
| Successful recovery | Choosing the synthetic `New Project` folder and `Use this location` changed the row to an enabled `New Project` at `/private/tmp/leonardo-516-qa.gajRv4/New Project`; opening it displayed the expected `README.md` and `relocation-note.md`. |

## Bundled Help smoke

Help was opened through the application Help menu in both languages. The
working copies were created in the disposable home and their hashes matched
the candidate package:

| Locale | Working copy opened by Help | SHA-256 | Native checks |
| --- | --- | --- | --- |
| English | `.../User Guides/v150/en/Guide-v150-en.mdlz` | `0e17463a0052718973fde8591255226bb9ec9f0e27d1f2ef2686e438b748e9f4` | Package header showed `en`; chapter **7. Home, recent items and favorites** rendered and described `Locate moved item…`; durable capture `captures/help-v150-en.jpeg`. |
| Español | `.../User Guides/v150/es/Guide-v150-es.mdlz` | `2e344eb7e182afb2d44f02a3a077b459b6e003a9b4c8ba1e4da5c557cf6d8ddd` | Preferences changed language only inside the disposable home; Help reopened as `es`; chapter **7. Inicio, recientes y favoritos** rendered and described `Localizar el elemento…`; durable capture `captures/help-v150-es.jpeg`. |

The extension recommendation was dismissed with `Not now/Ahora no`; no
extension or synchronization setting was enabled. The practice form was not
re-run because this PR changes Home recovery and bundled Help packaging, not
practice behavior; deterministic guide/package tests cover the packaged
resources.

## Focused visual retake and process identity reconciliation

An authorized focused retake used the exact candidate bundle and a synthetic
fixture only. Through the native Home window, CUA Sky captured the disabled
`Old Project` row, its warning recovery menu, and the enabled relocated row
after choosing the moved folder. The project pane showed the synthetic
`README.md` and `relocation-note.md`. The Help smoke was captured in both
English and Spanish with chapter 7 selected. These are durable, repository-
scoped JPEGs with generated capture metadata sidecars:

| Capture | SHA-256 | Scope |
| --- | --- | --- |
| `captures/home-missing-row.jpeg` | `c5294cfba9b33f30ff7b72b1629606be2c97bd6bbcf9c09533e9a3cec3b76d46` | Disabled missing saved project row and warning state. |
| `captures/home-missing-recovery-menu.jpeg` | `ab235ab06ab4b4d4ce38c74cd9adac509d77bbd37dbe88c32680affd1b728592` | `Retry saved location` and `Locate moved item…` menu. |
| `captures/home-relocated-row.jpeg` | `3b2ce409ebebd679b9178ffe21950eec5f66186186257d91bddfada9fee299fc` | Enabled `New Project` row after `Use this location`. |
| `captures/help-v150-en.jpeg` | `c97d66a609fe55b241a7e890f3ec64024666af476e7982f33126b32b204300d5` | English Guide v150, chapter 7. |
| `captures/help-v150-es.jpeg` | `6289137b2ad6e67d276ed965824aa49bf74bc56524abe5c5ba3200bc52e0f7d8` | Spanish Guide v150, chapter 7. |

Every capture is `2520x1700`, marked as a synthetic-data viewport capture,
and was taken from the isolated QA app window. No user data, project, Sync
grant or real preference was used or changed. The capture context files and
`.jpeg.json` metadata preserve the observed route, state, timestamp and Git
source identity.

The final process reconciliation covered every exact-bundle PID present in
the durable startup logs or observed during the task:

| PID | Evidence and role | Final state |
| --- | --- | --- |
| `30766` | `app.log`, direct non-isolated startup at 01:00:20 CET; reached `application_ready` | Exact bundle absent at final check; quit method not attributed. |
| `32201` | `app-isolated.log`, valid isolated packaged QA at 01:02:03 CET; reached `application_ready` | Native application-menu quit was used for this isolated flow; exact bundle absent at final check. |
| `32723` | `app-envcheck.log`, environment-control process at 01:02:47 CET; no `application_ready` | Exact bundle absent at final check; quit method not attributed. |
| `33207` | Coordinator `ps` observation at 01:03:29 CET; no durable startup log or launch command | Exact bundle absent at final check; provenance and quit method unknown, so neither is claimed. |
| `36725` | Coordinator `ps` observation at 01:07:16 CET; no durable startup log or launch command | Exact bundle absent at final check; provenance and quit method unknown, so neither is claimed. |
| `39722` | Exact-bundle `ps` observation at 01:09:12 CET after a CUA rebind; no durable startup log | Exact bundle absent at final check; provenance and quit method not attributed. |
| `43997` | Focused visual retake launched at 01:15:23 CET with the isolated `open -n -a` flow; native Home window reached | Native application-menu quit issued; exact PID and bundle/helper absence verified at 01:19:53 CET. |
| `94241` | Exact candidate `launch.sh --qa` process started at 09:52:47 CET; reached `application_ready`; Home and Help evidence above | Native application-menu quit issued at 10:07:43 CET; exact PID, bundle and task-owned helper absent at final check. |

No `LeonardoMDQA.app` process or task-owned `LeonardoSyncHelper` remained at
the final exact-path check (`2026-11-26T10:07:43+01:00`). PID `94241` was
verified absent without a force-kill or name-wide termination. The synthetic
fixtures and isolated package were left intact for hash and audit reproduction.

## Current-main CI regression triage

After rebasing the draft onto current `origin/main` `727a7446`, macOS job
`139604476331` exposed a host-dependent regression in
`SavedItemAvailabilityTests.testDocumentRecentReplacementRemovesStaleAndDuplicateDestinationPaths`:
the test changed the process-global AppKit `NSDocumentController` recent store
and read it immediately, so the hosted store could still be empty. This was a
test-environment dependency, not a relocation defect. Production behavior still
uses the native AppKit store through `AppKitRecentDocumentStore`.

The focused regression now injects an in-memory `RecentDocumentStore`, retaining
the same stale-source removal, destination deduplication and ordering contract
without touching host recents or preferences. The recorded command
`python3 scripts/compile-and-record.py --pr-number 516 -- swift test --filter
'(SavedItemAvailabilityTests|SavedItemRecoveryPersistenceTests)'` passed all
5 tests; the PR ledger is at build delta 18. Full current-head CI remains the
authoritative suite gate.

## Current-main reconciliation and final native QA

The draft was subsequently rebased onto `origin/main` `32efc6f2`, which
includes merged PR #499 and its Guide v146 table-pagination baseline. The
exact v146 packages were retained in the repository:

| Locale | Guide v146 SHA-256 |
| --- | --- |
| English | `3b863449ff6fe5cbc1051b7fe57bb3fb823b0ae818c234aa61c97030274a1489` |
| Español | `a063da2b8f0a6a30afecaeea56cdf8012bf2d0ef135a9110a9211e642577c480` |

Guide v150 was regenerated from the combined current bilingual sources, so the
candidate retains both #499 table-pagination content and #514 Home recovery:

| Locale | Guide v150 SHA-256 |
| --- | --- |
| English | `0e17463a0052718973fde8591255226bb9ec9f0e27d1f2ef2686e438b748e9f4` |
| Español | `2e344eb7e182afb2d44f02a3a077b459b6e003a9b4c8ba1e4da5c557cf6d8ddd` |

Deterministic package validation, focused Swift checks and the native retake
are all tied to the exact candidate source above. The candidate therefore
retains the #499 Guide v146 baseline and the #514 Home recovery behavior while
providing current packaged evidence for both Home relocation and bilingual
Guide v150. The draft remains subject to its current CI and strict review
gates; this record does not mark it ready or merge it.
