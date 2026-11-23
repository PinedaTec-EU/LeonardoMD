import Foundation

/// Value snapshots belong to one session; loading content invalidates the history.
struct DocumentEditHistory {
    struct Edit {
        let before: String
        let after: String
        let form: Bool
    }
    var undo: [Edit] = []
    var redo: [Edit] = []
    // Bound retained snapshots for long editing sessions.
    static let maximumEdits = 200

    mutating func record(before: String, after: String, form: Bool) {
        guard before != after else { return }
        undo.append(Edit(before: before, after: after, form: form))
        if undo.count > Self.maximumEdits { undo.removeFirst() }
        redo.removeAll()
    }
}

extension AppSession {
    private func mayRestore(_ edit: DocumentEditHistory.Edit?) -> Bool {
        guard let edit, !saving, fileOperationCount == 0 else { return false }
        return edit.form ? canFillLeonardoForm : canEditDocument
    }
    var canUndoDocument: Bool { mayRestore(editHistory.undo.last) }
    var canRedoDocument: Bool { mayRestore(editHistory.redo.last) }

    func applyDocumentEdit(_ replacement: String, form: Bool) {
        guard content != replacement else { return }
        var history = editHistory
        history.record(before: content, after: replacement, form: form)
        content = replacement
        editHistory = history
        contentChanged()
    }

    /// Commit pending WebKit edits before choosing the entry to restore.
    func undoDocument() async {
        let url = documentURL
        guard !isClosing, !stopped, await flushPreviewEdits(), documentURL == url, canUndoDocument else { return }
        var history = editHistory
        guard let edit = history.undo.popLast(), content == edit.after else { return }
        history.redo.append(edit)
        content = edit.before
        editHistory = history
        contentChanged()
    }

    func redoDocument() async {
        let url = documentURL
        guard !isClosing, !stopped, await flushPreviewEdits(), documentURL == url, canRedoDocument else { return }
        var history = editHistory
        guard let edit = history.redo.popLast(), content == edit.before else { return }
        history.undo.append(edit)
        content = edit.after
        editHistory = history
        contentChanged()
    }
}
