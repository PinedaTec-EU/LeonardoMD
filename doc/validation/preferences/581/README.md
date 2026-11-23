# Preferences header validation for PR #581

On 2026-11-23 the author inspected the English native Preferences sheet at 780 × 780 pt in the packaged QA build 0.3.2196. Only the header regions were captured. The images contain no project names, connections or document data.

| Screen | Capture | Metadata |
| --- | --- | --- |
| General | [PNG](general.png) | [JSON](general.metadata.json) |
| Extensions | [PNG](extensions.png) | [JSON](extensions.metadata.json) |
| Updates | [PNG](updates.png) | [JSON](updates.metadata.json) |
| Synchronization, Share selected | [PNG](synchronization-share.png) | [JSON](synchronization-share.metadata.json) |
| Synchronization, Remote selected | [PNG](synchronization-remote.png) | [JSON](synchronization-remote.metadata.json) |
| Synthetic native share (en) | [PNG](component-share-en.png) | [JSON](component-share-en.metadata.json) |
| Synthetic native remote (en) | [PNG](component-remote-en.png) | [JSON](component-remote-en.metadata.json) |
| Synthetic native share (es) | [PNG](component-share-es.png) | [JSON](component-share-es.metadata.json) |
| Synthetic native remote (es) | [PNG](component-remote-es.png) | [JSON](component-remote-es.metadata.json) |

Both Sync selections retained the same service panel and changed the selected role. The ad-hoc QA helper was unavailable and macOS Keychain access requests from the temporary bundle were denied. The live Remote interaction was exercised and the updated Remote screenshots come from the synthetic native component in both languages. Signed helper operation was outside this layout check.

The packaged app was built from clean source revision `9fdc0baec12372959bbc061f468971486795da4e`; git status was empty immediately before `LEONARDO_SOURCE_PR=581 ./launch.sh --qa`. The recorder changed only the source-PR build delta after compilation. The capture sidecars were generated as the evidence files were collected at that same revision, so they report recorded build accounting and visual evidence changes. The new evidence commit changes only documentation and that pending build delta, which is not a packaged app input before merge. The synthetic native captures record the same revision in their contexts and reproduced the v130 instructional states without replacing any bundled bytes.

| Build input | SHA-256 |
| --- | --- |
| `Sources/LeonardoApp/SyncHelperPreferencesSection.swift` | `455f2ae674b790a235b07ab921debf70177fe3ae9461b42d3880726b288dda29` |
| `Sources/LeonardoApp/Resources/Localization/en.json` | `e17e61f5942140d3ccef4d143682c11eb116e0f70adb97f6f8ff6f45f827960b` |
| `Sources/LeonardoApp/Resources/Localization/es.json` | `e6fbbdf8ef167e169b71657911782a87299553de55d4b2d6956f135b17baf494` |
| `Sources/LeonardoApp/Resources/Guide-v130-en.mdlz` | `69c5ec7e7e2ab01e555bfd7235e523c3301bc8b9c31b3621e5cd731892d4bbfc` |
| `Sources/LeonardoApp/Resources/Guide-v130-es.mdlz` | `808848db0bf224edadaff5d33aceb017d98206a2cdf661e8a3f1a6f9f155c98e` |

To reproduce, run `./launch.sh --qa` from a clean checkout while no other LeonardoMD instance owns the product session, open Preferences with Cmd+, and select each tab. In Synchronization, switch between Share and Remote.

The task-owned QA processes used the leonardo-native-qa-y5le723g/LeonardoMDQA.app bundle. PID 76948 started at 14:00:48, PID 77160 at 14:01:22 and PID 77360 at 14:02:03 local workstation time. All three were gracefully quit and verified absent. Help opened the English and Spanish v130 copies, both matched the bundled bytes, and rendered the scope and shared-switch guidance.

The clean-source recheck began with no LeonardoMD process and opened no Device Hub session. The verified QA bundle `leonardo-native-qa-di8l2sp1/LeonardoMDQA.app` had `CFBundleExecutable=LeonardoMD`, passed the launcher's dependency check (no XCTest linkage), and opened its first window and the Preferences sheet. Exact PID 42332, started at 16:22:25 local workstation time, was gracefully quit and verified absent.

| Guide v130 | Bundled SHA-256 | Help-opened personal-copy SHA-256 |
| --- | --- | --- |
| English | `69c5ec7e7e2ab01e555bfd7235e523c3301bc8b9c31b3621e5cd731892d4bbfc` | `69c5ec7e7e2ab01e555bfd7235e523c3301bc8b9c31b3621e5cd731892d4bbfc` |
| Español | `808848db0bf224edadaff5d33aceb017d98206a2cdf661e8a3f1a6f9f155c98e` | `808848db0bf224edadaff5d33aceb017d98206a2cdf661e8a3f1a6f9f155c98e` |

There were no differences between the opened copies and bundled packages.
