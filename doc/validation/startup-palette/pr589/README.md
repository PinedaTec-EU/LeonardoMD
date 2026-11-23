# Leonardo Classic startup validation

[Issue #588](https://github.com/PinedaTec-EU/LeonardoMD/issues/588) and [PR #589](https://github.com/PinedaTec-EU/LeonardoMD/pull/589), November 24, 2026. Product and test source `91aa15814040a3f93e528d2f600c08d293f7d557`. Later changes record only these captures and the compilation ledger. Verify the mapping with `git diff --name-only 91aa15814040a3f93e528d2f600c08d293f7d557 HEAD`.

| State | Capture | Metadata |
| --- | --- | --- |
| Home with no preferences file | [Classic default](startup-default.png) | [JSON](startup-default.metadata.json) |
| Home with explicitly saved Classic | [Saved Classic](startup-classic.png) | [JSON](startup-classic.metadata.json) |
| Home with explicitly saved Graphite Glass | [Saved Graphite Glass](startup-saved.png) | [JSON](startup-saved.metadata.json) |
| Help chapter 11 in English | [Updated default](help-en.png) | [JSON](help-en.metadata.json) |
| Help chapter 11 in Spanish | [Updated default](help-es.png) | [JSON](help-es.metadata.json) |

The captures show the initial Home window or the documented Help section. The startup check combines early window captures with the loading order in the source. It does not claim frame-by-frame video analysis. The native viewport measurements in the shared metadata are window points. All activity used an isolated synthetic home as an additional instance because a production instance was present at the start of QA.

Build and start from the product source using `LEONARDO_SOURCE_PR=589 ./launch.sh --qa --env "CFFIXED_USER_HOME=$QA_HOME" --env "HOME=$QA_HOME" --args --new-instance`. Use a disposable home and a permitted additional instance. Start without the preferences file, then seed `Library/Application Support/LeonardoMD/preferences.json` with `{"palette":"leonardo-classic"}` or `{"palette":"graphite-glass"}` between fresh launches. Open Help and use the document outline to reach chapter 11. Both working copies matched their bundled Guide v137 templates. Form practice behavior was outside the change scope.

Native QA verified the real packaged executable and dependency checks for version 0.3.2205 build 2205 on macOS 27.2.1 (26B131). Bundle identifier `eu.pinedatec.LeonardoMD.qa.48b23ca31ba3443da63d3acc01989a6e`. Executable in `leonardo-native-qa-_lrr2_bq/LeonardoMDQA.app/Contents/MacOS/LeonardoMD`. Owned PIDs 81592 (00:43:06), 85519 (00:46:11), 85941 (00:46:43) and 86784 (00:47:25) exited after graceful quit. No quit command was sent to the pre-existing app. No Device Hub sessions were opened.

Local checks on the reconciled source passed 584 XCTest cases (40 skips, zero failures), 72 Swift Testing cases and three deterministic Guide package tests.
