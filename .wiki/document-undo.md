# Document editing history

[Issue #230](https://github.com/PinedaTec-EU/LeonardoMD/issues/230) / [PR #231](https://github.com/PinedaTec-EU/LeonardoMD/pull/231) introduce per-session Undo/Redo in `DocumentEditHistory.swift`. `editDocument` and `updateLeonardoFields` record successful nonempty edits. Restoring an entry reuses `contentChanged` so dirty state follows the saved snapshot.

The `content` setter invalidates history for non-edit replacements; the edit/restore boundary explicitly preserves its updated value history. `documentURL` changes also invalidate it. Save preserves history unless it migrates the format. Raw NSTextView disables its independent history inside WorkspaceView. Menu actions route unrelated native text controls to their own UndoManager. Toolbar and menu restore source or form entries only with the matching current permission.

Keep this boundary shared when adding another document mutation surface; do not introduce another parallel undo stack. See [behavior and validation](../doc/validation/document-undo.md).
