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

## Row drag-source follow-up — 2026-11-18

- Commit `90b726fd06847e1f83bbe542e9932532521d8bbd` moves `ProjectTreeDragSource` and the folder drop delegate from the row's inner `Button` to its outer row container, with a full-width hit shape. The intent is to keep row drag/drop gestures separate from Button click and double-click tracking; this is a candidate fix, not a confirmed live interaction result.
- `python3 scripts/compile-and-record.py --pr-number 471 -- swift test --filter ProjectTabOpeningTests/testNativeFileRowsSupportModifierSelectionAcrossFilesAndFolders` passed (1 test). The focused test still verifies plain selection, ⌘ toggle and ⇧ range across mixed file/folder rows; it does not initiate a native drag.
- Re-ran `EVIDENCE_SHA=90b726fd06847e1f83bbe542e9932532521d8bbd LEONARDO_VISUAL_EVIDENCE=/tmp/leonardo-pr471-selection-captures-90b726fd-exact swift test --skip-build --filter SidebarSelectionTests/testNativeSelectionAppearances` (1 test passed, 2026-11-18 20:42:11 UTC). The sidecars identify source `90b726fd06847e1f83bbe542e9932532521d8bbd`, English, 440×240 points and 880×480 pixels. PNG hashes match the already-attached light/dark images byte-for-byte, so no extra public image upload was needed.
- `LEONARDO_SOURCE_PR=471 ./launch.sh --qa` packaged the current source. Bundle: `/var/folders/_s/khfztzr97kd4049py5k3zsg80000gn/T/leonardo-native-qa-o2jdldk4/LeonardoMDQA.app`; identifier `eu.pinedatec.LeonardoMD.qa.e1e6478530a64bb4870eb8dc65ccf93a`; executable `LeonardoMD`; app 0.3.1884 stable; PR ledger build 15. `otool -L` showed the expected app frameworks and no XCTest/XCUI dependency. The release-notes sheet was dismissed and the synthetic fixture `leonardo-pr471-dnd-2zm0he4b` opened in this fresh process.
- Task-owned process PID 6851 started 2026-11-18 20:53:20 Europe/Madrid from `/private/var/folders/_s/khfztzr97kd4049py5k3zsg80000gn/T/leonardo-native-qa-o2jdldk4/LeonardoMDQA.app/Contents/MacOS/LeonardoMD`. Through the real Help menu, the English bundled Guide v96 opened at the local v96 path and its bundled cover image rendered. The Mac relocked before this process's remaining mandatory Help checks (Spanish, rendered examples, Math fallback and practice-form save/reopen) could be completed.
- The owner reported that earlier task-owned PID 61105 did not start dragging; that process was closed. CUA's previous pointer attempts could not hit-test the tree on the external display. No live move or Option-copy outcome is claimed for PID 6851; its drag gesture has not yet been manually exercised.
- Exact-head `pull_request` CI run 44387446267 passed on `90b726fd06847e1f83bbe542e9932532521d8bbd`. The current `validate` run 44394414398 and evidence-count run 135120172855 also passed. The same-SHA `push` test run 44387428604 was still in progress at this record and is not used as a substitute for the passing `pull_request` run.
- PID 6851 was gracefully quit after the interrupted Help check; its exact process exited. Do not report that instance's Help smoke or live drag/drop acceptance as passed.

## Native AppKit drag-source follow-up — 2026-11-18

- The owner manually tested build 17 (PID 66985, source `90b726fd`) and confirmed that dragging `MoveSource.md` to `MoveFolder` still did not start. That task-owned process was later gracefully quit and verified exited.
- Replaced the row-level SwiftUI drag source with a transparent `NSViewRepresentable` source registered with a local AppKit mouse-event monitor. It captures the initiating mouse-down event and starts `beginDraggingSession` after a five-point movement threshold, leaving the existing row `Button` responsible for selection and click/double-click behavior.
- `python3 scripts/compile-and-record.py --pr-number 471 -- swift test --filter ProjectTabOpeningTests` passed after the event-source change: 8 tests, 1 opt-in evidence test skipped, 0 failures. The mixed file/folder selection and row click/double-click tests passed; this suite does not prove native drag initiation. PR ledger build delta is 20.
- `python3 scripts/compile-and-record.py --pr-number 471 -- swift test --filter DocumentTabsTests/testProjectTreePasteboardItemCarriesMixedSelectionBatch` passed (1 test). It verifies the native pasteboard exposes the primary file URL and serializes a mixed file/folder selection under the project-tree type. The ledger is now 22; the product sources are unchanged from the PID 5554 bundle (build 21).
- `LEONARDO_SOURCE_PR=471 ./launch.sh --qa` produced `/var/folders/_s/khfztzr97kd4049py5k3zsg800000gn/T/leonardo-native-qa-id9o39bk/LeonardoMDQA.app`, identifier `eu.pinedatec.LeonardoMD.qa.8469566fd4244577b3fa4672f5528120`, executable `LeonardoMD`, app 0.3.1884 stable, PR ledger build 21. A fresh process PID 5554 started 2026-11-18 23:26:01 Europe/Madrid. `otool -L` showed no XCTest dependency. The real fixture `leonardo-pr471-dnd-2zm0he4b` is open with `MoveSource.md` and `MoveFolder` visible.
- CUA could not synthesize a pointer drag: hit-testing failed at the app window's monitor coordinates even after moving the task-owned window to the Studio Display and centering it. Accessibility can read the source and target, but cannot validate the gesture. The Mac is unlocked; owner confirmation for build 21 is pending. Do not claim live move, Option-copy, mixed-batch drag or Help acceptance yet.
- PID 97545 (build 19) was gracefully quit and verified exited before build 21 launch. PID 5554 remains task-owned and must be used for the current live check and the required bilingual Help smoke, then gracefully quit and verified exited.
- The branch still has uncommitted source changes based on `90b726fd`; exact-head CI, strict current-head judge and merge gates do not apply to this worktree state. Keep PR #471 in draft until live drag/drop acceptance is confirmed.

Reproduce the captures from a disposable worktree at the recorded source revision:

```sh
git worktree add --detach /tmp/leonardo-pr471-source-47b5495 47b5495b6b3be7ba651b33160da7af448fb37fa2
cd /tmp/leonardo-pr471-source-47b5495
EVIDENCE_SHA=47b5495b6b3be7ba651b33160da7af448fb37fa2 \
LEONARDO_VISUAL_EVIDENCE=/tmp/leonardo-pr471-selection-captures-47b5495b-exact \
  swift test --filter SidebarSelectionTests/testNativeSelectionAppearances
```
