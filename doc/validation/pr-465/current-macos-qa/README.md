# PR #465 · preserved packaged macOS Help smoke

Date: 2026-11-26 CET. This is the preserved native macOS validation of the
reconciled Guide v147 package. The implementation source used to build the
package was `613c24c31e1a83560ea4654175b452ab3b192f25`; the later
`c80f4c03b132f11e46b9287ab82ff7bad400c856` head records the packaging ledger
delta only. The PR head and the QA branch were clean and identical at the
time of validation. After #415 merged, the bilingual sources were reconciled
and repackaged as Guide v156 without repeating this GUI run; this record remains
runtime evidence for the unchanged Little Leonardo chapter only.

## Package identity

The package was prepared with `LEONARDO_SOURCE_PR=465 ./scripts/build-app.sh`
and the recorder recorded build delta 20. The disposable QA copy was made
from the real package with `scripts/qa-bundle.py` and passed
`--verify-only` before launch.

| Property | Observed value |
| --- | --- |
| QA bundle | `/var/folders/_s/khfztzr97kd4049py5k3zsg80000gn/T/leonardo-native-qa-8rns3abc/LeonardoMDQA.app` |
| Bundle identifier | `eu.pinedatec.LeonardoMD.qa.2665985f8582476dad149f3ae0602b50` |
| Executable | `LeonardoMD` (the real product executable) |
| Version / build | `0.3.2318 / 2318` |
| XCTest linkage | None (`otool -L` and package report) |
| Code signing / dependencies | Verified by `qa-bundle.py --verify-only` |
| ReleaseChanges SHA-256 | `1f1d1ba1d3431f9140580099ee7847047dadb84d406d3c424bb0e2bfe40995a8` |

## Native Help flow

The app ran under the isolated profile
`CFFIXED_USER_HOME=/tmp/leonardo-pr465-desktop-7bYbey`, so user-guide copies
and preference changes did not touch the user's profile. The first window
reached the real Welcome screen. The English **Leonardo user guide…** route
opened `Guide-v147-en.mdlz` in Preview/read-only mode. The first open showed
the native disabled-extension recommendation; Mermaid, Math and Charts were
selected and enabled through the explicit consent action. The rendered local
cover and the **Built-in extensions on iPhone and iPad** chapter were visually
inspected, including the guidance for device-local switches, read-only
received documents and offline scope.

The interface language was then changed through Preferences → General →
Language to Español. The Welcome **Guía de Leonardo…** route opened
`Guide-v147-es.mdlz` in Preview/read-only mode. The rendered local cover and
the **Extensiones incluidas en iPhone y iPad** chapter were visually
inspected. The Spanish route used the same v147 package and the previously
consented extension state; no implicit activation or editability was observed.

The personal copies were byte-identical to the bundled resources:

| Locale | Help-created copy | SHA-256 (copy and bundle) | Result |
| --- | --- | --- | --- |
| English | `User Guides/v147/en/Guide-v147-en.mdlz` | `69b9811c51634422a15a1a2ea0203ab21d0ed5b7ab5f10745260537a2b401a82` | `cmp` passed |
| Spanish | `User Guides/v147/es/Guide-v147-es.mdlz` | `da3d046493102110c33bf334fdb707bcd1833231ca881dcb84dd71d9b88ea45a` | `cmp` passed |

The package and personal paths were both under the isolated QA home; no
production Help copy was modified.

The reconciled Guide v156 package also contains the #415 chapter-1 Finder/icon
guidance. Its deterministic package hashes are EN
`3299b5faa869f34d6aa2b2aefeb0068d430b159a5d246d1355c94b4bb25cca32` and ES
`7027ef6d34f631b2d7158eb7d54a5b680073ca8f846c99a815252aec99190fea`. The
real-Finder visual evidence supplied by #415 remains in
`doc/validation/document-icons-415/README.md`; no new desktop launch was made
for this reconciliation.

## Ownership and teardown

The preflight confirmed that the coordinator's earlier QA PID 94241 was
absent. This task created exactly one LeonardoMD QA process:

| PID | Start | Executable | Teardown |
| --- | --- | --- | --- |
| 13267 | 10:08:48 CET | `.../leonardo-native-qa-8rns3abc/LeonardoMDQA.app/Contents/MacOS/LeonardoMD` | Quit from the native application menu at 10:12:28 CET; `ps -p 13267` was empty |

The native log records `application_will_terminate`, approval of termination,
and `Termination complete. Exiting without sudden termination.` No Device Hub
session, simulator or other task-owned app instance was started. No crash was
observed during the fresh-process check or the Help smoke.

This evidence establishes the preserved packaged macOS Help gate for the
Little Leonardo chapter in Guide v147 and the process teardown. It does not
claim a fresh Guide v156 GUI run, Finder acceptance beyond the linked #415
record, physical-device/TestFlight acceptance or the coordinator's fresh judge.
