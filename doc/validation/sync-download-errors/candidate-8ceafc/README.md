# Reconciled project-download error candidate

Tracking: [#368](https://github.com/PinedaTec-EU/LeonardoMD/issues/368), [PR #369](https://github.com/PinedaTec-EU/LeonardoMD/pull/369).

## Candidate and build binding

- Reviewed PR head: `8ceafc430d51e26868199228ad4887fab1872662`.
- The captured test binary was built at parent `8418da47a8e8d27610bae6ce9d734b505218a638`; the only change from that build to the reviewed head is the compilation ledger delta in `deploy/version/entries/369.yaml`. Runtime source, test sources, manifests, scripts and version inputs are unchanged.
- [build-inputs.json](build-inputs.json) records the reviewed head and Git tree objects for those inputs.

## Native alert captures

The production `DesktopPeerPreferencesView` displayed a synthetic, authorized HTTP 413 corpus-size error. The English and Spanish captures show the response, available quantities, transfer limit, relative file path and recovery action. The focused opt-in capture passed at the recorded candidate build:

```sh
EVIDENCE_SHA=8ceafc430d51e26868199228ad4887fab1872662 \
LEONARDO_SYNC_ERROR_EVIDENCE=/tmp/leonardo-sync-errors-369-current \
swift test --skip-build --filter PeerSyncErrorMessageTests.testCaptureProductionDownloadAlert
```

Both screenshots were inspected. The test's OCR checks require HTTP 413 and the localized confirmation action. Sidecars were generated with the shared capture-metadata helper after the capture; they preserve capture time, measured native-window size, image dimensions, SHA-256 and the reviewed source revision.

| Locale | Capture | Metadata | Result |
|---|---|---|---|
| English | [download-error-en.png](download-error-en.png) | [download-error-en.json](download-error-en.json) | HTTP 413, quantities, transfer limit and recovery action visible |
| Spanish | [download-error-es.png](download-error-es.png) | [download-error-es.json](download-error-es.json) | HTTP 413, quantities, transfer limit and recovery action visible |

## Packaged Help acceptance

The fresh QA instance `eu.pinedatec.LeonardoMD.qa.1a239f8d89cf46ac8db4f854f34e8994` ran version `0.3.1371`, with packaged Guide v68. From its real Help menu, both English and Spanish guides opened. Mermaid, inline and display math (including one-line and multiline `$$`, Markdown-sensitive underbraces and tagged equation `(1)`), charts, local images and tables rendered. With Math disabled, delimiters and code examples remained literal; Math was restored afterward.

The Help-linked practice document could not be opened because another LeonardoMD instance held the source document. No running user instance was closed. An isolated, byte-identical temporary copy of `doc/guide/es/practice.mdlr` was opened in the same QA app, filled with synthetic data, saved, closed and reopened; the answer and checkbox persisted. The source document was not modified. This validates form persistence in the isolated copy, while the exact Help-link workflow remains pending.

## Other validation

- `python3 -m unittest discover -s scripts/tests -p 'test_package_user_guide.py' -v`: 3 passed after reconciling the guides with current `main`.
- Recorded focused Swift checks on the reconciled candidate: 11 HTTPS transport, 7 HTTP transport, 5 project corpus reader, 5 bundled guide, and 4 peer-sync error-message tests passed; one unrelated screenshot test was skipped.
- `git diff --check origin/main...HEAD` passed before this evidence-only update.

No physical iPhone synchronization, TestFlight distribution, or successful large-image transfer is claimed. Those remain separate acceptance for #380.
