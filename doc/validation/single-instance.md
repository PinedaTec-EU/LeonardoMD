# Single-instance launches

Tracking: [#22](https://github.com/PinedaTec-EU/LeonardoMD/issues/22).
Dependency: [PR #21](https://github.com/PinedaTec-EU/LeonardoMD/pull/21), document tabs. The owner authorized this sequence. PR #21 is integrated in main; this PR now targets main and includes About, startup diagnostics and native drop-provider corrections. Current-head CI, process validation and strict judgment must pass before merge.

## Behavior

LeonardoMD elects one editor per app bundle identifier in the current login session. A named Core Foundation message port is claimed before the application event loop starts. Competing executables forward their paths (or an empty activation request), wait for an acknowledgement and exit. The kernel releases ownership on process exit or crash. No filesystem lock or stale PID cleanup is needed.

Normal Launch Services reopen and document events join the same queue. Reopen restores the active window from minimization. External documents open in new tabs; documents already open in any window activate their existing tab. Existing blank tabs are retained. New windows are still available within the same process.

Requests arriving before launch finishes are queued; batches are processed in order. Requests during a tab/window close wait for that close to finish. Reply-bearing transport is serialized on a dedicated DispatchQueue because CFMessagePort caches each process’s remote endpoint; see [#23](https://github.com/PinedaTec-EU/LeonardoMD/issues/23). Forwarding runs off the UI thread with bounded send/reply timeouts of ten seconds each. Its acknowledgement confirms that the owner accepted the request into its queue, not that file loading succeeded. Existing editor error presentation handles file loading errors. An unavailable or unresponsive owner produces an error and a failing secondary exit, never a second editor.

Direct executable launches accept document paths. Finder supplies its documents through application open events. Existing versions without this protocol must be quit before starting the updated version; this change does not terminate older editors or recover their state.

## Validation

- `swift test --filter 'SingleInstanceTests|DocumentTabsTests'` exercises owner election, acknowledged empty/path requests, release and reacquisition, missing-owner failure, concurrent forwarding, dirty-tab preservation and repeated file deduplication.
- `swift test` includes the complete core, application and real WebKit integration suites.
- `./scripts/build-app.sh` packages and ad-hoc signs the release app.

Native process checks on 2026-10-07 used the packaged release executable copied to a QA bundle (`eu.pinedatec.LeonardoMD.qa22`) with synthetic files in `/private/tmp/leonardo22-qa`. This isolates existing editor processes. The application code was unchanged; only the QA bundle identifier/name and ad-hoc signature differed.

1. Started `first.md` in the owner, then launched four simultaneous secondaries: activation only, `second.md`, `third.md`, and repeated `second.md`. All secondaries exited 0; only owner PID 10313 remained. Native accessibility inspection showed each of the three files once, plus the initial empty tab.
2. Minimized the QA window and reopened its app through Launch Services. Forced another process with `open -n -a <QA app> finder.md`; the native tree showed `finder.md` selected in a new tab in the restored owner window. This exercises the same application-open event used by Finder document launches.
3. With no QA owner, launched four processes concurrently, each with a different document. PID 12940 remained; PIDs 12941–12943 exited 0. Native inspection of the live winner showed all four documents exactly once, plus its initial empty tab. The launching harness remained alive during inspection to avoid its process cleanup terminating the winner.

No existing user editor was closed for these checks. Real Finder association/default-app changes were unnecessary. Double-click with Leonardo selected as the document handler uses the validated Launch Services event path.

After the #23 transport correction, the final release binary was rebuilt and the cold-start race was repeated: owner PID 17418 remained, while PIDs 17417, 17419 and 17420 exited 0. Native inspection again showed all four requested files once. Empty direct reopen and repeated `first.md` launches exited 0; a forced Launch Services process opened `final-launch-services.md` as the fifth document tab in the same owner. Final automated validation passed 63 tests (53 XCTest plus 10 Swift Testing), including twelve concurrent IPC requests. Release packaging and ad-hoc signing passed.
