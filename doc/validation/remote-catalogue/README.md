# Remote catalogue design QA

LMB-600 compares the [approved design](approved-design.png) with the packaged app in [English](catalogue-en.jpg) and [Spanish](catalogue-es.jpg). Both use the synthetic LeonardoSyncQA catalogue with one cached Markdown file and Leonardo Classic in light appearance.

The sheet matches the approved layout. It displays the project identity once, puts Done at the upper right, aligns names and availability in two columns, and keeps the project menu in the footer. The outlined document icon is blue for the cached file and the status label uses secondary text. The controls and table use native SwiftUI styles. The native capture bounds cut off the part of the open Spanish menu outside the sheet. The accessibility tree confirmed both menu commands in both languages.

- English catalogue build source: `566f7c47ebd6fce3990574161115ec564e4a2142`. Opened the cached preview, used Back to return to the catalogue, and closed the catalogue with Done.
- Spanish catalogue and bilingual Help build source: `6ff74f488f7d91b7fb9a10f9dba4c156d694f7cf`. The intervening commit only changes the bundled guide revision. Opened Guide v140 from Help in both languages and verified the updated section. Both opened copies matched the corresponding packaged resource by SHA-256.
- Fresh QA processes used the real LeonardoMD executable (0.3.2267) on macOS 27.2.1. PID 9551 started at 12:40:23 CET in `leonardo-native-qa-t_9lfxei/LeonardoMDQA.app`. PID 12805 started at 12:44:18 CET in `leonardo-native-qa-jjiodrzm/LeonardoMDQA.app`. Both were quit normally and their exit was verified. No Device Hub sessions were opened.
- Seven focused Swift tests and three guide packaging tests passed. Manual validation used the available one-file fixture. Folder navigation and visibility were covered by the focused tests. A populated long catalogue and changes to stored offline content were outside this manual run.
