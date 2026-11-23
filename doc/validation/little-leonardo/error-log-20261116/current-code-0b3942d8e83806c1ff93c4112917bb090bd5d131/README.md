# Little Leonardo current-source download error evidence — 2026-11-16

This bundle records bilingual native iOS simulator evidence for PR #435's
localized shared-project download status. The test and capture source was
`3f4622791ba3912d5d4f4f520acd5dccf5ab9722`; the current code commit is
`0b3942d8e83806c1ff93c4112917bb090bd5d131`. Both commits have the same Git
tree: the later commit only corrected the issue-linked commit subject. The
full source mapping, test results, simulator identities, capture times and PNG
hashes are in [manifest.json](manifest.json).

## English

`OnDemandSyncUITests/testEnglishSharedDownloadFailureLocalizesVoiceOverCopy()`
passed 1/1 on iPhone 17 Pro / iOS 26.5. It verifies the English file retry
accessibility label and visible project status **“Download failed · will
retry”**, then checks the localized preview notice and matching local
diagnostic reference.

- [Project and file failure status](english-project-failure.png)
- [Inline document error](english-document-error.png)
- [Matching local log entry](english-diagnostic-log.png)

## Español

`OnDemandSyncUITests/testCatalogueContextRetentionAndSeparateCache()` passed
1/1 on iPhone 17 Pro / iOS 26.5. It verifies the localized project failure,
single-action download alert, inline preview error and matching local log
reference while exercising the on-demand cache fixture.

- [Aviso y estado del proyecto](spanish-project-failure-alert.png)
- [Error del documento](spanish-document-error.png)
- [Registro local correspondiente](spanish-diagnostic-log.png)

The Spanish host fixture passed 1/1 with zero snapshot requests. Its audits
record a metadata-only catalogue read and one explicit file fetch:
[metadata-only](fixture-metadata-only.json),
[single-file fetch](fixture-single-file.json), and
[aggregate audit](fixture-completed.json).

The two task-owned QA simulators were Shutdown after validation; process
inspection found no LittleLeonardo process under either device path. The
separate pre-existing iPhone 17 Pro simulator and its app process were left
running. The XcodeBuildMCP test result did not expose app PIDs or start times;
the exact simulator identities and teardown observation are recorded in
[manifest.json](manifest.json).

These are original native app screenshots with synthetic loopback content.
Browser and CSS viewport fields do not apply; the logical viewport was 402 ×
874 native points. No physical camera scan or physical large-image transfer is
claimed. The latter remains open under [#380](https://github.com/PinedaTec-EU/LeonardoMD/issues/380).
