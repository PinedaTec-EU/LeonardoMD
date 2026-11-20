# CI suite selection

The Actions **CI plan** summary lists changed paths, requested labels and
scheduled suites. The `test` check passes when planning succeeds, every
scheduled suite succeeds and every intentionally omitted suite is skipped.
The central release ledger and evidence checks run independently.

| Changed surface | Product suites |
| --- | --- |
| Little Leonardo sources or tests under `Mobile/` | iOS |
| Little Leonardo legal resources | iOS and packaging |
| LeonardoMD application sources, assets or bundled guide sources | macOS and packaging |
| Desktop XCTest paths | macOS |
| Shared native Swift sources, rendering or synchronization | macOS, iOS and packaging |
| Canonical format examples, schemas or cross-format fixtures | All |
| Agent plugin manifests, skill and standalone tests | Plugin |
| Agent plugin scripts or bundled schema used by the guides or macOS tests | Plugin, macOS and packaging |
| Packaging tests, generated web guides or sync-helper evidence checked by packaging tests | Packaging |
| Recognized maintainer prose and PR ledger entries | No product suite |
| Workflow, scripts, package manifests and unclassified paths | All |

Mixed changes use the union of the affected suites. Renames and copies include
both paths. An unavailable, empty, stale, or potentially truncated comparison
runs all suites. Product CI also schedules every suite for pushes to `main`.

Use PR labels `ci:macos`, `ci:ios`, `ci:package` and `ci:plugin` to add individual
suites. `ci:full` schedules all suites. Labels are read when the planning job
runs. Adding or removing a label does not launch product CI on its own.
After changing labels on an existing run, select **Re-run all jobs** and confirm
the new plan in the run summary before relying on the additional checks.
