# Favorite project appearance

Tracking: [#300](https://github.com/PinedaTec-EU/LeonardoMD/issues/300), [#303](https://github.com/PinedaTec-EU/LeonardoMD/issues/303), [#304](https://github.com/PinedaTec-EU/LeonardoMD/issues/304) and [workspace removal #305](https://github.com/PinedaTec-EU/LeonardoMD/issues/305).

## Current behavior

Project favorites can select a theme. The same association appears beside matching starred project rows in Recents and applies when that project opens through either route. Inherit restores portable project/global appearance. Document favorites have no theme selector.

Workspace grouping and its manager are removed. Previously stored workspace favorite metadata is readable but absent from navigation and cannot affect project or standalone appearance. Detaching a project, opening a standalone document and Save Copy restore normal standalone appearance.

`FavoriteThemeTests` covers project/standalone transitions, inert workspace metadata, session isolation, Recents refresh, custom-token inheritance and concurrent membership/theme writes. `FavoriteAppearancePersistenceTests` retains serialization and merge coverage. `ProjectTabOpeningTests` also verifies the theme of a new project document tab.

`FavoriteThemePicker` uses a borderless native Menu with a checked Picker. Label and disclosure use the active session text tokens through SwiftUI tint and native accent color. Current capture fixtures include an Aqua host with a graphite session and generate project states only.

See [current project navigation evidence](../project-navigation/README.md) for the current Home and tabs. CI renders actual `SavedItemsView` / `FavoriteThemePicker` states in `favorite-themes/` under its exact `EVIDENCE_SHA`.

## Historical #301 captures

The image files and source manifest stored in this directory are historical evidence from #301, before workspace removal. They are not screenshots of the current workspace-free interface:

- `favorite-themes-en-900.png` and `favorite-themes-es-900.png`: project Favorites/Recents, light, 900×620 points.
- `favorite-themes-es-600.png`: project Favorites/Recents, graphite session with Aqua hosting, 600×620 points.
- Files ending in `-workspace.png`: the former workspace category, retained only as historical evidence for #303/#304.

Their JSON sidecars record original capture times, dimensions, categories and native host appearance; `source-hashes.json` binds those original product/test inputs. The narrower historical capture demonstrated readable selected palette names and disclosure arrows with truncated paths.

All captures use native AppKit/SwiftUI component rendering through XCTest, with synthetic folders and isolated preferences. No XCTest executable was packaged or launched as a GUI app. Component rendering does not prove fresh packaged-process startup or multi-process acceptance; the owner's installed app was preserved.
