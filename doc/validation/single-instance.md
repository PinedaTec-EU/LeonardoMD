# Single-instance launches

Tracking: [#22](https://github.com/PinedaTec-EU/LeonardoMD/issues/22).
Dependency: [PR #21](https://github.com/PinedaTec-EU/LeonardoMD/pull/21), document tabs. The owner authorized this sequence. PR #21 is integrated in main; this PR now targets main and includes About, startup diagnostics and native drop-provider corrections. Current-head CI, process validation and strict judgment must pass before merge.

## Behavior

LeonardoMD elects one editor per product, including copies with different bundle identifiers in the current login session. A named Core Foundation message port is claimed before the application event loop starts. Competing executables forward their paths (or an empty activation request), wait for an acknowledgement and exit. The kernel releases ownership on process exit or crash. No filesystem lock or stale PID cleanup is needed.

Normal Launch Services reopen and document events join the same queue. Reopen restores the active window from minimization. External documents open in new tabs; documents already open in any window activate their existing tab. Existing blank tabs are retained. New windows are still available within the same process.

Requests arriving before launch finishes are queued; batches are processed in order. Requests during a tab/window close wait for that close to finish. Reply-bearing transport is serialized on a dedicated DispatchQueue because CFMessagePort caches each process’s remote endpoint; see [#23](https://github.com/PinedaTec-EU/LeonardoMD/issues/23). Forwarding runs off the UI thread with bounded send/reply timeouts of ten seconds each. Its acknowledgement confirms that the owner accepted the request into its queue, not that file loading succeeded. Existing editor error presentation handles file loading errors. An unavailable or unresponsive owner produces an error and a failing secondary exit, never a second editor.

Direct executable launches accept document paths. Finder supplies its documents through application open events. Existing versions without this protocol must be quit before starting the updated version; this change does not terminate older editors or recover their state.

## Validation

- `swift test --filter 'SingleInstanceTests|DocumentTabsTests'` exercises owner election, acknowledged empty/path requests, release and reacquisition, missing-owner failure, concurrent forwarding, dirty-tab preservation and repeated file deduplication.
- `swift test` includes the complete core, application and real WebKit integration suites.
- `./scripts/build-app.sh` packages and ad-hoc signs the release app.

Native process checks on 2026-10-07 used the packaged release executable copied to a QA bundle (`eu.pinedatec.LeonardoMD.qa22`) with synthetic files in `/private/tmp/leonardo22-qa`. That historical QA isolation used the old bundle-specific namespace; it no longer applies. Updated QA must quit its own owner gracefully and never assume a changed bundle identifier creates an isolated editor. The application code was unchanged; only the QA bundle identifier/name and ad-hoc signature differed.

1. Started `first.md` in the owner, then launched four simultaneous secondaries: activation only, `second.md`, `third.md`, and repeated `second.md`. All secondaries exited 0; only owner PID 10313 remained. Native accessibility inspection showed each of the three files once, plus the initial empty tab.
2. Minimized the QA window and reopened its app through Launch Services. Forced another process with `open -n -a <QA app> finder.md`; the native tree showed `finder.md` selected in a new tab in the restored owner window. This exercises the same application-open event used by Finder document launches.
3. With no QA owner, launched four processes concurrently, each with a different document. PID 12940 remained; PIDs 12941–12943 exited 0. Native inspection of the live winner showed all four documents exactly once, plus its initial empty tab. The launching harness remained alive during inspection to avoid its process cleanup terminating the winner.

No existing user editor was closed for these checks. Real Finder association/default-app changes were unnecessary. Double-click with Leonardo selected as the document handler uses the validated Launch Services event path.

After the #23 transport correction, the final release binary was rebuilt and the cold-start race was repeated: owner PID 17418 remained, while PIDs 17417, 17419 and 17420 exited 0. Native inspection again showed all four requested files once. Empty direct reopen and repeated `first.md` launches exited 0; a forced Launch Services process opened `final-launch-services.md` as the fifth document tab in the same owner. That historical validation passed 63 tests; it predates main integration and is not current-head acceptance. The refreshed integrated suite passes 84 tests (74 XCTest plus 10 Swift Testing), including twelve concurrent IPC requests. Release packaging and ad-hoc signing passed.

During integration, hosted CI exposed [#35](https://github.com/PinedaTec-EU/LeonardoMD/issues/35): Git subprocess completion could race the final stream callback. The corrective revision waits for independent stdout/stderr EOF readers before completion; exact-output, large-stream and failed-launch regressions accompany the existing Git integration suite. Historical process evidence above is not current-head acceptance; refreshed process records and captures are attached to PR #24.

## Reopened regression (2026-10-08)

The owner found multiple editors left running from QA. The previous namespace used `Bundle.main.bundleIdentifier`, so renamed QA bundles escaped product ownership. The launch service now has the fixed product identity `eu.pinedatec.LeonardoMD.launch`. Document batches activate the owner again after asynchronous file loading. Existing binaries using their own namespaces must be quit normally once; running code cannot be retroactively changed. Never kill editors to enforce uniqueness, because they may contain unsaved work.

Historical pre-rebase regression validation: 88 tests pass (78 XCTest plus 10 Swift Testing), including 14 focused application tests; release packaging and ad-hoc signing pass. Both `/private/tmp/leonardo22-regression/Owner.app` and `Other.app` were copied from this worktree release binary, with distinct bundle identifiers and identical linked-code UUIDs. Owner PID 83519 retained `first.md`, `second.md`, `third.md`, and `finder.md`; three simultaneous direct secondaries exited 0 and duplicate `second.md` appeared once. A forced Launch Services launch of `Other.app` selected `finder.md` in the owner. An empty secondary launch restored the minimized owner; `NSWorkspace.frontmostApplication` returned PID 83519, and the process inventory showed only that owner for these corrected copies. At that earlier head, literal Finder contextual-menu interaction remained pending because concurrent desktop activity changed the Finder window during inspection; the Launch Services delivery path was verified. The refreshed validation below supersedes that pending result.

Artifact audit: controls and updates QA executable UUIDs matched their worktree packaged binaries, and both worktree heads contain integrated PR #24 (`041c63bd95f6f03f4b8bd4b354109ff3085ad8de`). The tags QA binary contains `SingleInstance` symbols, but its exact source revision was not established. The old tabs executable UUID matched its worktree artifact, whose history does not contain PR #24 and whose binary has no `SingleInstance` symbols. It was quit normally; no unsaved-change dialog was discarded. These older running QA binaries are not evidence for the corrected build.

## Refreshed integrated validation

The runtime was rebuilt after rebasing onto integrated main `612bc40dec21648d30c45dd460df011e3f926dbf`. Validation at runtime source `23e9bcda1e14a352afeaf984611e9ac9f0eda13b` passes 94 tests (84 XCTest plus 10 Swift Testing), 14 focused tests, release packaging/signing and both current-head CI jobs. The subsequent documentation correction changes no runtime or test source; its CI must pass separately.

Both QA bundles were freshly copied from this release executable with identifiers `eu.pinedatec.LeonardoMD.regression22.owner` and `eu.pinedatec.LeonardoMD.regression22.other`. Owner PID 98800 remains after three simultaneous direct secondaries exit 0; `second.md` appears once. Repeated `first.md` activates the existing tab and preserves its pending draft protected by an external-file conflict.

The literal Finder contextual-menu path passed: right-click `finder.md`, select **Open With → Other…**, choose `/private/tmp/leonardo22-regression/Other.app`, and click **Open** with **Always Open With** unchecked. The existing owner selected `finder.md`; `NSWorkspace.frontmostApplication` returned PID 98800. After minimizing the owner, frontmost PID was 5963; an empty secondary launch exited 0, restored the owner, and made PID 98800 frontmost again.

[Implementation-owned captures and native process provenance](https://github.com/PinedaTec-EU/LeonardoMD/pull/43#issuecomment-6048813973) record the runtime source, capture time, bundle identifiers, process inventory, document state and image dimensions. They supersede the historical PID-83519 evidence above and its pending Finder note. Local reproduction uses packaged bundles built from the reviewed runtime, two distinct temporary bundle identifiers, synthetic Markdown files, simultaneous direct executable launches, the Finder **Open With** path, and minimized-owner reopening. Never use an older running QA binary as proof for a new build; quit task-owned QA normally before replacing it.
