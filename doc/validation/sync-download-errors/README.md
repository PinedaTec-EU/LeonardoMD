# Project-download error validation

Tracking: [#368](https://github.com/PinedaTec-EU/LeonardoMD/issues/368), [PR #369](https://github.com/PinedaTec-EU/LeonardoMD/pull/369).

## Native captures

The production `DesktopPeerPreferencesView` presents a synthetic authorized HTTP 413 corpus-size failure. Both localizations show the cause, measured bytes/MiB, limit, relative path and recovery action without truncating the text or button. Captured by the opt-in XCTest fixture through `swift test`, not by launching an XCTest executable as an app. No real project, pairing, installation, fresh packaged-process startup or physical two-Mac acceptance is claimed.

Capture source: `38abda384e637e4449e388e9ea6a7f1bddb5db39`. The capture binary matches that committed source; subsequent evidence-only commits change these evidence files, not runtime sources or the guide packages. The PR's implementation evidence comment records the final reviewed head and compilation allocation. Native window viewport, image dimensions, timestamp and OS are recorded in each JSON sidecar; browser/CSS are not applicable.

- [English](download-error-en.png) · [metadata](download-error-en.json)
- [Spanish](download-error-es.png) · [metadata](download-error-es.json)

Reproduce after building the selected head with the repository compilation recorder:

```sh
EVIDENCE_SHA=$(git rev-parse HEAD) LEONARDO_SYNC_ERROR_EVIDENCE=/tmp/leonardo-sync-errors swift test --skip-build --filter PeerSyncErrorMessageTests.testCaptureProductionDownloadAlert
```

Window capture needs local screen-recording permission. This opt-in capture is skipped in ordinary test runs.

## Automated coverage

- Real pinned HTTPS: source corpus limit returns HTTP 413 and structured quantities/path; source filesystem failure returns sanitized HTTP 500; revoked recipients receive HTTP 403 without project diagnostics.
- Reader: file, aggregate and file-count limits stop without returning partial snapshots. Observed quantities are the amount encountered before stopping, not a complete inventory.
- Empty/malformed older-source error bodies retain HTTP status and never invent a size cause or display raw server messages.
- Both UI languages include recovery, quantities and file path; direct local-copy failures also avoid numeric Swift errors.
- Full `swift test` passes with opt-in/environment skips; deterministic guide-package tests pass. Bundled guides render in both languages through WKWebView.

## Remaining scope

Whole-snapshot size limits remain. This diagnostic correction neither attributes the owner's original HTTP 500 to size/cloud placeholders nor implements bounded per-file synchronization. Large-project work must address manifests, consistent revisions, file-backed copy/base/comparison state, uploads, persistence, progress/cancellation and retries together.
