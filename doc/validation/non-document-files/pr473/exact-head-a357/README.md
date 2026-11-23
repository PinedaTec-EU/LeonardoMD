# PR #473 exact-source capture record

These native captures document the non-document-file preference on source
`a357aaeb0dbc4f7cf4f1fbf4f5ca3e0c6080dde0` (product code for PR #473). The
subsequent PR commit adds evidence and a compilation-ledger entry only. All
fixture content is synthetic; no user documents are shown.

## Captures

| Platform | Capture | Result |
| --- | --- | --- |
| Little Leonardo | [Preference off](ios-settings-off.jpg) · [metadata](ios-settings-off.metadata.json) | Off by default; non-document rows stay hidden. |
| Little Leonardo | [Preference on](ios-settings-on.jpg) · [metadata](ios-settings-on.metadata.json) | Opt-in switch can be enabled. |
| Little Leonardo | [Demo documents while off](ios-demo-documents-off.jpg) · [metadata](ios-demo-documents-off.metadata.json) | `Demo-es.mdlr` and `Demo-en.mdlr` remain available with the filter off. |
| LeonardoMD macOS | [Preference off](macos-settings-off.jpg) · [metadata](macos-settings-off.metadata.json) | Global setting is off by default. |
| LeonardoMD macOS | [Preference on](macos-settings-on.jpg) · [metadata](macos-settings-on.metadata.json) | The same global setting can be enabled. |
| LeonardoMD macOS | [Files hidden; Markdown image still renders](macos-files-off-image-still-renders.jpg) · [metadata](macos-files-off-image-still-renders.metadata.json) | Only `Readme.md` is listed; its `green-square.png` image renders, and the received document is read-only. |
| LeonardoMD macOS | [Image file shown](macos-files-on-image-listed.jpg) · [metadata](macos-files-on-image-listed.metadata.json) | `Readme.md` and `green-square.png` are both listed; the image still renders. |

The macOS app was LeonardoMD QA `0.3.1884` / build `1884`, bundle
`eu.pinedatec.LeonardoMD.qa.7fd3c7cb1cf34e5ea21aade757c235d1`, PID `69539`
(started 2026-11-18 13:59:42 Europe/Madrid). The iOS app was Little Leonardo
`0.3.1884` / build `1884`, bundle `eu.pinedatec.LittleLeonardo`, PID `62337`,
on iPhone 17e / iOS 27.0 simulator
`BAFCF426-B9C8-4514-A18E-CB1BE99139EE` (started 2026-11-18 13:53:54
Europe/Madrid). Screenshots show the Spanish interface. Each sidecar records
the image dimensions, SHA-256, state, process and source revision. For iOS the
optimized screenshot timestamp was not retained by XcodeBuildMCP; the sidecar
records when the image was staged in this evidence directory.

## Packaged Help and practice acceptance

Guide v98 Spanish and English were opened from the real Help workflow in that
same packaged macOS QA process. Both locales were inspected with Math enabled
for Mermaid, inline math, one-line and multiline `$$` display formulas,
underscores and underbraces, the tagged box-counting equation `(1)`, Vega
charts, local images and tables. No KaTeX errors or literal math delimiters
appeared. With Math disabled, the source notation remained readable and code
examples stayed literal. The separate Spanish and English practice forms were
each opened, filled, saved, closed and reopened; the original practice data
and app preferences were restored afterward. Acceptance used macOS 27.0.1 and
product source `a357aaeb0dbc4f7cf4f1fbf4f5ca3e0c6080dde0`.

The task-owned macOS QA app was quit with Command-Q; PID `69539` and its
`LeonardoMDQA.app` executable were confirmed absent. Little Leonardo was
stopped through XcodeBuildMCP; PID `62337` was confirmed absent. The task-owned
iPhone 17e simulator was shut down and confirmed `Shutdown`. Another
Little Leonardo process on simulator
`E2045815-8A83-4B25-AFD4-1CC7C573BE7E` was left untouched. The global file
visibility preference was restored to off.
