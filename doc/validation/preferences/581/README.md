# Preferences header validation for PR #581

On 2026-11-23 the author inspected the English native Preferences sheet at 780 × 780 pt in the packaged QA build 0.3.2196. Only the header regions were captured. The images contain no project names, connections or document data.

| Screen | Capture | Metadata |
| --- | --- | --- |
| General | [PNG](general.png) | [JSON](general.metadata.json) |
| Extensions | [PNG](extensions.png) | [JSON](extensions.metadata.json) |
| Updates | [PNG](updates.png) | [JSON](updates.metadata.json) |
| Synchronization, Share selected | [PNG](synchronization-share.png) | [JSON](synchronization-share.metadata.json) |
| Synchronization, Remote selected | [PNG](synchronization-remote.png) | [JSON](synchronization-remote.metadata.json) |

Both Sync selections retained the same service panel and changed the selected role. The ad-hoc QA helper was unavailable as expected. The captures do not validate signed helper operation. The English and Spanish guide assets show both roles in synthetic disabled-helper states.

The packaged app was built from the application and final Guide v129 resources in e68f6256f9d498a1b5f6267e6bd8c29110608f68. The author collected these captures at 01a5bfcfcf3fcdc0daf01d438a930a347207542e. The intervening change is restricted to the XCTest host padding and the pending per-PR build count. This evidence commit changes only the validation directory, which is outside the application and package build inputs.

To reproduce, run `./launch.sh --qa` from a clean checkout while no other LeonardoMD instance owns the product session, open Preferences with Cmd+, and select each tab. In Synchronization, switch between Share and Remote.

The task-owned QA instance used the leonardo-native-qa-qbnk961z/LeonardoMDQA.app bundle, PID 68848, started at 13:40:40 local workstation time. Its Preferences sheet was closed, the app was quit normally, and the exact PID was verified absent.
