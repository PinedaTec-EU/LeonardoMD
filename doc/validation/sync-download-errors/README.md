# Project-download error validation

Tracking: [#368](https://github.com/PinedaTec-EU/LeonardoMD/issues/368), [PR #369](https://github.com/PinedaTec-EU/LeonardoMD/pull/369).

The `b19ed7b` / Guide v73 and `current-head-2026-11-13` capture sets are
historical. The retained bilingual HTTP 413 screenshots in
[exact-head-44c1ae4d-2026-11-13](exact-head-44c1ae4d-2026-11-13/README.md)
show the separate size-limit alert. The new bilingual HTTP 403 recovery
screenshots are in
[http403-access-denied-caf23aeb-20261113](http403-access-denied-caf23aeb-20261113/README.md)
are retained as the earlier status-only state. The latest bilingual HTTP 403
captures are in
[http403-access-denied-cd149200-20261113](http403-access-denied-cd149200-20261113/README.md)
and show the bounded operation/status reference from source
`cd1492005e5178c5e7e7b87bf3a0e305b7ab2e18`. The Guide v76 packaged-app
record is in `../user-guide/native/guide-v76-20261113.json`; it includes the
Spanish Math-on equation/tag check and Spanish practice/save round-trip
completed in the QA instance on 2026-11-13.

## Candidate identity

- The HTTP 413 alert source is `44c1ae4d6ddc17af5dda791eb45b3a0036a78157`; the Guide v76 validation source is `6b83c502bbe5c9b67b7ebf75ee1fb79acab98caf`.
- The latest HTTP 403 capture source is `cd1492005e5178c5e7e7b87bf3a0e305b7ab2e18`; the compiler-recorded PR build delta is 47.
- The historical 413 capture manifest binds `Sources`, `Tests`, package manifests, scripts, version and PR entry to its source. Verify that historical binding with:

```sh
python3 - <<'PYVERIFY'
import json, subprocess
from pathlib import Path
binding = json.loads(Path('doc/validation/sync-download-errors/exact-head-44c1ae4d-2026-11-13/build-inputs.json').read_text())
for path, expected in binding['input_objects'].items():
    actual = subprocess.check_output(['git', 'rev-parse', 'HEAD:' + path], text=True).strip()
    assert actual == expected, path
print('All recorded runtime and build inputs match HEAD')
PYVERIFY
```

## Native captures

The production macOS preferences view displayed a synthetic authorized HTTP 413 corpus-size failure. The English and Spanish screenshots show the HTTP status, observed and allowed sizes, affected relative file, recovery guidance and confirmation button. The complete 600×532-point native window is visible in each 1200×1064 image. The opt-in XCTest capture passed for both languages on source `44c1ae4d`.

The capture is synthetic and uses the production `DesktopPeerPreferencesView` fixture through `swift test`; it is not a user project, live peer connection or packaged startup test. Context sidecars identify the native AppKit/SwiftUI route, viewport, locale, capture time and source. Canonical metadata sidecars bind both image SHA-256 values to the clean `b19ed7b` source checkout.

- [English screenshot](download-error-en.png) · [metadata](download-error-en.json) · [capture context](download-error-en.context.json)
- [Spanish screenshot](download-error-es.png) · [metadata](download-error-es.json) · [capture context](download-error-es.context.json)

Capture command on the recorded built source:

```sh
EVIDENCE_SHA=b19ed7b1f73c142914811c4b67678d610d3d498a \
LEONARDO_SYNC_ERROR_EVIDENCE=/tmp/leonardo-sync-errors \
swift test --skip-build --filter PeerSyncErrorMessageTests.testCaptureProductionDownloadAlert
```

## HTTP 403 recovery captures

The latest production macOS synchronization-preferences captures show the
localized neutral recovery plus the bounded reference
`[LL1 op=file http=403]` when the source denies a file request but fresh STATUS
does not identify a revocation or grant change. The alert does not guess which
authorization changed. OCR verified the recovery, operation, HTTP status and
confirmation button in both languages. They contain no device, project,
credential or document details. The former status-only captures remain linked
above as historical evidence.

| Locale | Native window | Capture and metadata | SHA-256 |
|---|---:|---|---|
| English | 600 × 532 pt | [image](http403-access-denied-cd149200-20261113/access-denied-en.png) · [metadata](http403-access-denied-cd149200-20261113/access-denied-en.json) · [context](http403-access-denied-cd149200-20261113/access-denied-en.context.json) | `26d81115b4484a41184905f710b880a7ce05f745c71810d6b90d7dc5b26973a7` |
| Spanish | 600 × 532 pt | [image](http403-access-denied-cd149200-20261113/access-denied-es.png) · [metadata](http403-access-denied-cd149200-20261113/access-denied-es.json) · [context](http403-access-denied-cd149200-20261113/access-denied-es.context.json) | `596dca8614aecb14452dd6143df668b2bdca6d015447ec4ddfcb039941735d99` |

The 1200 × 1064 px captures were rendered by
`PeerSyncErrorMessageTests.testCaptureProductionAccessDeniedAlert` in the
production `DesktopPeerPreferencesView` using source commit
`cd1492005e5178c5e7e7b87bf3a0e305b7ab2e18`. See
[build-inputs.json](http403-access-denied-cd149200-20261113/build-inputs.json)
for tree bindings and the compiler-recorded build delta `47`. The artifact
commit is evidence-only; the manifest maps it back to the exact capture source.
These are desktop captures, not Little Leonardo simulator or TestFlight
acceptance.

## Packaged Help acceptance

The Guide v76 QA record identifies the fresh app processes, version `0.3.1602` / build `1602`, both bundled guide hashes and real Help opens. Live inspection covered the local cover and images, Mermaid, Vega-Lite, tables, one-line and multiline equations, Markdown-sensitive underbraces, radicals, arrows, cancellation and tagged box-counting equation `(1)` in both locales. English and Spanish Math-off views showed literal source fallback; a fenced BibTeX example stayed literal. The English and Spanish practice forms were each filled with fictional values, saved, closed, reopened from the corresponding guide and verified to retain their answers.

The final Spanish checks ran on 2026-11-13 in QA bundle `eu.pinedatec.LeonardoMD.qa.514fb956b10e4a3fb82b8433b1cdfadd`, version/build `0.3.1602/1602`, in the dedicated home `/tmp/leonardo-guide-v76-qa-home`. The language and Math preferences were restored to English and on in that isolated home. Device Hub remained running. No screenshot artifact was retained from the CUA screenshots; the evidence is the observed packaged-app UI and persisted form file hash recorded in the JSON manifest. The macOS help smoke is complete; this does not establish Little Leonardo simulator or TestFlight acceptance.

## Scope and automated coverage

The snapshot route preserves structured HTTP 413 limit responses and sanitized source-read diagnostics. Catalogue and file routes keep empty HTTP 413 responses. When a project request returns HTTP 403, mobile and desktop clients refresh authenticated status: confirmed device revocation triggers local cleanup, a withdrawn project grant remains project-scoped, a removed file selection stays outside scope, and an unknown cause preserves its operation/status without claiming revocation. Mobile access denials never return retained stale bytes as a successful open; confirmed desktop device revocation immediately hides every reader cache for that connection. Swift regressions cover those races, malformed/older response bodies, partial-read behavior, scope filtering, privacy and localized user guidance. Deterministic package tests cover both guides.

This PR keeps the whole-snapshot transfer limit. It does not claim to identify the original HTTP 500 cause or to fix the physical large-image synchronization tracked by #380. It also does not claim Little Leonardo simulator or TestFlight acceptance; issue #368 remains open for the owner's original import failure.

The prior [candidate-8ceafc](candidate-8ceafc/README.md) captures are retained as superseded history and are not used for current acceptance.
