import AppKit
import Foundation
import UniformTypeIdentifiers
import LeonardoCore

/// Native save-panel actions and portable export adapters for Leonardo files.
extension AppSession {
    struct LeonardoExportIdentity: Sendable {
        let documentURL: URL
        let kind: AppDocumentKind
        let storage: AppDocumentStorage
        let sourceURL: URL?
        let workspaceDirectory: URL?
        let assetRoot: URL?
    }

    func leonardoExportIdentity(for requestedURL: URL) -> LeonardoExportIdentity? {
        guard let currentURL = documentURL?.standardizedFileURL,
              currentURL == requestedURL.standardizedFileURL else { return nil }
        let workspaceDirectory = packageWorkspace?.directoryURL.standardizedFileURL
        let assetRoot = (packageWorkspace?.directoryURL ?? projectURL)?.standardizedFileURL
        return LeonardoExportIdentity(
            documentURL: currentURL,
            kind: documentKind,
            storage: documentStorage,
            sourceURL: documentSourceURL?.standardizedFileURL,
            workspaceDirectory: workspaceDirectory,
            assetRoot: assetRoot
        )
    }

    func leonardoExportIdentityIsCurrent(_ identity: LeonardoExportIdentity) -> Bool {
        documentURL?.standardizedFileURL == identity.documentURL &&
        documentKind.rawValue == identity.kind.rawValue &&
        documentStorage.rawValue == identity.storage.rawValue &&
        documentSourceURL?.standardizedFileURL == identity.sourceURL &&
        packageWorkspace?.directoryURL.standardizedFileURL == identity.workspaceDirectory &&
        (packageWorkspace?.directoryURL ?? projectURL)?.standardizedFileURL == identity.assetRoot
    }

    func leonardoExportMayWrite(
        identity: LeonardoExportIdentity,
        content draft: String,
        snapshotFingerprint: FileFingerprint?
    ) -> Bool {
        busy && fileOperationCount == 1 && !stopped && !isClosing &&
        !isSyncSuspended && !isCapturingPreview && !saving &&
        leonardoExportIdentityIsCurrent(identity) && content == draft &&
        snapshot?.fingerprint == snapshotFingerprint
    }

    func leonardoExportSources(for identity: LeonardoExportIdentity) -> [URL] {
        var sources = [identity.documentURL]
        if identity.storage.rawValue == AppDocumentStorage.package.rawValue,
           let packageURL = identity.sourceURL,
           packageURL != identity.documentURL {
            sources.append(packageURL)
        }
        return sources
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

    /// Panel-free response export adapter used by the native panel callback
    /// and by authorization tests.  The panel wrapper remains responsible
    /// for choosing the destination and allowed extensions.
    func exportLeonardoResponse(
        to destination: URL,
        documentURL: URL,
        panelRequiresPackage: Bool
    ) async {
        guard let identity = leonardoExportIdentity(for: documentURL),
              !stopped, !busy, !saving, !isClosing, !isSyncSuspended,
              !isCapturingPreview, fileOperationCount == 0 else { return }
        fileOperationCount += 1
        var ownsBusy = false
        defer {
            if ownsBusy { busy = false }
            fileOperationCount -= 1
        }
        guard await flushPreviewEdits(), fileOperationCount == 1,
              !stopped, !busy, !saving, !isClosing, !isSyncSuspended,
              !isCapturingPreview, leonardoExportIdentityIsCurrent(identity) else { return }
        busy = true
        ownsBusy = true
        let draft = content
        let snapshotFingerprint = snapshot?.fingerprint
        guard var document = leonardoDocument else { return }
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
            let sources = leonardoExportSources(for: identity)
            if responseURL.pathExtension.lowercased() == "mdlz" {
                let packageURL = responseURL.deletingPathExtension().appendingPathExtension("mdlz")
                try await authorizeLeonardoExport(sources: sources, destinationURL: packageURL)
                guard leonardoExportMayWrite(identity: identity, content: draft, snapshotFingerprint: snapshotFingerprint) else { return }
                try await exportResponsePackage(
                    serialized: serialized,
                    sourceURL: identity.documentURL,
                    to: packageURL,
                    assetRoot: identity.assetRoot
                )
                saveStatus = "Exported · package"
            } else {
                try await authorizeLeonardoExport(sources: sources, destinationURL: responseURL)
                guard leonardoExportMayWrite(identity: identity, content: draft, snapshotFingerprint: snapshotFingerprint) else { return }
                _ = try await documents.save(serialized, to: responseURL)
                saveStatus = "Exported · response"
            }
        } catch {
            report(error)
        }
    }

    private func exportResponsePackage(
        serialized: String,
        sourceURL: URL,
        to packageURL: URL,
        assetRoot: URL?
    ) async throws {
        // The transport only needs the document URL for its root filename and
        // the parent directory used to resolve local assets. The virtual MDLR
        // avoids writing a hidden staging document beside a read-only source.
        let virtualDocumentURL = sourceURL.deletingPathExtension().appendingPathExtension("mdlr")
        try await Task.detached(priority: nil) {
            try LeonardoPackageTransport.export(documentURL: virtualDocumentURL, content: serialized, to: packageURL, assetRoot: assetRoot)
        }.value
    }

    private func containsLocalResources(_ document: LeonardoDocument) -> Bool {
        // Core owns the same Markdown masking and resource grammar used by
        // package export, including HTML and reference-style images. If the
        // detector cannot parse the draft, choose the portable path rather
        // than allowing a potentially non-portable MDLR response.
        (try? LeonardoLocalImagePolicy.hasLocalResources(in: document)) ?? true
    }

    /// Panel-free package export adapter.  The UI wrapper supplies a selected
    /// destination; callers that already have a destination can use this
    /// method without opening a second save panel.
    func exportLeonardoPackage(to destination: URL, documentURL: URL) async {
        guard let identity = leonardoExportIdentity(for: documentURL),
              !stopped, !busy, !saving, !isClosing, !isSyncSuspended,
              !isCapturingPreview, fileOperationCount == 0 else { return }
        fileOperationCount += 1
        var ownsBusy = false
        defer {
            if ownsBusy { busy = false }
            fileOperationCount -= 1
        }
        guard await flushPreviewEdits(), fileOperationCount == 1,
              !stopped, !busy, !saving, !isClosing, !isSyncSuspended,
              !isCapturingPreview, leonardoExportIdentityIsCurrent(identity) else { return }
        busy = true
        ownsBusy = true
        let packageURL = destination.pathExtension.lowercased() == "mdlz"
            ? destination
            : destination.appendingPathExtension("mdlz")
        let draft = content
        let snapshotFingerprint = snapshot?.fingerprint
        do {
            try await authorizeLeonardoExport(
                sources: leonardoExportSources(for: identity),
                destinationURL: packageURL
            )
            guard leonardoExportMayWrite(identity: identity, content: draft, snapshotFingerprint: snapshotFingerprint) else { return }
            try await Task.detached(priority: nil) {
                try LeonardoPackageTransport.export(documentURL: identity.documentURL, content: draft, to: packageURL, assetRoot: identity.assetRoot)
            }.value
            saveStatus = "Exported · package"
        } catch {
            report(error)
        }
    }

    /// Export authorization follows the document identity visible to the
    /// user. A package-backed tab has both a temporary working file and the
    /// original package identity; an explicitly extracted tab owns the
    /// working file and must not silently fall back to the package grant.
    func authorizeLeonardoExport(sources: [URL], destinationURL: URL) async throws {
        for source in sources {
            try await authorizePath(source.standardizedFileURL, .document)
        }
        try await authorizePath(destinationURL.standardizedFileURL, .document)
    }
}
