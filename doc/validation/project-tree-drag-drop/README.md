# Project-tree mixed selection evidence

Tracking: [PR #471](https://github.com/PinedaTec-EU/LeonardoMD/pull/471), [issue #261](https://github.com/PinedaTec-EU/LeonardoMD/issues/261).

These are implementation-owned native component captures from source revision `47b5495b6b3be7ba651b33160da7af448fb37fa2`. Both show a selected `.mdlf` file and `Assets-folder` together; an active package document remains visually distinct. The fixture uses synthetic names/content, isolated preferences and disabled automatic following.

- `mixed-selection-light.png` / `.json`: light appearance, 440×240 points, 880×480 pixels, recaptured from the exact source revision on 2026-11-18 07:49:57 UTC.
- `mixed-selection-dark.png` / `.json`: dark appearance, same dimensions and source revision, captured at the same time.

PNG SHA-256: light `d58d13900e4ad0a7369d8986ea14520845d7d6198006f8bd45a8f7c43467bfbc`; dark `c9ca4c2c07fbaa8e822d1fde794c528ad5c54ecc2057132cff742f3a474609cc`.

The JSON files are the native `NativeViewCaptureSupport` provenance sidecars. This is an AppKit/SwiftUI component bitmap, so browser and CSS viewport fields are not applicable; the sidecars identify the native screen, OS, view size in points, image pixels, capture time, language and source SHA. These images show selection appearance only. They do not claim packaged-app startup, live pointer/drop-target behavior or bilingual Help acceptance.

The `ProjectTabOpeningTests.testNativeFileRowsSupportModifierSelectionAcrossFilesAndFolders` test exercises synthetic native mouse events for plain selection, ⌘ toggling and ⇧ range selection. `ProjectFileTreeTests` cover selection/model behavior, while `LocalProjectRepositoryTests` cover mixed batch move/copy and preflight collision rejection.

## Packaged-app validation — 2026-11-18

- Fresh task-owned QA app from `./launch.sh --qa`: LeonardoMD 0.3.1884 stable, bundle `eu.pinedatec.LeonardoMD.qa.231f83887f494aaa96f12f76f63dcc11`, PID 32935 (started 17:20:44 Europe/Madrid), built from PR head `9cb26b201b6f2215a52341e75f433a9bff871976`; implementation source remains unchanged from `47b5495b6b3be7ba651b33160da7af448fb37fa2`. Guide package revision v96; the PR ledger build delta is now 13.
- Opened `Help → Leonardo user guide` in English and Spanish in that same process. The selected guide URLs resolved to the local v96 personal copies (`User Guides/v96/en/Guide-v96-en.mdlz` and `User Guides/v96/es/Guide-v96-es.mdlz`). Both rendered the bundled cover/local images, Mermaid diagram, Vega-Lite chart and format table.
- Mermaid, Math (KaTeX) and Charts (Vega-Lite) were enabled. In both locales, inline math and one-line and multiline display equations rendered, including Markdown-sensitive underbraces, roots/arrows and tagged box-counting equation `(1)`. The `$$…$$` example shown inside inline code stayed literal by design. In the English guide, Math was disabled to verify literal fallback and code examples, then re-enabled. No KaTeX error or unintended raw delimiter was visible in the rendered equations.
- Opened the English practice form via the guide link, changed its name and goal to synthetic values, saved, closed and reopened it to confirm persistence, then restored and saved the original values. The Ready to share checkbox remained checked.
- Mixed selection of a folder and a file was visible in the packaged project tree. CUA could not hit-test the app window for pointer drag (`windowNotFoundAtPosition`), even after the window was raised/resized and the Mac unlocked. No drop executed; no file move or copy was observed. Live packaged move/copy acceptance remains pending.
- Restored the QA instance's original English interface setting and gracefully quit PID 32935. `cua.listApps()` no longer listed the QA app and `ps -p 32935` returned no process. Existing simulator/helper processes were preserved.

Reproduce the captures from a disposable worktree at the recorded source revision:

```sh
git worktree add --detach /tmp/leonardo-pr471-source-47b5495 47b5495b6b3be7ba651b33160da7af448fb37fa2
cd /tmp/leonardo-pr471-source-47b5495
EVIDENCE_SHA=47b5495b6b3be7ba651b33160da7af448fb37fa2 \
LEONARDO_VISUAL_EVIDENCE=/tmp/leonardo-pr471-selection-captures-47b5495b-exact \
  swift test --filter SidebarSelectionTests/testNativeSelectionAppearances
```
