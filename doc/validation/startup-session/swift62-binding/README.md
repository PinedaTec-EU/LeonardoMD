# Native Preferences recheck after Swift 6.2 compatibility fix

[Issue #90](https://github.com/PinedaTec-EU/LeonardoMD/issues/90), [PR #91](https://github.com/PinedaTec-EU/LeonardoMD/pull/91). Reviewed product source `c39e7785d9a312836b032550b02511308e5ca168`. The [Swift 6.2.4 CI crash](https://github.com/PinedaTec-EU/LeonardoMD/actions/runs/45234004821/job/137900843160) occurred in IR generation of the bound Preferences setter. The explicit closure calls the same global-only setter. The lifecycle code is unchanged since the [packaged lifecycle regression](../corrected-quit/README.md). The subsequent evidence commit adds documentation and the successful compilation allocation only.

Reproduced with `LEONARDO_SOURCE_PR=91 ./launch.sh --qa <synthetic-project>`. Candidate PID 13040, started November 23, 2026 at 19:08:28 CET. Executable `leonardo-native-qa-ebil3qr6/LeonardoMDQA.app/Contents/MacOS/LeonardoMD`, version/build 0.3.2205/2205, on macOS 27.2.1. Preflight verified native executable identity, dependencies, signatures and absence of XCTest linkage. First window opened the synthetic project.

- Verified both [on](preferences-on.png) and [off](preferences-off.png) while scoped to This project. The project's configuration inode, modification time and size were identical before and after toggling.
- Revisited chapter 11 of Guide v135 through Help in both languages. The native WebKit accessibility tree included the startup instruction, and both personal-copy hashes matched the packaged assets and the preceding evidence.
- All 12 focused Swift tests passed again. Normal quit of PID 13040 was verified, prior snapshot state restored, and no Device Hub sessions were opened.

QA bundle identifier: `eu.pinedatec.LeonardoMD.qa.86dc427d9c1b46fd8db108345f5298d8`.
