# Startup Preferences after the compact-header update

[PR #91](https://github.com/PinedaTec-EU/LeonardoMD/pull/91) and [issue #90](https://github.com/PinedaTec-EU/LeonardoMD/issues/90). November 23, 2026. Source `7bb998795e64cfc8b17169a82ae57dce9d24db4f`. Build with `LEONARDO_SOURCE_PR=91 ./launch.sh --qa <synthetic-project> <second.md>`. The next commit records build count and QA evidence only. The candidate identifies as 0.3.2205 (build 2205) on macOS 27.2.1 (26B131). Preflight verified the real LeonardoMD executable and dependencies, with no XCTest linkage. No pre-existing LeonardoMD window or task-owned Device Hub session was active at launch.

- PID 79538 at 17:41:54 opened the explicit synthetic document with its first window ready. Verified [on](preferences-on.png) and [off](preferences-off.png) at General → On this Mac, including persisted off state. Normal quit.
- PID 79995 at 17:42:25 launched to an empty window with restoration disabled. Opened Guide v135 through Help in English and Spanish. Confirmed chapter 11 and the new default-on switch text in native WebKit accessibility output. Bundled and personal copy bytes matched in each locale. Re-enabled restoration and quit normally.
- PID 80412 at 17:43:19 launched with no explicit target and restored the selected Guide-v135-en package. Its final snapshot contained the same prior tabs. Normal quit.
- Verified all three PIDs exited. Restored pre-test snapshot state. No Device Hub sessions were opened or shut down.

All candidate processes used `leonardo-native-qa-qgjeebx9/LeonardoMDQA.app/Contents/MacOS/LeonardoMD`. Guide SHA-256: EN `c6a8c5455b10424145c2f74e05160630e1b72d9af042257e208eac71f84f9ef5`, ES `6e7b4e09d0cd4f95611683f29fced617b6c38342abc60084674814836822bbf6`.

The earlier [project and document restoration and explicit precedence tests](../packaged-v128/README.md) also passed. The refresh changes Preferences header and guide assets; session persistence, launch routing and preference controls are identical to the earlier product source.

Bundle identifier: `eu.pinedatec.LeonardoMD.qa.ee07597e11d64143a187bf3e0a31005c`.
