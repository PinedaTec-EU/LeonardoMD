# Project navigation

Tracking: [#305](https://github.com/PinedaTec-EU/LeonardoMD/issues/305). Existing project favorite themes from [#300](https://github.com/PinedaTec-EU/LeonardoMD/issues/300) remain available. Workspace grouping and its session appearance context are removed; stored workspace metadata stays readable but inert.

The actual SwiftUI Home offers Projects and Documents only. The project file context menu offers **Open in new tab**; double-click uses the same opening boundary. Single-click still opens normally. The new session keeps the project root, file visibility/order and a copy of settled expanded folders; source documents and unsaved drafts remain in their original tab. Already-open documents activate their existing tab.

`ProjectTabOpeningTests` sends native mouse down/up events through a real NSWindow/FileTreeRow host to distinguish single and double clicks. It also covers draft preservation, project favorite theme inheritance, tree state, duplicate activation, unsupported/outside paths, stale authorization and legacy preference loading. `FavoriteThemeTests` preserves project/standalone appearance transitions and verifies old workspace themes cannot override them. The retired manager's dedicated tests are removed; core file/symlink and package/sync tests remain.

Captures render real native views through XCTest, with synthetic documents and isolated preferences. No test executable was launched as an app, and the owner's running app was preserved.

- `welcome-en.png`, `welcome-es.png`: Home, 1100×1150 points, Projects selected in Favorites and Recents; no workspace controls/category.
- `project-tabs-en.png`, `project-tabs-es.png`: DocumentTabsView, 1260×850 points, two document tabs with the same project, expanded Notes and Decisions selected.

JSON sidecars record actual capture time, pixel dimensions, language, OS and source head. `source-hashes.json` binds the local captures to product/test inputs independently of the later evidence commit. CI regenerates these states under its exact `EVIDENCE_SHA` in the visual artifact. Native component bitmaps do not establish fresh packaged-process startup or physical mouse interaction; event delivery is tested separately.

Reproduce with `LEONARDO_PROJECT_TABS_CAPTURE` / `LEONARDO_FAVORITES_CAPTURE` and the source-PR compilation recorder, or use `swift test --skip-build` after compiling that exact checkout. The CI `LEONARDO_VISUAL_EVIDENCE` root enables both capture suites automatically.

The full local suite reproduces the existing ancestor-authorization assertion failure [#307](https://github.com/PinedaTec-EU/LeonardoMD/issues/307), also present in unchanged #301. Focused project navigation, native click, favorites and theme checks pass. Hosted checks and the independent verdict are recorded on the PR; this page does not claim integration or release publication.
