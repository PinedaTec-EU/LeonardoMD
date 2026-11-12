# PR #430 packaged macOS acceptance

## Candidate identity

- Product source used to build and capture the candidate: `d64a6b841687c4e1b2fee965a49cd909b7ff2168`.
- Candidate build and capture were recorded while PR head was `4f3c4387d7d3fc9e5b9bbf8fdfc09273233376f5`; that head differed from the product source only in `deploy/version/entries/430.yaml`, which recorded build allocation 32. The later PR head integrates released main `0.3.1339` and these evidence records; it does not change the captured product UI.
- App: disposable packaged `LeonardoMDQA.app`; bundle ID `eu.pinedatec.LeonardoMD.qa.05e1e57c74784ba5b66330ccb8e7e1b0`.
- Fresh native process PID `32804`; executable `LeonardoMD`; version/build `0.3.1333 / 1333`.
- OS: macOS `27.0.1` (build `26A434`). The first window became ready in this process; the packaged app launched independently from the previous QA process.

## Bundled Help smoke

Opened both bundled guides from the real Help menu in the same fresh process:

- English: `Guide-v66-en.mdlz`, personal copy `/Users/jmr.pineda/Library/Application Support/LeonardoMD/User Guides/v66/en/Guide-v66-en.mdlz`.
- Spanish: `Guide-v66-es.mdlz`, personal copy `/Users/jmr.pineda/Library/Application Support/LeonardoMD/User Guides/v66/es/Guide-v66-es.mdlz`.
- The bundle and personal-copy SHA-256 values match: EN `542f23298a69db78e0ef1f983cce27ba8d9638190fb3144501ddb1766e31c6e8`; ES `95a36791b6d4848c9606ec790c6b84c48278facdceb55590a010683b53ab77e5`.

Mermaid, Math (KaTeX) and Charts (Vega-Lite) were enabled. In the live guides, the Mermaid diagram, local images, tables and chart rendered. The English and Spanish accessibility trees exposed the rendered one-line and display equations, underbraces, radicals, arrows and cancellation marks, including the tagged box-counting equation `(1)` with no KaTeX error or literal delimiters in the rendered equation. With Math disabled in the Spanish guide, the inline and display TeX source, Markdown-sensitive underscores/underbraces, and `\tag(1)` remained literal. Math was re-enabled afterward.

The Spanish practice form opened from the guide in Fill mode. Fictional answers were saved with `⌘S`, the form was closed and reopened through the guide, and the values persisted. Its original personal copy was restored byte-for-byte afterward; both the saved baseline and restored file have SHA-256 `dcaef10188834457094ecbafa8ff3ceb1996b6188d79ca02869821c9082321c7`. The app language was restored to English; Math is enabled. Neither bundled guide was edited.

## Native capture evidence

The native synthetic acceptance fixture ran against product source `d64a6b841687c4e1b2fee965a49cd909b7ff2168` on macOS `27.0.1` (build `26A434`). The screenshots use synthetic hosts and projects; they do not represent real shared files or a production host. The current PR head's only later change is the build-ledger allocation recorded above.

- [Remote project review](mac/d64a6b84/remote-project-review.png): a linked synthetic host, an incoming project awaiting Add or Ignore, a new file awaiting review, and an accepted project that remains browseable.
- [Sync helper checking](mac/d64a6b84/status-checking.png): red dot and “Checking synchronization status” during the health check.
- [Sync helper online](mac/d64a6b84/status-online.png): green dot remains visible and the status subtitle is hidden once running.

Each capture includes its test-generated `.context.json` and a `.metadata.json` sidecar with source revision, capture time, dimensions and image digest.

## Focused native checks

`swift test --filter 'DesktopPeerNativeAcceptanceTests|SyncHelperControllerTests/testStatusIndicatorStatesDuringHealthCheck'` passed 4 tests: three native acceptance tests and the #421 checking-state test. The run included the pinned-HTTPS offline-catalogue restart regression and native review captures.

`python3 -m unittest discover -s scripts/tests -p 'test_package_user_guide.py'` passed 3 tests. `git diff --check` passed after the evidence record was assembled. CI passed both test jobs, `validate`, and evidence compilation for PR head `4f3c4387d7d3fc9e5b9bbf8fdfc09273233376f5`; `request-policy` was skipped by workflow conditions. The current PR head is validated separately by its own checks.
