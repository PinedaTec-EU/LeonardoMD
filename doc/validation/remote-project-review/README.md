# PR #430 packaged macOS acceptance

## Candidate identity

- Source code: `f00d7ed9d7d3559ee2eb48783c071f025e2c1730`.
- App: disposable packaged `LeonardoMDQA.app`, bundle ID `eu.pinedatec.LeonardoMD.qa.b0d79956bb2a42d89e7365048f25579b`.
- Process: fresh native process PID `47244`; executable `LeonardoMD`; version/build `0.3.1333`.
- OS: macOS `27.0.1` (build `26A434`). The first window was ready in this process; bundle signature and executable dependencies were inspected, and the app executable did not link XCTest.

## Bundled Help smoke

Opened both guides from the app's real Help menu in this same process:

- English: `Guide-v65-en.mdlz`, packaged copy under `User Guides/v65/en`.
- Spanish: `Guide-v65-es.mdlz`, packaged copy under `User Guides/v65/es`.
- The installed user copies matched the copies in the built app bundle: EN SHA-256 `54b0b7e74324b6eb8979f0cd4dfe9aefcfa825622a6763ab2db4ad021d4045a8`; ES SHA-256 `cc69530516c15d473c2aac909e168007115d2d25b06636ce6bcacaf11d43b793`.

For each guide, Mermaid, Math (KaTeX), and Charts (Vega-Lite) were enabled. The live accessibility tree showed the Mermaid diagram, rendered inline and display equations, chart image, tables, and local images. It showed the tagged box-counting equation number `(1)` without visible TeX delimiters or commands. Math was then disabled for the Spanish guide: the one-line and multiline `$$` formulas, Markdown-sensitive `\\underbrace`, tagged `\\tag(1)` equation, and code examples stayed literal. No KaTeX error or rendered equation remained in that fallback. Math was restored to enabled, and the final English guide was reopened through Help.

The separate English and Spanish practice forms opened in Fill mode. Each used fictional QA answers, was saved with `⌘S`, closed, and reopened. The saved name, goal, and checked/unchecked readiness value were present after reopening. The original guide source files were not edited. Language was restored to English after the run.

## Native capture evidence

The native synthetic acceptance fixture ran against the exact product code source above. Captures are 1904×1304 px, from a 952×652 point viewport; the sync-state captures are 1064×520 px, from a 532×260 point viewport. The fixture uses no real shared files or host.

- [Remote project review](mac/remote-project-review.png): linked host, incoming project awaiting Add/Ignore, new file awaiting review, and an accepted project still browseable.
- [Sync helper checking](mac/status-checking.png): red dot and “Checking synchronization status” during the brief health check.
- [Sync helper online](mac/status-online.png): green dot stays visible and the status subtitle is hidden once running.

Each screenshot has its observed `.context.json` and collected `.metadata.json` sidecars. The capture context records the exact source SHA; metadata records the screenshot dimensions and digest.

## Focused native checks

`swift test --filter 'DesktopPeerNativeAcceptanceTests|SyncHelperControllerTests/testStatusIndicatorStatesDuringHealthCheck'` passed 4 tests: three native acceptance tests and the #421 checking-state test. The run included the pinned-HTTPS offline-catalogue restart regression and the remote review screenshot capture.

`python3 -m unittest discover -s scripts/tests -p 'test_package_user_guide.py'` passed 3 tests. `git diff --check` passed before the evidence record was added; it was rerun after staging this record and its sidecars.
