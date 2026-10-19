import AppKit
import Foundation
import LeonardoCore

/// App-side lifecycle and editing adapters for the open Leonardo format.
/// `LeonardoCore` remains the owner of the wire schema; this file only maps
/// that schema to session state and native macOS controls.
extension DocumentTabs {
    func configureLeonardoTransport(for session: AppSession) {
        session.openPackageDocument = { [weak session] packageURL, preference in
            guard let session else { return false }
            return await session.openLeonardoPackage(packageURL, preference: preference)
        }
        session.migrateMarkdownDocument = { [weak session] in
            guard let session else { return false }
            return await session.migrateMarkdownToLeonardo()
        }
    }
}

extension AppSession {
    /// Switch an open package to a user-owned extracted workspace.  The
    /// current package workspace remains alive until the replacement has
    /// loaded successfully, so cancelling the destination panel or failing
    /// to read the extracted document leaves the current tab usable.
    func extractLeonardoPackageToFolder() {
        guard documentStorage == .package,
              let packageURL = documentSourceURL,
              !stopped, !isClosing, !busy, !isSyncSuspended else { return }

        Task { [weak self] in
            guard let self else { return }
            guard await prepareNavigation() else { return }
            guard documentStorage == .package,
                  documentSourceURL == packageURL,
                  !stopped, !isClosing, !busy, !isSyncSuspended else { return }

            let previousWorkspace = packageWorkspace
            let previousMode = mode
            busy = true
            defer { busy = false }
            guard await openLeonardoPackage(packageURL, preference: .extracted) else { return }

            // A recipient may already be filling the form when choosing to
            // extract it. Keep that intent after the document identity moves
            // from the temporary package workspace to the user-owned folder.
            if previousMode == .fill, availableDocumentModes.contains(.fill) {
                mode = .fill
                showInspector = true
            }
            if let previousWorkspace {
                LeonardoPackageTransport.discard(previousWorkspace)
            }
        }
    }

    func openLeonardoPackage(
        _ packageURL: URL,
        preference: LeonardoPackageOpenPreference
    ) async -> Bool {
        let extraction: URL?
        switch preference {
        case .package:
            extraction = nil
        case .extracted:
            guard let destination = choosePackageExtractionDestination(for: packageURL) else { return false }
            extraction = destination
        case .ask:
            guard let choice = choosePackageOpenMode(for: packageURL) else { return false }
            if choice == .package {
                extraction = nil
            } else {
                guard let destination = choosePackageExtractionDestination(for: packageURL) else { return false }
                extraction = destination
            }
        }

        return await openLeonardoPackage(packageURL, extractingTo: extraction)
    }

    /// Opens a package with a caller-supplied extraction destination.  The
    /// preference-facing overload above owns AppKit's panels; this adapter is
    /// deliberately panel-free so tests, automation, and future agents can
    /// exercise the same authorization and transport path deterministically.
    func openLeonardoPackage(_ packageURL: URL, extractingTo extraction: URL?) async -> Bool {
        guard !stopped, !isClosing, !isSyncSuspended else { return false }
        // `open(_:)` owns the normal busy flag while this adapter runs.  Do
        // not reject that caller, but remember the surrounding identity so an
        // authorization callback cannot switch the tab before transport
        // writes the extracted workspace.
        let expectedDocumentURL = documentURL?.standardizedFileURL
        let expectedSourceURL = documentSourceURL?.standardizedFileURL
        let expectedKind = documentKind.rawValue
        let expectedStorage = documentStorage.rawValue
        let expectedOperationCount = fileOperationCount

        var openedWorkspace: LeonardoPackageWorkspace?
        do {
            // The package remains the source identity even when the
            // transport materializes a temporary working document. An
            // explicit extraction creates a directory tree, so authorize
            // that mutation before the transport writes its first byte.
            try await authorizePath(packageURL, .document)
            if let extraction {
                try await authorizePath(extraction, .directoryMutation)
            }
            guard !stopped, !isClosing, !isSyncSuspended,
                  fileOperationCount == expectedOperationCount,
                  documentURL?.standardizedFileURL == expectedDocumentURL,
                  documentSourceURL?.standardizedFileURL == expectedSourceURL,
                  documentKind.rawValue == expectedKind,
                  documentStorage.rawValue == expectedStorage else { return false }
            let workspace = try await Task.detached(priority: nil) {
                try LeonardoPackageTransport.open(packageURL, extractingTo: extraction)
            }.value
            openedWorkspace = workspace
            let loaded = try await documents.read(workspace.documentURL)
            guard !stopped, !isClosing, !isSyncSuspended,
                  fileOperationCount == expectedOperationCount,
                  documentURL?.standardizedFileURL == expectedDocumentURL,
                  documentSourceURL?.standardizedFileURL == expectedSourceURL,
                  documentKind.rawValue == expectedKind,
                  documentStorage.rawValue == expectedStorage else {
                LeonardoPackageTransport.discard(workspace)
                openedWorkspace = nil
                return false
            }

            let kind = AppDocumentKind.classify(workspace.documentURL)
            let parsed = try? LeonardoFormatParser.parse(loaded.content)
            let nextMode: DocumentMode
            if kind == .leonardoResponse {
                nextMode = .fill
            } else {
                nextMode = kind.defaultMode(global: resolved.defaultMode)
            }
            packageWorkspace = workspace
            documentURL = workspace.documentURL
            documentSourceURL = packageURL.standardizedFileURL
            documentKind = kind
            documentStorage = extraction == nil ? .package : .extracted
            snapshot = loaded
            content = loaded.content
            isProtected = true
            editorScroll = 0
            requestedLine = nil
            externalConflict = false
            leonardoFormatWarning = false
            mode = nextMode
            if nextMode == .fill || parsed?.isForm == true { showInspector = true }
            saveStatus = extraction == nil ? "Saved · package" : "Saved · extracted folder"
            NSDocumentController.shared.noteNewRecentDocumentURL(extraction == nil ? packageURL : workspace.documentURL)
            openedWorkspace = nil
            updateTitle()
            return true
        } catch {
            if let openedWorkspace {
                LeonardoPackageTransport.discard(openedWorkspace)
            }
            report(error)
            return false
        }
    }

    private func choosePackageOpenMode(for packageURL: URL) -> LeonardoPackageOpenPreference? {
        let alert = NSAlert()
        alert.messageText = L10n.text("Open Leonardo package")
        alert.informativeText = packageURL.lastPathComponent
        alert.addButton(withTitle: L10n.text("Open package and save it as a package"))
        alert.addButton(withTitle: L10n.text("Extract into a folder"))
        alert.addButton(withTitle: L10n.text("Cancel"))
        switch alert.runModal() {
        case .alertFirstButtonReturn: return .package
        case .alertSecondButtonReturn: return .extracted
        default: return nil
        }
    }

    /// Selects a new folder path without creating it.  The Core transport
    /// deliberately rejects existing destinations so an extraction cannot
    /// overwrite an unrelated folder.
    private func choosePackageExtractionDestination(for packageURL: URL) -> URL? {
        let panel = NSSavePanel()
        panel.title = L10n.text("Extract Leonardo package")
        panel.message = L10n.text("Choose a new folder for the package contents.")
        panel.nameFieldStringValue = packageURL.deletingPathExtension().lastPathComponent
        panel.directoryURL = packageURL.deletingLastPathComponent()
        panel.canCreateDirectories = false
        return panel.runModal() == .OK ? panel.url : nil
    }

    func migrateMarkdownToLeonardo(
        allowSaveReentry: Bool = false,
        allowClosing: Bool = false
    ) async -> Bool {
        guard documentKind == .markdown, let sourceURL = documentURL,
              !stopped, (!isClosing || allowClosing), !isSyncSuspended,
              !externalConflict,
              !busy, !saving else { return false }

        // `save()` owns one file-operation slot while it invokes the
        // migration preference. Direct UI migration must be idle; the only
        // permitted re-entry is that exact save path.
        let calledFromSave = allowSaveReentry && fileOperationCount == 1
        guard calledFromSave || (!allowSaveReentry && fileOperationCount == 0) else { return false }

        let ownsOperation = !calledFromSave
        if ownsOperation { fileOperationCount += 1 }
        var ownsBusy = false
        defer {
            if ownsBusy { busy = false }
            if ownsOperation { fileOperationCount -= 1 }
        }

        NSApplication.shared.keyWindow?.makeFirstResponder(nil)
        guard await flushPreviewEdits(),
              documentKind == .markdown,
              documentURL == sourceURL,
              !stopped, (!isClosing || allowClosing), !isSyncSuspended,
              !externalConflict, !busy,
              let sourceSnapshot = snapshot,
              sourceSnapshot.url.standardizedFileURL == sourceURL.standardizedFileURL else { return false }
        // Keep the preview editable while its asynchronous DOM-to-native
        // bridge is flushed. Lock the session only after the latest content
        // has reached `content` and the source snapshot is captured.
        busy = true
        ownsBusy = true

        let destination = sourceURL.deletingPathExtension().appendingPathExtension("mdlf")
        if FileManager.default.fileExists(atPath: destination.path) {
            errorMessage = L10n.text("The MDLF destination already exists. Choose another name before migrating.")
            return false
        }
        let metadata = LeonardoMetadata(
            document: LeonardoDocumentDescriptor(
                title: sourceURL.deletingPathExtension().lastPathComponent,
                kind: .document
            )
        )
        do {
            // Authorize both identities before the exclusive destination
            // create. `createNew(preserving:)` performs the final source
            // fingerprint check, closing the race after this authorization.
            try await authorizePath(sourceURL, .document)
            try await authorizePath(destination, .document)
            guard documentKind == .markdown,
                  documentURL == sourceURL,
                  snapshot?.fingerprint == sourceSnapshot.fingerprint,
                  !stopped, (!isClosing || allowClosing), !isSyncSuspended,
                  !externalConflict, ownsBusy else { return false }

            // Keep the original Markdown bytes as the MDLF body. This also
            // preserves ordinary YAML front matter inside a Markdown file;
            // Leonardo metadata is the only front matter this wrapper owns.
            let serialized = try LeonardoFormatParser.serialize(
                LeonardoDocument(body: content, metadata: metadata)
            )
            let saved = try await documents.createNew(serialized, to: destination, preserving: sourceSnapshot)
            documentURL = destination
            documentSourceURL = nil
            documentKind = .leonardoTemplate
            documentStorage = .localFile
            packageWorkspace = nil
            snapshot = saved
            content = serialized
            externalConflict = false
            leonardoFormatWarning = false
            isProtected = true
            mode = .preview
            saveStatus = "Saved · local file"
            NSDocumentController.shared.noteNewRecentDocumentURL(destination)
            updateTitle()
            return true
        } catch let error as FileSystemRepositoryError {
            if case .itemAlreadyExists = error {
                errorMessage = L10n.text("The MDLF destination already exists. Choose another name before migrating.")
            } else {
                report(error)
            }
            return false
        } catch DocumentStoreError.conflict {
            externalConflict = true
            saveStatus = "External conflict · edits protected"
            errorMessage = L10n.text("The Markdown source changed on disk. Reload it before migrating.")
            return false
        } catch {
            report(error)
            return false
        }
    }

}

extension AppSession {
    var leonardoDocument: LeonardoDocument? {
        guard documentKind.isLeonardo else { return nil }
        return try? LeonardoFormatParser.parse(content)
    }

    var leonardoFieldIDs: [String] {
        leonardoDocument?.metadata.fields.keys.sorted() ?? []
    }

    func leonardoFieldDefinition(_ fieldID: String) -> LeonardoFieldDefinition? {
        leonardoDocument?.metadata.fields[fieldID]
    }

    func leonardoFieldValue(_ fieldID: String) -> LeonardoJSONValue? {
        guard let document = leonardoDocument,
              let definition = document.metadata.fields[fieldID] else { return nil }
        return document.metadata.values[fieldID] ?? definition.defaultValue
    }

    func leonardoFieldText(_ fieldID: String) -> String {
        guard let value = leonardoFieldValue(fieldID) else { return "" }
        switch value {
        case .string(let value): return value
        case .number(let value): return String(value)
        case .boolean(let value): return value ? "true" : "false"
        case .array, .object: return ""
        case .null: return ""
        }
    }

    func leonardoFieldBool(_ fieldID: String) -> Bool {
        leonardoFieldValue(fieldID)?.booleanValue ?? false
    }

    func leonardoFieldDiagnostics(_ fieldID: String) -> [LeonardoDiagnostic] {
        guard let document = leonardoDocument else { return [] }
        return LeonardoFormatValidator.validate(document, context: .draft).filter { $0.fieldID == fieldID }
    }

    @discardableResult
    func updateLeonardoField(_ fieldID: String, text: String) -> Bool {
        guard let definition = leonardoFieldDefinition(fieldID) else { return false }
        let value: LeonardoJSONValue
        if definition.type == .number, let number = Double(text.trimmingCharacters(in: .whitespacesAndNewlines)), number.isFinite {
            value = .number(number)
        } else if definition.type == .number, text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            value = .null
        } else {
            value = .string(text)
        }
        return updateLeonardoField(fieldID, value: value, definition: definition)
    }

    @discardableResult
    func updateLeonardoCheckbox(_ fieldID: String, value: Bool) -> Bool {
        guard let definition = leonardoFieldDefinition(fieldID), definition.type == .checkbox else { return false }
        return updateLeonardoField(fieldID, value: .boolean(value), definition: definition)
    }

    private func updateLeonardoField(
        _ fieldID: String,
        value: LeonardoJSONValue,
        definition: LeonardoFieldDefinition
    ) -> Bool {
        guard documentURL != nil, documentKind.isLeonardo, !definition.readOnly,
              mode == .fill, !stopped, !isClosing, !busy, !isSyncSuspended,
              var document = leonardoDocument else { return false }
        document.metadata.values[fieldID] = value
        guard let replacement = try? LeonardoFormatParser.serialize(document) else { return false }
        content = replacement
        contentChanged()
        return true
    }
}
