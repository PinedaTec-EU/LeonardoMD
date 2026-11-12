import AppKit
import Foundation
import UniformTypeIdentifiers
import LeonardoCore

/// Conflict recovery retains package resources and commits only a verified replacement.
extension AppSession {
    func saveCopy() {
        guard let url = documentURL else { return }
        let panel = NSSavePanel()
        let name = (documentSourceURL ?? url).deletingPathExtension().lastPathComponent
            + L10n.text("Copy filename suffix")
        if documentStorage == .package {
            panel.nameFieldStringValue = (name as NSString).deletingPathExtension + ".mdlz"
            panel.allowedContentTypes = [UTType(filenameExtension: "mdlz") ?? .data]
        } else {
            panel.nameFieldStringValue = name
        }
        presentFilePanel(panel) { [weak self] destination in
            self?.saveCopy(to: destination, sourceURL: url)
        }
    }

    func saveCopy(to destination: URL, sourceURL: URL) {
        Task { await saveCopyAndOpen(to: destination, sourceURL: sourceURL) }
    }

    func saveCopyAndOpen(to destination: URL, sourceURL: URL) async {
        guard let identity = leonardoExportIdentity(for: sourceURL),
              !stopped, !busy, !saving, !isClosing, !isSyncSuspended,
              !isCapturingPreview, fileOperationCount == 0 else { return }
        let canonicalDestination = ProcessFileLock.canonicalURL(destination)
        guard !leonardoExportSources(for: identity).contains(where: {
            ProcessFileLock.canonicalURL($0) == canonicalDestination
        }) else {
            errorMessage = L10n.text("Choose another file to keep both versions.")
            return
        }
        if identity.storage == .package,
           let directory = identity.workspaceDirectory,
           case let workspace = ProcessFileLock.canonicalURL(directory),
           canonicalDestination.path.hasPrefix(workspace.path + "/") {
            errorMessage = L10n.text("Choose another file to keep both versions.")
            return
        }
        guard identity.storage != .package || destination.pathExtension.lowercased() == "mdlz" else {
            errorMessage = L10n.text("Save a package conflict copy as MDLZ to preserve its resources.")
            return
        }
        fileOperationCount += 1
        var ownsBusy = false
        defer {
            if ownsBusy { busy = false }
            fileOperationCount -= 1
        }
        NSApplication.shared.keyWindow?.makeFirstResponder(nil)
        guard await flushPreviewEdits(), !stopped, !busy, !saving, !isClosing,
              !isSyncSuspended, !isCapturingPreview, fileOperationCount == 1,
              leonardoExportIdentityIsCurrent(identity) else { return }
        busy = true
        ownsBusy = true
        let draft = content
        let fingerprint = snapshot?.fingerprint
        do {
            try await authorizeLeonardoExport(sources: leonardoExportSources(for: identity), destinationURL: destination)
            guard leonardoExportMayWrite(identity: identity, content: draft, snapshotFingerprint: fingerprint) else { return }
            if identity.storage == .package {
                try await savePackageConflictCopy(to: destination, identity: identity, draft: draft, fingerprint: fingerprint)
            } else {
                let copy = try await documents.save(draft, to: destination)
                guard leonardoExportMayWrite(identity: identity, content: draft, snapshotFingerprint: fingerprint) else { return }
                let previousWorkspace = packageWorkspace
                adoptConflictCopy(copy, package: nil, sourceURL: destination)
                if let previousWorkspace { await disposePackageWorkspace(previousWorkspace) }
            }
        } catch { report(error) }
    }

    private func savePackageConflictCopy(
        to destination: URL,
        identity: LeonardoExportIdentity,
        draft: String,
        fingerprint: FileFingerprint?
    ) async throws {
        let previousWorkspace = packageWorkspace
        let previousMode = mode
        var replacement: LeonardoPackageWorkspace?
        defer {
            if let replacement { queuePackageWorkspaceDisposal(replacement) }
        }
        try await Task.detached(priority: nil) {
            try LeonardoPackageTransport.export(
                documentURL: identity.documentURL, content: draft,
                to: destination, assetRoot: identity.assetRoot
            )
        }.value
        guard leonardoExportMayWrite(identity: identity, content: draft, snapshotFingerprint: fingerprint) else { return }
        let workspace = try await Task.detached(priority: nil) {
            try LeonardoPackageTransport.open(destination, extractingTo: nil)
        }.value
        replacement = workspace
        let loaded = try await documents.read(workspace.documentURL)
        _ = try LeonardoFormatParser.parse(loaded.content)
        guard leonardoExportMayWrite(identity: identity, content: draft, snapshotFingerprint: fingerprint) else { return }
        adoptConflictCopy(loaded, package: workspace, sourceURL: destination)
        if previousMode == .fill, availableDocumentModes.contains(.fill) { mode = .fill }
        replacement = nil
        if let previousWorkspace { await disposePackageWorkspace(previousWorkspace) }
    }

    private func adoptConflictCopy(_ copy: DocumentSnapshot, package: LeonardoPackageWorkspace?, sourceURL: URL) {
        projectURL = nil
        projectConfiguration = .default
        projectBaseline = .default
        rootEntries = []
        resetSearch()
        focus = false
        documentURL = copy.url
        documentSourceURL = package == nil ? nil : sourceURL.standardizedFileURL
        packageWorkspace = package
        documentKind = AppDocumentKind.classify(copy.url)
        documentStorage = package == nil ? .localFile : .package
        leonardoFormatWarning = false
        snapshot = copy
        content = copy.content
        externalConflict = false
        errorMessage = nil
        isProtected = true
        editorScroll = 0
        requestedLine = nil
        mode = documentKind.defaultMode(global: resolved.defaultMode)
        selectedLeonardoFieldID = nil
        saveStatus = package == nil ? "Saved · local file" : "Saved · package"
        NSDocumentController.shared.noteNewRecentDocumentURL(sourceURL)
        updateTitle()
    }
}
