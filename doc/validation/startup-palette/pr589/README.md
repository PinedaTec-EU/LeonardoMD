# Leonardo Classic startup validation

[Issue #588](https://github.com/PinedaTec-EU/LeonardoMD/issues/588) and [PR #589](https://github.com/PinedaTec-EU/LeonardoMD/pull/589), November 24, 2026. Product and test source `3cd021acd12439178ed540f10efa15e718d3325c`. Later changes record only these captures and the compilation ledger. Verify the mapping with `git diff --name-only 3cd021acd12439178ed540f10efa15e718d3325c HEAD`.

| State | Capture | Metadata |
| --- | --- | --- |
| Home with no preferences file | [Classic default](startup-default.png) | [JSON](startup-default.metadata.json) |
| Home with explicitly saved Classic | [Saved Classic](startup-classic.png) | [JSON](startup-classic.metadata.json) |
| Home with explicitly saved Graphite Glass | [Saved Graphite Glass](startup-saved.png) | [JSON](startup-saved.metadata.json) |
| Two restored Paper White windows | [Saved Paper White](startup-paper-white.png) | [JSON](startup-paper-white.metadata.json) |
| Recent document in saved Paper White | [Recent document](startup-recents.png) | [JSON](startup-recents.metadata.json) |
| Help chapter 11 in English | [Updated default](help-en.png) | [JSON](help-en.metadata.json) |
| Help chapter 11 in Spanish | [Updated default](help-es.png) | [JSON](help-es.metadata.json) |

The captures show the initial Home window, a restored window or the documented Help section. The startup check combines early window captures with the loading order in the source. It does not claim frame-by-frame video analysis. The native viewport measurements in the shared metadata are window points. All activity used an isolated synthetic home. No production LeonardoMD instance was running at launch. The clean launch also exercised primary-instance session initialization.

Build and start from the product source using `LEONARDO_SOURCE_PR=589 ./launch.sh --qa --env "CFFIXED_USER_HOME=$QA_HOME" --env "HOME=$QA_HOME" --args --new-instance`. Use a disposable home. Leave any pre-existing production instance running. Start without the preferences file, then seed `Library/Application Support/LeonardoMD/preferences.json` with `{"palette":"leonardo-classic"}` or `{"palette":"graphite-glass"}` between fresh launches. Open Help and use the document outline to reach chapter 11. Both working copies matched their bundled Guide v137 templates. Form practice behavior was outside the change scope.

Native QA verified the real packaged executable and dependency checks for version 0.3.2241 build 2241 on macOS 27.2.1 (26B131). Bundle identifier `eu.pinedatec.LeonardoMD.qa.d6beebdf8b794d9fa376b7780ececac9`. Executable in `leonardo-native-qa-qhfbia32/LeonardoMDQA.app/Contents/MacOS/LeonardoMD`. Owned PIDs 4833 (09:34:43), 5721 (09:35:10), 5830 (09:35:15), 5879 (09:35:17), 5962 (09:35:20) exited after graceful quit. No Device Hub sessions were opened.

The functional XCTest checks the saved palette and settings baseline immediately after creating new tab and window sessions. It uses no UI automation. The live app verified Recent Documents by opening the synthetic Second tab.md in Paper White. The earlier candidate's suspended-initialization test exercised Bring All to Front, New Window and the native Recent Documents action. That UI test was replaced under the repository's updated CI policy.

The following SHA-256 digests come from the actual packaged files and personal copies opened through Help. Each pair also passed `cmp`.

| Locale | Bundled guide | Opened personal copy |
| --- | --- | --- |
| English | `34237873642a85b25df2d9b6d7316e1ce0b0b86b20ebd84efc0eb4a87d609386` | `34237873642a85b25df2d9b6d7316e1ce0b0b86b20ebd84efc0eb4a87d609386` |
| Spanish | `4f8363d706aa4c12a02423e7c453faa20b5800351228e7dcf276e4e5d5c09030` | `4f8363d706aa4c12a02423e7c453faa20b5800351228e7dcf276e4e5d5c09030` |

Seeded restoration used saved Paper White and two synthetic windows. The accessibility window titles confirmed Second tab.md and Second window.md. The functional XCTest also checks the palette immediately after creating tab and window sessions, before their asynchronous reads. Earlier QA PID 97556 (03:28:51, bundle c0e3dc124fe64920b1f11e9cc02c8aaa) was verified absent after its requested graceful quit.

Local validation passed with `swift test` and the three deterministic guide-package tests on the recorded source revision.
