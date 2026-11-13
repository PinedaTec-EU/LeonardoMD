# Project-download error validation

Tracking: [#368](https://github.com/PinedaTec-EU/LeonardoMD/issues/368), [PR #369](https://github.com/PinedaTec-EU/LeonardoMD/pull/369).

## Candidate identity

- Runtime, guide and capture source: `b19ed7b1f73c142914811c4b67678d610d3d498a`.
- PR build delta: 32. Both packaged guides are Guide v73, regenerated from the combined Spanish and English sources after current `main` was merged.
- The following commit updates validation records and screenshots only. [build-inputs.json](build-inputs.json) binds `Sources`, `Tests`, package manifests, scripts, version and the PR ledger entry to the captured source. Verify the binding at the reviewed head with:

```sh
python3 - <<'PYVERIFY'
import json, subprocess
from pathlib import Path
binding = json.loads(Path('doc/validation/sync-download-errors/build-inputs.json').read_text())
for path, expected in binding['input_objects'].items():
    actual = subprocess.check_output(['git', 'rev-parse', 'HEAD:' + path], text=True).strip()
    assert actual == expected, path
print('All recorded runtime and build inputs match HEAD')
PYVERIFY
```

## Native captures

The production macOS preferences view displayed a synthetic authorized HTTP 413 corpus-size failure. The English and Spanish screenshots show the HTTP status, observed and allowed sizes, affected relative file, recovery guidance and confirmation button. The complete 600×532-point native window is visible in each 1200×1064 image. The opt-in XCTest capture passed for both languages on the recorded source.

The capture is synthetic and uses the production `DesktopPeerPreferencesView` fixture through `swift test`; it is not a user project, live peer connection or packaged startup test. Context sidecars identify the native AppKit/SwiftUI route, viewport, locale, capture time and source. Canonical metadata sidecars bind both image SHA-256 values to the clean `b19ed7b` source checkout.

- [English screenshot](download-error-en.png) · [metadata](download-error-en.json) · [capture context](download-error-en.context.json)
- [Spanish screenshot](download-error-es.png) · [metadata](download-error-es.json) · [capture context](download-error-es.context.json)

Capture command on the recorded built source:

```sh
EVIDENCE_SHA=b19ed7b1f73c142914811c4b67678d610d3d498a \
LEONARDO_SYNC_ERROR_EVIDENCE=/tmp/leonardo-sync-errors \
swift test --skip-build --filter PeerSyncErrorMessageTests.testCaptureProductionDownloadAlert
```

## Packaged Help acceptance

A fresh QA app process (`eu.pinedatec.LeonardoMD.qa.92ec8dd194434068b2b275db42584a1b`, version `0.3.1596`) opened the bundled Spanish and English Guide v73 through the real Help menu. Mermaid, inline and display math, one-line and multiline `$$`, the tagged box-counting equation `(1)`, charts, local images and tables rendered. With Math disabled, TeX stayed literal; code examples stayed literal and no KaTeX error or stray formula delimiter appeared. Math was restored afterward.

The Spanish and English Help-linked practice forms were opened, filled, saved, closed and reopened in that same instance; their values and checkbox state persisted. Original practice values were restored and verified after the checks.

## Scope and automated coverage

The reader and router changes preserve structured HTTP 413 limit responses on whole-snapshot and on-demand routes, keep source read failures distinct and sanitized, and return HTTP 403 without project diagnostics after grant revocation. Swift regressions cover those routes, malformed/older response bodies, partial-read behavior, scope filtering, privacy and localized user guidance. Deterministic package tests cover both regenerated guides.

This PR keeps the whole-snapshot transfer limit. It does not claim to identify the original HTTP 500 cause or to fix the physical large-image synchronization tracked by #380. No physical two-Mac transfer or TestFlight acceptance is claimed here; issue #368 remains open for the owner's original import failure.

The prior [candidate-8ceafc](candidate-8ceafc/README.md) captures are retained as superseded history and are not used for current acceptance.
