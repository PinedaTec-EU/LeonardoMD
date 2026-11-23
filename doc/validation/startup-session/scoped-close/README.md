# Packaged macOS verification of scoped startup close handling

[PR #91](https://github.com/PinedaTec-EU/LeonardoMD/pull/91), [issue #90](https://github.com/PinedaTec-EU/LeonardoMD/issues/90). Reviewed PR head `72de90351c3ce8609f270fb76676099185734bce`. The product was built from parent `c78c673c067618ed1b73d2d114686fe9141559b0` with `LEONARDO_SOURCE_PR=91 ./launch.sh --qa <synthetic-project>`; the PR head adds only the successful compilation allocation. This evidence-only commit is linked from the PR without modifying its CI-tested head.

On November 23, 2026, the verified QA bundle used the real `leonardo-native-qa-6ws6qebc/LeonardoMDQA.app/Contents/MacOS/LeonardoMD` executable, bundle ID `eu.pinedatec.LeonardoMD.qa.2ef40f8beb8d4808b2ba4ed88eb47def`, version/build `0.3.2205/2205` on macOS 27.2.1 (26B131). QA preflight checked native executable identity, signatures and dependencies, including absence of XCTest linkage.

- PID 52603 (20:20:04 CET) reported first-window readiness. After unlock, verified the synthetic project, both switch states in **General → On this Mac** ([on](preferences-on.png), [off](preferences-off.png)) and unchanged inode, modification time and size of the project settings file. Created and closed an independent tab and window. Opened chapter 11 through Help in both locales, verified the rendered setting instruction and matched bundled/working-copy package bytes. Quit normally.
- PID 3557 (23:20:08 CET) launched without a target and restored the selected English Guide package. The successful quit snapshot also confirmed the previously open synthetic project was restored.
- PID 3711 (23:20:23 CET) launched by opening the explicit synthetic Markdown file while the prior snapshot was populated. Its successful quit snapshot contained only the blank initial tab and requested file.
- Verified all three PIDs exited, including the candidate originally retained while locked. Restored pre-test startup snapshot state. No Device Hub sessions were opened.
- Focused tests for this product source and exact-head CI cover the last-window veto, independent close during reservation, restore destination identity, later standalone Split-mode initialization, global-only preference writes and the bundled guides. The [earlier lifecycle record](../corrected-quit/README.md) also exercises the off-state clean launch.

Guide v135 packages verified: EN `c6a8c5455b10424145c2f74e05160630e1b72d9af042257e208eac71f84f9ef5`, ES `6e7b4e09d0cd4f95611683f29fced617b6c38342abc60084674814836822bbf6`.
