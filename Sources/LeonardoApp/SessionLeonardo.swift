import AppKit
import Foundation
import UniformTypeIdentifiers
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

        var openedWorkspace: LeonardoPackageWorkspace?
        do {
            let workspace = try await Task.detached(priority: nil) {
                try LeonardoPackageTransport.open(packageURL, extractingTo: extraction)
            }.value
            openedWorkspace = workspace
            let loaded = try await documents.read(workspace.documentURL)
            guard !stopped, !isClosing, !isSyncSuspended else {
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

    func migrateMarkdownToLeonardo() async -> Bool {
        guard documentKind == .markdown, let sourceURL = documentURL else { return false }
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
            // Keep the original Markdown bytes as the MDLF body.  This also
            // preserves ordinary YAML front matter inside a Markdown file;
            // Leonardo metadata is the only front matter this wrapper owns.
            let serialized = try LeonardoFormatParser.serialize(
                LeonardoDocument(body: content, metadata: metadata)
            )
            let saved = try await documents.save(serialized, to: destination)
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
        } catch {
            report(error)
            return false
        }
    }

    func exportLeonardoPackage() {
        guard let documentURL, documentKind.isLeonardo else { return }
        let panel = NSSavePanel()
        panel.title = L10n.text("Export Leonardo package")
        panel.nameFieldStringValue = documentURL.deletingPathExtension().lastPathComponent + ".mdlz"
        panel.allowedContentTypes = [UTType(filenameExtension: "mdlz") ?? .data]
        presentFilePanel(panel) { [weak self] destination in
            Task { await self?.exportLeonardoPackage(to: destination, documentURL: documentURL) }
        }
    }

    func exportLeonardoResponse() {
        guard let documentURL, let document = leonardoDocument, document.isForm else { return }
        let hasLocalResources = containsLocalResources(document)
        let panel = NSSavePanel()
        panel.title = L10n.text("Export Leonardo response")
        panel.nameFieldStringValue = documentURL.deletingPathExtension().lastPathComponent + (hasLocalResources ? ".mdlz" : ".mdlr")
        let responseType = UTType(filenameExtension: "mdlr") ?? .plainText
        let packageType = UTType(filenameExtension: "mdlz") ?? .data
        // A response containing local assets must be portable. Keep the
        // panel's selected destination aligned with that decision so the
        // callback never silently changes `foo.mdlr` into `foo.mdlz`.
        panel.allowedContentTypes = hasLocalResources ? [packageType] : [responseType, packageType]
        presentFilePanel(panel) { [weak self] destination in
            Task {
                await self?.exportLeonardoResponse(
                    to: destination,
                    documentURL: documentURL,
                    panelRequiresPackage: hasLocalResources
                )
            }
        }
    }

    private func exportLeonardoResponse(
        to destination: URL,
        documentURL: URL,
        panelRequiresPackage: Bool
    ) async {
        guard self.documentURL == documentURL, !stopped, !busy, !isClosing else { return }
        guard await flushPreviewEdits(), self.documentURL == documentURL,
              var document = leonardoDocument else { return }
        let destinationExtension = destination.pathExtension.lowercased()
        let hasLocalResources = containsLocalResources(document)
        if (panelRequiresPackage || hasLocalResources) && destinationExtension != "mdlz" {
            // This can only happen when a preview edit becomes visible after
            // the panel was configured, or when AppKit returns a manually
            // overridden extension. Never redirect the export to a sibling
            // path without showing that path in a save panel first.
            let derivedPackageURL = destination.deletingPathExtension().appendingPathExtension("mdlz")
            errorMessage = FileManager.default.fileExists(atPath: derivedPackageURL.path)
                ? L10n.text("The MDLZ destination already exists. Choose another name.")
                : L10n.text("Forms with local resources must be exported as an MDLZ package. Choose an MDLZ destination.")
            return
        }
        let responseURL = ["mdlr", "mdlz"].contains(destinationExtension)
            ? destination
            : destination.appendingPathExtension("mdlr")
        do {
            document.metadata.document.kind = .form
            let serialized = try LeonardoFormatParser.serialize(document)
            if responseURL.pathExtension.lowercased() == "mdlz" {
                let packageURL = responseURL.deletingPathExtension().appendingPathExtension("mdlz")
                try await exportResponsePackage(serialized: serialized, sourceURL: documentURL, to: packageURL)
                saveStatus = "Exported · package"
            } else {
                _ = try await documents.save(serialized, to: responseURL)
                saveStatus = "Exported · response"
            }
        } catch {
            report(error)
        }
    }

    private func exportResponsePackage(serialized: String, sourceURL: URL, to packageURL: URL) async throws {
        // The transport only needs the document URL for its root filename and
        // the parent directory used to resolve local assets. The virtual MDLR
        // avoids writing a hidden staging document beside a read-only source.
        let virtualDocumentURL = sourceURL.deletingPathExtension().appendingPathExtension("mdlr")
        let assetRoot = packageWorkspace?.directoryURL ?? projectURL
        try await Task.detached(priority: nil) {
            try LeonardoPackageTransport.export(documentURL: virtualDocumentURL, content: serialized, to: packageURL, assetRoot: assetRoot)
        }.value
    }

    private func containsLocalResources(_ document: LeonardoDocument) -> Bool {
        var references: [String] = []
        if let regex = try? NSRegularExpression(pattern: #"!\[[^\]\n]*\]\(\s*<?([^>\s)]+)"#) {
            let range = NSRange(document.body.startIndex..., in: document.body)
            references += regex.matches(in: document.body, range: range).compactMap {
                guard $0.numberOfRanges > 1, let valueRange = Range($0.range(at: 1), in: document.body) else { return nil }
                return String(document.body[valueRange])
            }
        }
        if let layout = document.metadata.layout {
            references += layout.images.map(\.source)
            if let image = layout.background?.image { references.append(image) }
        }
        return references.contains { reference in
            guard !reference.isEmpty, !reference.hasPrefix("#") else { return false }
            let scheme = URL(string: reference)?.scheme?.lowercased()
            return scheme == nil || scheme == "file"
        }
    }

    private func exportLeonardoPackage(to destination: URL, documentURL: URL) async {
        guard self.documentURL == documentURL, !stopped, !busy, !isClosing else { return }
        guard await flushPreviewEdits(), self.documentURL == documentURL else { return }
        let packageURL = destination.pathExtension.lowercased() == "mdlz"
            ? destination
            : destination.appendingPathExtension("mdlz")
        let draft = content
        let assetRoot = packageWorkspace?.directoryURL ?? projectURL
        do {
            try await Task.detached(priority: nil) {
                try LeonardoPackageTransport.export(documentURL: documentURL, content: draft, to: packageURL, assetRoot: assetRoot)
            }.value
            saveStatus = "Exported · package"
        } catch {
            report(error)
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
