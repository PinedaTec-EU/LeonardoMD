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
    func waitForCloseOperations() async -> Bool {
        while busy || saving || gitBusy || fileOperationCount > 0 || settingsTask != nil || isSyncSuspended || isCapturingPreview {
            if stopped || Task.isCancelled { return false }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return !stopped && !Task.isCancelled
    }

    func toggleProtection() async {
        guard !stopped, !isSyncSuspended, !busy else { return }
        NSApplication.shared.keyWindow?.makeFirstResponder(nil)
        if !isProtected, !(await flushPreviewEdits()) { return }
        isProtected.toggle()
    }

    func flushPreviewEdits() async -> Bool {
        guard await renderer.flushEdits() else {
            errorMessage = L10n.text("Preview edits could not be synchronized. Try again before closing.")
            return false
        }
        return true
    }

    func setDocumentMode(_ value: DocumentMode) async {
        guard !stopped, !busy, !isSyncSuspended else { return }
        let url = documentURL
        NSApplication.shared.keyWindow?.makeFirstResponder(nil)
        guard await flushPreviewEdits(), documentURL == url, !stopped, !isSyncSuspended else { return }
        mode = value
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
