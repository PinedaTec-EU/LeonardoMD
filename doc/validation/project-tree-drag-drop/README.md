# Project-tree mixed selection evidence

Tracking: [PR #471](https://github.com/PinedaTec-EU/LeonardoMD/pull/471), [issue #261](https://github.com/PinedaTec-EU/LeonardoMD/issues/261).

These are implementation-owned native component captures from source revision `47b5495b6b3be7ba651b33160da7af448fb37fa2`. Both show a selected `.mdlf` file and `Assets-folder` together; an active package document remains visually distinct. The fixture uses synthetic names/content, isolated preferences and disabled automatic following.

- `mixed-selection-light.png` / `.json`: light appearance, 440×240 points, 880×480 pixels, recaptured from the exact source revision on 2026-11-18 07:49:57 UTC.
- `mixed-selection-dark.png` / `.json`: dark appearance, same dimensions and source revision, captured at the same time.

PNG SHA-256: light `d58d13900e4ad0a7369d8986ea14520845d7d6198006f8bd45a8f7c43467bfbc`; dark `c9ca4c2c07fbaa8e822d1fde794c528ad5c54ecc2057132cff742f3a474609cc`.

The JSON files are the native `NativeViewCaptureSupport` provenance sidecars. This is an AppKit/SwiftUI component bitmap, so browser and CSS viewport fields are not applicable; the sidecars identify the native screen, OS, view size in points, image pixels, capture time, language and source SHA. These images show selection appearance only. They do not claim packaged-app startup, live pointer/drop-target behavior or bilingual Help acceptance.

The `ProjectTabOpeningTests.testNativeFileRowsSupportModifierSelectionAcrossFilesAndFolders` test exercises synthetic native mouse events for plain selection, ⌘ toggling and ⇧ range selection. `ProjectFileTreeTests` cover selection/model behavior, while `LocalProjectRepositoryTests` cover mixed batch move/copy and preflight collision rejection.

Reproduce the captures from a disposable worktree at the recorded source revision:

```sh
git worktree add --detach /tmp/leonardo-pr471-source-47b5495 47b5495b6b3be7ba651b33160da7af448fb37fa2
cd /tmp/leonardo-pr471-source-47b5495
EVIDENCE_SHA=47b5495b6b3be7ba651b33160da7af448fb37fa2 \
LEONARDO_VISUAL_EVIDENCE=/tmp/leonardo-pr471-selection-captures-47b5495b-exact \
  swift test --filter SidebarSelectionTests/testNativeSelectionAppearances
```
