import AppKit

// The decision is shared by navigation, tab/window close and application quit.
enum UnsavedChangesDecision { case save, discard, cancel }

enum UnsavedChangesPrompt {
    @MainActor static func show(_ filename: String) -> UnsavedChangesDecision {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L10n.format("Save changes to %@?", filename)
        alert.informativeText = L10n.text("Your changes have not been saved. Discarding cannot be undone.")
        alert.addButton(withTitle: L10n.text("Save"))
        alert.addButton(withTitle: L10n.text("Cancel"))
        alert.addButton(withTitle: L10n.text("Discard changes"))
        switch alert.runModal() {
        case .alertFirstButtonReturn: return .save
        case .alertThirdButtonReturn: return .discard
        default: return .cancel
        }
    }
}

extension AppSession {
    func toggleProtection() {
        guard !stopped, !isSyncSuspended, !busy else { return }
        NSApplication.shared.keyWindow?.makeFirstResponder(nil)
        isProtected.toggle()
    }

    @discardableResult
    func editDocument(expected: String, replacement: String) -> Bool {
        guard canEditDocument, content == expected else { return false }
        content = replacement
        contentChanged()
        return true
    }

    func resolveUnsavedChanges() async -> Bool {
        guard isDirty else { return true }
        switch unsavedChangesDecision(documentURL?.lastPathComponent ?? "LeonardoMD") {
        case .cancel: return false
        case .save:
            await save()
            return !isDirty
        case .discard:
            guard let snapshot else { return false }
            content = snapshot.content
            externalConflict = false
            saveStatus = "Saved · local file"
            updateTitle()
            return true
        }
    }
}
