# Document tabs

Tracking: [issue #19](https://github.com/PinedaTec-EU/LeonardoMD/issues/19). PR #8 is integrated in main; PR #21 now targets main and includes the About and startup-diagnostics changes. That integration context predates the ledger. Current release.feature.build versioning follows [the shared-ledger workflow](../release-version-ledger.md), with initial baseline 0.1.56.

## Behavior

- `+` or Cmd-T creates an empty tab. Each tab provides the existing document/project controls.
- In the project tree, single-click opens a file normally; double-click or **Open in new tab** creates a tab with the same project, file filters and expanded folders. The originating tab keeps its document and unsaved draft. Search results also offer **Open in new tab**.
- Opening a file normally replaces the active document. Already open files activate their tab; standardized paths and symlink aliases are deduplicated.
- Dropping local `.md` / `.markdown` files from Finder on the window or sidebar opens them in new tabs. Finder/Dock document-open events use this same flow. Document drops reject unsupported/non-file URL batches atomically. A drag that starts on a project-tree row and ends on a folder row moves that one item; hold ⌥ while releasing to copy instead. Both operations use the existing file-operation, session and symlink guards, reject destination collisions, and refresh the tree. The target highlights and labels the internal action. Unsupported external files do not enter the relocation path.
- Each tab owns an `AppSession` and retains its native editor/preview views, preserving selection, undo, scroll, mode, settings and project context. Inactive views cannot receive input. Sessions keep monitoring disk changes and retain existing autosave/conflict behavior.
- Drag a tab onto another tab to move it to that position. The context menu also offers Move Left and Move Right, disabled at the corresponding edge. Reordering preserves the selected tab and its session, drafts, undo and scroll. Document/project tabs show a grip with two vertical columns of dots; empty New Tab headers omit it. The pointer gesture uses header frames in a window-local coordinate space, moves the dragged header with the pointer above its siblings with a shadow, highlights its target, and animates the committed order on release. External file drops remain independent. Repair tracking: [#55](https://github.com/PinedaTec-EU/LeonardoMD/issues/55). Tracking: [#51](https://github.com/PinedaTec-EU/LeonardoMD/issues/51).
- Tab headers show full paths as tooltips. Their context menu offers Show in Finder, Copy Path and Close; location actions are disabled for empty tabs. Project-only tabs reveal their folder.
- Cmd-W closes the active tab; Cmd-Shift-W closes the window. Closing the last tab leaves a fresh empty tab.
- Tab/window/application close saves relevant sessions. Conflicts or failed saves prevent close and reveal the affected tab. Switching tabs retains conflicting drafts without requiring resolution first.
- Rename/move/delete operations prepare affected sibling sessions, remap their paths after success, or clear deleted contexts. A sibling conflict prevents destructive operations.

Tabs are window-local and are not restored across restarts. Split tab groups and cross-window moves are unsupported. Keeping native views alive consumes resources per open tab; no fixed tab limit is imposed.

## Automated validation

Run `swift test`. `DocumentTabsTests` covers empty/replace/reuse navigation, multiple drops through actual `NSItemProvider` URL loading, mixed/unsupported/non-file provider rejection, alias deduplication, invalid-drop rejection, prior sidebar relocation boundaries, inactive drafts and conflicts, mode/scroll/project restoration, and closing all sessions. Those existing provider tests do not exercise the new Option-copy gesture or folder-copy path; exact-source CI and native pointer acceptance remain necessary. The existing real WebKit suite remains part of full validation.

Native captures and the exact reviewed SHA are recorded in the PR. CI and visual evidence do not replace the independent review required before merge.

The window and sidebar share `DocumentDropProviders` for native URL-provider loading. Native pointer gestures may remain pending when Computer cannot deliver them; the deterministic provider regression exercises the same production boundary and document-opening path.

Sidebar external-drop correction: [#34](https://github.com/PinedaTec-EU/LeonardoMD/issues/34).

Project-tree move/copy addition: [#261](https://github.com/PinedaTec-EU/LeonardoMD/issues/261). Fresh packaged pointer acceptance for move, ⌥ copy, collision rejection, folder contents, target feedback and Help v94 remains pending.

## Project-tree move/copy pointer acceptance

Use a fresh packaged LeonardoMD process and a synthetic project with files and nested folders. Record the process identity, build and exact source SHA. Drag one file onto a different folder and confirm the original path disappears and the destination appears. Repeat with ⌥ held through release and confirm the original remains and a copy appears. Repeat both operations with a folder containing nested files. Confirm the target row shows its localized action while hovering, an existing destination is never overwritten, self/descendant targets are rejected, the open source tab remains valid after copying, and moving an open file or folder keeps the open document/session path current. A Finder Markdown drop must still open a tab; an unsupported Finder file must not enter the project.

In that same packaged app, open the bundled Spanish and English guides through Help. Check the live Mermaid, display/inline math (including the tagged box-counting formula), Vega chart, local image and table examples, then open, fill, save and reopen the separate practice form. With Math enabled, verify rendered equations and tags without literal delimiters or KaTeX errors; check the disabled fallback and literal code examples. Capture the Help package/copy content identities and locale/extension state. Gracefully quit only task-owned app processes and confirm exit. Acceptance for this candidate remains pending.

## Native pointer acceptance

Run the packaged source-PR build with three distinct local documents. Capture the initial order, drag the first document onto the last and drag it back; check the header order and selected document after each release. Verify that the two-column dot grip is present only on document/project headers and absent on empty New Tab headers. Releasing outside the bar must leave the order unchanged. Preserve before/after captures and the exact implementation SHA in the PR.

If macOS exposes only a transformed window thumbnail to Computer Use, use the application's Window → Bring All to Front action before coordinate testing. An accessibility Raise action alone did not restore the full window in this environment. Do not treat a gesture sent against the thumbnail as functional evidence.
