import AppKit

// The decision is shared by navigation, tab/window close and application quit.
enum UnsavedChangesDecision { case save, discard, cancel }

enum PendingPreviewEditsPolicy {
    case flush
    case alreadyResolved
    case discardAfterExplicitCloseConfirmation

    var requiresFlush: Bool {
        if case .flush = self { return true }
        return false
    }
}

enum PreviewCloseResolution: Equatable {
    case readyToClose
    case discardPreviewEdits
    case keepOpen
}

enum UnsavedChangesPrompt {
    @MainActor static func show(_ filename: String, on window: NSWindow? = nil) async -> UnsavedChangesDecision {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L10n.format("Save changes to %@?", filename)
        alert.informativeText = L10n.text("Your changes have not been saved. Discarding cannot be undone.")
        alert.addButton(withTitle: L10n.text("Save"))
        alert.addButton(withTitle: L10n.text("Cancel"))
        alert.addButton(withTitle: L10n.text("Discard changes"))
        switch await NativeDialog.present(alert, on: window) {
        case .alertFirstButtonReturn: return .save
        case .alertThirdButtonReturn: return .discard
        default: return .cancel
        }
    }
}

extension AppSession {
    func waitForCloseOperations() async -> Bool {
        while busy || saving || saveTask != nil || gitBusy || fileOperationCount > 0 || settingsTask != nil || isSyncSuspended || isCapturingPreview {
            if stopped || Task.isCancelled { return false }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return !stopped && !Task.isCancelled
    }

    func toggleProtection() async {
        guard !stopped, !isClosing, !isSyncSuspended, !busy else { return }
        fileOperationCount += 1
        defer { fileOperationCount -= 1 }
        NSApplication.shared.keyWindow?.makeFirstResponder(nil)
        if !isProtected, !(await flushPreviewEdits()) { return }
        guard !isClosing, !stopped else { return }
        isProtected.toggle()
    }

    func flushPreviewEdits() async -> Bool {
        guard await renderer.flushEdits() else {
            let alert = Self.previewEditsSynchronizationWarning()
            _ = await NativeDialog.present(alert, on: presentationWindow)
            return false
        }
        return true
    }

    func resolvePreviewEditsBeforeClose(
        documentName: String,
        onRecoveryPrompt: @MainActor () -> Void
    ) async -> PreviewCloseResolution {
        let synchronized = await renderer.flushEdits()
        isClosePreviewSyncPending = false
        guard !synchronized else { return .readyToClose }

        onRecoveryPrompt()
        let alert = Self.previewEditsCloseWarning(documentName: documentName)

        switch await NativeDialog.present(alert, on: presentationWindow) {
        case .alertFirstButtonReturn: return .keepOpen
        case .alertSecondButtonReturn: return .discardPreviewEdits
        default: return .keepOpen
        }
    }

    static func previewEditsSynchronizationWarning() -> NSAlert {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L10n.text("Could not apply preview edits")
        alert.informativeText = L10n.text("The latest changes in Preview were not applied. Keep the document open and try again.")
        alert.addButton(withTitle: L10n.text("OK"))
        return alert
    }

    static func previewEditsCloseWarning(documentName: String) -> NSAlert {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L10n.text("Could not apply preview edits")
        alert.informativeText = L10n.format(
            "Some edits in %@ are still only in Preview. Keep it open and retry, or discard them and close the document.",
            documentName
        )
        alert.addButton(withTitle: L10n.text("Keep Open")).keyEquivalent = "\u{1b}"
        alert.addButton(withTitle: L10n.text("Discard Preview Changes")).hasDestructiveAction = true
        return alert
    }

    func setDocumentMode(_ value: DocumentMode) async {
        guard !stopped, !isClosing, !busy, !isSyncSuspended else { return }
        fileOperationCount += 1
        defer { fileOperationCount -= 1 }
        let url = documentURL
        NSApplication.shared.keyWindow?.makeFirstResponder(nil)
        guard await flushPreviewEdits(), documentURL == url, !stopped, !isClosing, !isSyncSuspended else { return }
        mode = value
        if value != .fill { selectedLeonardoFieldID = nil }
    }

    @discardableResult
    func editDocument(expected: String, replacement: String) -> Bool {
        guard canEditDocument, content == expected else { return false }
        applyDocumentEdit(replacement, form: false)
        return true
    }

    /// The close preparation gate permits the renderer's final snapshot only;
    /// native editing remains blocked while the session is closing.
    func editPreviewDocument(expected: String, replacement: String) -> Bool {
        let canApplyCloseSnapshot = isClosing && isClosePreviewSyncPending && canEditDocumentIgnoringClose
        guard canEditDocument || canApplyCloseSnapshot, content == expected else { return false }
        applyDocumentEdit(replacement, form: false)
        return true
    }

    func resolveUnsavedChanges(pendingPreviewEdits: PendingPreviewEditsPolicy = .flush) async -> Bool {
        guard isDirty else { return true }
        switch await unsavedChangesDecision(documentURL?.lastPathComponent ?? "LeonardoMD") {
        case .cancel: return false
        case .save:
            await save(allowClosing: true, pendingPreviewEdits: pendingPreviewEdits)
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
