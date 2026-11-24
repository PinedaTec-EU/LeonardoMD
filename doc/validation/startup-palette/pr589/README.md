# Leonardo Classic startup validation

[Issue #588](https://github.com/PinedaTec-EU/LeonardoMD/issues/588) and [PR #589](https://github.com/PinedaTec-EU/LeonardoMD/pull/589), November 24, 2026. Product and test source `aefc29abd6b062fa078bb39215b64d3d7757dccb`. Later changes record only these captures and the compilation ledger. Verify the mapping with `git diff --name-only aefc29abd6b062fa078bb39215b64d3d7757dccb HEAD`.

| State | Capture | Metadata |
| --- | --- | --- |
| Home with no preferences file | [Classic default](startup-default.png) | [JSON](startup-default.metadata.json) |
| Home with explicitly saved Classic | [Saved Classic](startup-classic.png) | [JSON](startup-classic.metadata.json) |
| Home with explicitly saved Graphite Glass | [Saved Graphite Glass](startup-saved.png) | [JSON](startup-saved.metadata.json) |
| Help chapter 11 in English | [Updated default](help-en.png) | [JSON](help-en.metadata.json) |
| Help chapter 11 in Spanish | [Updated default](help-es.png) | [JSON](help-es.metadata.json) |

The captures show the initial Home window or the documented Help section. The startup check combines early window captures with the loading order in the source. It does not claim frame-by-frame video analysis. The native viewport measurements in the shared metadata are window points. All activity used an isolated synthetic home. No production LeonardoMD instance was running at launch. The clean launch also exercised primary-instance session initialization.

Build and start from the product source using `LEONARDO_SOURCE_PR=589 ./launch.sh --qa --env "CFFIXED_USER_HOME=$QA_HOME" --env "HOME=$QA_HOME" --args --new-instance`. Use a disposable home. Leave any pre-existing production instance running. Start without the preferences file, then seed `Library/Application Support/LeonardoMD/preferences.json` with `{"palette":"leonardo-classic"}` or `{"palette":"graphite-glass"}` between fresh launches. Open Help and use the document outline to reach chapter 11. Both working copies matched their bundled Guide v137 templates. Form practice behavior was outside the change scope.

Native QA verified the real packaged executable and dependency checks for version 0.3.2230 build 2230 on macOS 27.2.1 (26B131). Bundle identifier `eu.pinedatec.LeonardoMD.qa.170e6000aaab4e2dac20b1d28356e702`. Executable in `leonardo-native-qa-3b3q35us/LeonardoMDQA.app/Contents/MacOS/LeonardoMD`. Owned PIDs 78067 (02:45:18), 78246 (02:45:36) and 78357 (02:45:41) exited after graceful quit. No Device Hub sessions were opened.

Local checks on the reconciled source passed 585 XCTest cases (40 skips, zero failures), 72 Swift Testing cases and three deterministic Guide package tests.

The delayed-preference XCTest holds initialization suspended, calls Bring all to front and New Window, and dispatches the native Recent Documents action. It checks that the first window remains hidden until saved Graphite Glass loads and that the selected recent document opens afterward. The intermediate QA process 50317 (01:58:19, bundle `eu.pinedatec.LeonardoMD.qa.84ec5dfee2de4b469a03a789a61f96f9`, executable in `leonardo-native-qa-u_0ezusr/LeonardoMDQA.app/Contents/MacOS/LeonardoMD`) also exited after graceful quit.

The following SHA-256 digests come from the actual packaged files and personal copies opened through Help. Each pair also passed `cmp`.

| Locale | Bundled guide | Opened personal copy |
| --- | --- | --- |
| English | `34237873642a85b25df2d9b6d7316e1ce0b0b86b20ebd84efc0eb4a87d609386` | `34237873642a85b25df2d9b6d7316e1ce0b0b86b20ebd84efc0eb4a87d609386` |
| Spanish | `4f8363d706aa4c12a02423e7c453faa20b5800351228e7dcf276e4e5d5c09030` | `4f8363d706aa4c12a02423e7c453faa20b5800351228e7dcf276e4e5d5c09030` |
