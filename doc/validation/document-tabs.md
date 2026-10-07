# Document tabs

Tracking: [issue #19](https://github.com/PinedaTec-EU/LeonardoMD/issues/19). The implementation is stacked on [PR #8](https://github.com/PinedaTec-EU/LeonardoMD/pull/8); integrate #8 first, retarget to main, refresh the branch and rerun validation before merging this change. No version-bump workflow exists in this repository.

## Behavior

- `+` or Cmd-T creates an empty tab. Each tab provides the existing document/project controls.
- Opening a file normally replaces the active document. Already open files activate their tab; standardized paths and symlink aliases are deduplicated.
- Dropping local `.md` / `.markdown` files on the window or sidebar opens them in new tabs. Finder/Dock document-open events use this same flow. Files are neither copied nor moved. Sidebar Markdown drops now open tabs; use the existing Move menu to relocate Markdown files.
- Each tab owns an `AppSession` and retains its native editor/preview views, preserving selection, undo, scroll, mode, settings and project context. Inactive views cannot receive input. Sessions keep monitoring disk changes and retain existing autosave/conflict behavior.
- Tab headers show full paths as tooltips. Their context menu offers Show in Finder, Copy Path and Close; location actions are disabled for empty tabs. Project-only tabs reveal their folder.
- Cmd-W closes the active tab; Cmd-Shift-W closes the window. Closing the last tab leaves a fresh empty tab.
- Tab/window/application close saves relevant sessions. Conflicts or failed saves prevent close and reveal the affected tab. Switching tabs retains conflicting drafts without requiring resolution first.
- Rename/move/delete operations prepare affected sibling sessions, remap their paths after success, or clear deleted contexts. A sibling conflict prevents destructive operations.

Tabs are window-local and are not restored across restarts. Reordering and split tab groups are outside this change. Keeping native views alive consumes resources per open tab; no fixed tab limit is imposed.

## Automated validation

Run `swift test`. `DocumentTabsTests` covers empty/replace/reuse navigation, multiple drops, alias deduplication, invalid-drop rejection, inactive drafts and conflicts, mode/scroll/project restoration, closing all sessions and cross-tab project rename/delete. The existing real WebKit suite remains part of full validation.

Native captures and the exact reviewed SHA are recorded in the PR. CI and visual evidence do not replace the independent review required before merge.
