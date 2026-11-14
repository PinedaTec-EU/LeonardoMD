# Current-source alert captures

Tracking: [#368](https://github.com/PinedaTec-EU/LeonardoMD/issues/368), [PR #369](https://github.com/PinedaTec-EU/LeonardoMD/pull/369).

## Capture source

The English and Spanish production alert captures were made from source revision `e1ad1d2ada9e7a7b05066b26a229e038c416f069`, version `0.3.1596`, with Xcode 27.1 / Swift 6.4 on macOS. The opt-in `PeerSyncErrorMessageTests.testCaptureProductionDownloadAlert` passed for both locales: 1 test, 0 failures. It hosted the production `DesktopPeerPreferencesView` in a native AppKit window and injected a synthetic HTTP 413 corpus-size failure.

The successful command was:

```sh
EVIDENCE_SHA=e1ad1d2ada9e7a7b05066b26a229e038c416f069 \
LEONARDO_SYNC_ERROR_EVIDENCE=/tmp/leonardo-sync-error-evidence-20261113-369 \
python3 scripts/compile-and-record.py --pr-number 369 -- swift test \
  --filter PeerSyncErrorMessageTests.testCaptureProductionDownloadAlert
```

The command started with PR build delta `36`; after the successful test, the canonical recorder advanced it to `37` in commit `958a57ea625faf6884a32a1ed2b51a63a1246c87`. That commit changes only the build counter in `deploy/version/entries/369.yaml`. A later bookkeeping commit aligned that entry's release summary with the PR body; the runtime, test, package, script and version inputs stayed unchanged. [build-inputs.json](build-inputs.json) binds those captured source inputs. Verify them against the reviewed PR head before relying on the capture.

## Captures

The visible dialog identifies the project-download failure, HTTP status, transfer limit, relative test file and recovery action. The fixture contains no live endpoint, credential, project ID or user document. Images are original viewport captures; browser/CSS dimensions do not apply.

| Locale | Native window | Image | Capture time (UTC) | SHA-256 |
|---|---:|---|---|---|
| English | 600 × 532 pt | [download-error-en.png](download-error-en.png) · [metadata](download-error-en.json) · [context](download-error-en.context.json) | 2026-11-13 12:42:47 | `9ffae12d200b4deaa67f96f05fc6851b8721a6eee4ff10884cd2cfe83f035852` |
| Spanish | 600 × 532 pt | [download-error-es.png](download-error-es.png) · [metadata](download-error-es.json) · [context](download-error-es.context.json) | 2026-11-13 12:42:49 | `fced6a9687fe9110375b5aed6158b2a875dd28c017f6444d098f3c47ebf58011` |

Each image is 1200 × 1064 px. The metadata sidecars were generated with the shared `capture_metadata.py` helper after the ledger-only build-recording commit. They identify revision `958a57ea625faf6884a32a1ed2b51a63a1246c87`; at collection, the only untracked files were these evidence artifacts. The screenshot context independently records the actual capture time and source revision `e1ad1d2ada9e7a7b05066b26a229e038c416f069`.

These synthetic component captures establish dialog rendering and localization. They do not claim a fresh packaged-app launch, a live Mac-to-Mac transfer, resolution of the original HTTP 500, or physical/TestFlight acceptance. The complete current-source Help and practice-form acceptance is recorded in the PR validation body.
