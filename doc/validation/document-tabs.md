# Document tabs

Tracking: [issue #19](https://github.com/PinedaTec-EU/LeonardoMD/issues/19). PR #8 is integrated in main; PR #21 now targets main and includes the About and startup-diagnostics changes. That integration context predates the ledger. Current release.feature.build versioning follows [the shared-ledger workflow](../release-version-ledger.md), with initial baseline 0.1.56.

## Behavior

- `+` or Cmd-T creates an empty tab. Each tab provides the existing document/project controls.
- Opening a file normally replaces the active document. Already open files activate their tab; standardized paths and symlink aliases are deduplicated.
- Dropping local `.md` / `.markdown` files on the window or sidebar opens them in new tabs. Finder/Dock document-open events use this same flow. Document drops reject unsupported/non-file URL batches atomically. Existing project-sidebar relocation is a separate action: one non-Markdown source already inside the current project may move within that project, with the existing file-operation and symlink guards. Unsupported external files do not enter that move path. Sidebar Markdown drops now open tabs; use the existing Move menu to relocate Markdown files.
- Each tab owns an `AppSession` and retains its native editor/preview views, preserving selection, undo, scroll, mode, settings and project context. Inactive views cannot receive input. Sessions keep monitoring disk changes and retain existing autosave/conflict behavior.
- Drag a tab onto another tab to move it to that position. The context menu also offers Move Left and Move Right, disabled at the corresponding edge. Reordering preserves the selected tab and its session, drafts, undo and scroll. Document/project tabs show a grip with two vertical columns of dots; empty New Tab headers omit it. The pointer gesture uses header frames in a window-local coordinate space, highlights its target, and commits the move on release. External file drops remain independent. Repair tracking: [#55](https://github.com/PinedaTec-EU/LeonardoMD/issues/55). Tracking: [#51](https://github.com/PinedaTec-EU/LeonardoMD/issues/51).
- Tab headers show full paths as tooltips. Their context menu offers Show in Finder, Copy Path and Close; location actions are disabled for empty tabs. Project-only tabs reveal their folder.
- Cmd-W closes the active tab; Cmd-Shift-W closes the window. Closing the last tab leaves a fresh empty tab.
- Tab/window/application close saves relevant sessions. Conflicts or failed saves prevent close and reveal the affected tab. Switching tabs retains conflicting drafts without requiring resolution first.
- Rename/move/delete operations prepare affected sibling sessions, remap their paths after success, or clear deleted contexts. A sibling conflict prevents destructive operations.

Tabs are window-local and are not restored across restarts. Split tab groups and cross-window moves are unsupported. Keeping native views alive consumes resources per open tab; no fixed tab limit is imposed.

## Automated validation

Run `swift test`. `DocumentTabsTests` covers empty/replace/reuse navigation, multiple drops through actual `NSItemProvider` URL loading, mixed/unsupported/non-file provider rejection, alias deduplication, invalid-drop rejection, sidebar relocation boundaries, inactive drafts and conflicts, mode/scroll/project restoration, closing all sessions and cross-tab project rename/delete. The existing real WebKit suite remains part of full validation.

Native captures and the exact reviewed SHA are recorded in the PR. CI and visual evidence do not replace the independent review required before merge.

The window and sidebar share `DocumentDropProviders` for native URL-provider loading. Native pointer gestures may remain pending when Computer cannot deliver them; the deterministic provider regression exercises the same production boundary and document-opening path.

Sidebar external-drop correction: [#34](https://github.com/PinedaTec-EU/LeonardoMD/issues/34).

## Native pointer acceptance

Run the packaged source-PR build with three distinct local documents. Capture the initial order, drag the first document onto the last and drag it back; check the header order and selected document after each release. Verify that the two-column dot grip is present only on document/project headers and absent on empty New Tab headers. Releasing outside the bar must leave the order unchanged. Preserve before/after captures and the exact implementation SHA in the PR.

If macOS exposes only a transformed window thumbnail to Computer Use, use the application's Window → Bring All to Front action before coordinate testing. An accessibility Raise action alone did not restore the full window in this environment. Do not treat a gesture sent against the thumbnail as functional evidence.
