# Packaged macOS startup restoration

Issue [#90](https://github.com/PinedaTec-EU/LeonardoMD/issues/90) and [PR #91](https://github.com/PinedaTec-EU/LeonardoMD/pull/91). On November 23, 2026, source `1c5fb286d74926fe2315d1be26b15f6dca747b1b` built with `LEONARDO_SOURCE_PR=91 ./launch.sh --qa <synthetic-project> <second.md>`. The subsequent commit `fd66ef0c60e2ff9eca04fe5c82b54d4685eff35a` records the successful build and changes only the PR compilation counter. This validation record changes only files under `doc/validation`.

The executable was `LeonardoMDQA.app/Contents/MacOS/LeonardoMD` in the disposable `leonardo-native-qa-3_bchjh8` bundle. The launch preflight verified the executable, signatures and library dependencies, including absence of XCTest. Bundle ID `eu.pinedatec.LeonardoMD.qa.9fd254112f5349139e2335b19af65b1b`, version `0.3.2196`, build `2196`, macOS 27.2.1 (26B131).

| PID | Local start | Verification |
| --- | --- | --- |
| 36518 | 12:29 | Fresh first window showed the requested synthetic Markdown file. Normal quit persisted the project and document with the document selected. |
| 37561 | 12:31 | Fresh launch with no targets displayed the selected document. The snapshot produced after quit verified that project, document and tab order had been restored. Changed the General switch from on to off and verified the stored preference. |
| 41713 | After the interrupted quit was retried | Fresh launch with the switch off showed an empty window. Opened Guide v128 in both languages through Help and verified the chapter 11 heading and the new default-on instruction in the native WebKit accessibility tree. The working-copy SHA-256 of each guide matched its bundled asset. Re-enabled the switch before quitting. |
| 44155 | 12:39 | With restoration on and the previous snapshot populated, opening a specific Markdown file launched a fresh process and displayed that file. Its quit snapshot showed only the initial empty tab and the requested file. |

Guide package SHA-256: EN `edcb0ff2c6bcb6a59f70a7c70e0ed2b7650ca08bb2856ea6608dd3840320ba5c`, ES `af42c7ca7742f4bc3ac6db3f079939a730fc8fe32cce3afe0a7eb088d47fb3b6`. The changed Help scope was chapter 11. Math, practice form and guide examples were outside the change.

[Switch on](preferences-on.png) and [switch off](preferences-off.png) were captured in PID 37561, with an English macOS Preferences sheet over the synthetic document.

The owner-authorized pre-existing QA processes 59339, 67454 and 89429 quit normally before the candidate launch. After validation the four candidate PIDs were verified absent. No Device Hub sessions were opened. The test-only startup snapshot was removed from live settings.
