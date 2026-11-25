# Remote catalogue design QA

LMB-600 compares the [approved design](approved-design.png) with the packaged app in [English](catalogue-en.jpg) and [Spanish](catalogue-es.jpg). Both use the synthetic LeonardoSyncQA catalogue with one cached Markdown file and Leonardo Classic in light appearance.

The sheet matches the approved layout. It displays the project identity once, puts Done at the upper right, aligns names and availability in two columns, and keeps the project menu in the footer. The outlined document icon is blue for the cached file and the status label uses secondary text. The controls and table use native SwiftUI styles. The native capture bounds cut off the part of the open Spanish menu outside the sheet. The accessibility tree confirmed both menu commands in both languages.

- English catalogue build source: `566f7c47ebd6fce3990574161115ec564e4a2142`. Opened the cached preview, used Back to return to the catalogue, and closed the catalogue with Done.
- Spanish catalogue and bilingual Help build source: `6ff74f488f7d91b7fb9a10f9dba4c156d694f7cf`. The intervening commit only changes the bundled guide revision. Opened Guide v140 from Help in both languages and verified the updated section. Both opened copies matched the corresponding packaged resource by SHA-256.
- Fresh QA processes used the real LeonardoMD executable (0.3.2267) on macOS 27.2.1. PID 9551 started at 12:40:23 CET in `leonardo-native-qa-t_9lfxei/LeonardoMDQA.app`. PID 12805 started at 12:44:18 CET in `leonardo-native-qa-jjiodrzm/LeonardoMDQA.app`. Both were quit normally and their exit was verified. No Device Hub sessions were opened.
- Seven focused Swift tests and three guide packaging tests passed. Manual validation used the available one-file fixture. Folder navigation and visibility were covered by the focused tests. Changes to offline retention were outside this manual run.

## Long catalogue

The same packaged executable (application source `6ff74f488f7d91b7fb9a10f9dba4c156d694f7cf`) ran as PID 34516, started at 13:13:37 CET in `leonardo-native-qa-p1ijtno9/LeonardoMDQA.app`. The existing synthetic project was temporarily expanded to 40 files. In Preferences → Synchronization → Remote → Browse files, the [initial rows](long-top.jpg) overflowed the viewport. Scrolling exposed [the final row, qa-note-39.md](long-bottom.jpg), while the headings, Done and Project actions stayed visible. Opening the menu at scroll position 1 exposed Keep offline and Release local space. Release local space was disabled because the fixture had no cached file at capture time. No menu command was applied.

QA processes in the two disposable bundles were quit and verified absent. The fixture connection and catalogue index were restored byte for byte. An earlier startup evicted the previous 51-byte synthetic cached blob. No Device Hub sessions were opened.

Guide v140 package and opened-copy SHA-256: EN `04c0c5799c50d967990ae57124bed92752338a68d3347756288e7c987083dc1c`, ES `17b4f6dc8e604185b10cc1f11ad2a3ad132639608fc07fb0dad3107aab257dd1`.

## Reconciliation with main

The v141 guide combines the v139 pairing-token guidance already on main and the new catalogue instructions. The two catalogue view files are byte-for-byte unchanged from the visual QA build, and the upstream change did not alter the catalogue rows, table, or menu. The v141 app was built at `4ddd6152c67211b44556b1409a3d85838c08837c` and launched as PID 40452 at 13:23:16 CET in `leonardo-native-qa-kl02f5i7/LeonardoMDQA.app`. The updated section rendered through Help in both languages and both opened copies matched the bundled resources. The process exited normally and its absence was verified.

Guide v141 SHA-256: EN `04cd377193af8a00b8697e7c419460b8997c2ce574283cc181430af803e3a202`, ES `e65e0c3d525c951c1bad7c24635a51a1f958413271740dca78b57c7147055d7f`. The focused seven Swift tests and three package tests passed on the reconciled source.
