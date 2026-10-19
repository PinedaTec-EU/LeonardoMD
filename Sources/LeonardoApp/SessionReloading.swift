import AppKit
import Foundation
import LeonardoCore

/// Reloading a package must rebuild its temporary workspace from the package
/// identity. Reading the old extracted file would hide changes made to the
/// transport file and leave the next save with a stale source digest.
extension AppSession {
    private struct PackageReloadIdentity {
        let documentURL: URL
        let sourceURL: URL
        let documentKind: AppDocumentKind
        let documentStorage: AppDocumentStorage
        let projectURL: URL?
        let workspace: LeonardoPackageWorkspace
        let snapshot: DocumentSnapshot?
        let content: String
    }

    private func reloadSameURL(_ lhs: URL?, _ rhs: URL?) -> Bool {
        lhs?.standardizedFileURL == rhs?.standardizedFileURL
    }

    private func reloadSameWorkspace(_ expected: LeonardoPackageWorkspace) -> Bool {
        guard let actual = packageWorkspace else { return false }
        return reloadSameURL(actual.packageURL, expected.packageURL) &&
            actual.directoryURL.standardizedFileURL == expected.directoryURL.standardizedFileURL &&
            actual.documentURL.standardizedFileURL == expected.documentURL.standardizedFileURL
    }

    private func packageReloadIdentity() -> PackageReloadIdentity? {
        guard documentStorage == .package,
              let documentURL,
              let sourceURL = documentSourceURL,
              let workspace = packageWorkspace,
              workspace.packageURL != nil else { return nil }
        return PackageReloadIdentity(
            documentURL: documentURL.standardizedFileURL,
            sourceURL: sourceURL.standardizedFileURL,
            documentKind: documentKind,
            documentStorage: documentStorage,
            projectURL: projectURL?.standardizedFileURL,
            workspace: workspace,
            snapshot: snapshot,
            content: content
        )
    }

    private func packageReloadMayApply(_ identity: PackageReloadIdentity) -> Bool {
        !stopped && !isSyncSuspended && !isClosing && busy &&
            reloadSameURL(documentURL, identity.documentURL) &&
            reloadSameURL(documentSourceURL, identity.sourceURL) &&
            documentKind == identity.documentKind &&
            documentStorage == identity.documentStorage &&
            reloadSameURL(projectURL, identity.projectURL) &&
            reloadSameWorkspace(identity.workspace) &&
            snapshot == identity.snapshot && content == identity.content
    }

    private func reloadPackage(_ identity: PackageReloadIdentity) async {
        var replacement: LeonardoPackageWorkspace?
        defer {
            if let replacement { LeonardoPackageTransport.discard(replacement) }
        }
        do {
            try await authorizePath(identity.sourceURL, .document)
            guard packageReloadMayApply(identity) else { return }
            let workspace = try await Task.detached(priority: nil) {
                try LeonardoPackageTransport.open(identity.sourceURL, extractingTo: nil)
            }.value
            replacement = workspace
            let loaded = try await documents.read(workspace.documentURL)
            let parsed = try LeonardoFormatParser.parse(loaded.content)
            guard packageReloadMayApply(identity) else { return }

            let kind = AppDocumentKind.classify(workspace.documentURL)
            let nextMode: DocumentMode
            if kind == .leonardoResponse {
                nextMode = .fill
            } else if mode == .fill, parsed.isForm {
                nextMode = .fill
            } else {
                nextMode = kind.defaultMode(global: resolved.defaultMode)
            }
            packageWorkspace = workspace
            documentURL = workspace.documentURL
            documentSourceURL = identity.sourceURL
            documentKind = kind
            documentStorage = .package
            snapshot = loaded
            content = loaded.content
            externalConflict = false
            errorMessage = nil
            leonardoFormatWarning = false
            mode = nextMode
            saveStatus = "Saved · package"
            replacement = nil
            LeonardoPackageTransport.discard(identity.workspace)
            updateTitle()
        } catch {
            // An authorization/read/parse callback may have moved the tab to
            // another document.  Preserve that newer identity and discard
            // only the replacement workspace in the defer above.
            guard packageReloadMayApply(identity) else { return }
            externalConflict = true
            saveStatus = "External conflict · edits protected"
            report(error)
        }
    }

    private func reloadLocalDocument(
        _ url: URL,
        previousContent: String
    ) async {
        do {
            let loaded = try await documents.read(url)
            guard !stopped, !isSyncSuspended, documentURL == url else { return }
            guard content == previousContent else {
                externalConflict = true
                saveStatus = "External conflict · edits protected"
                return
            }
            snapshot = loaded
            content = loaded.content
            externalConflict = false
            saveStatus = "Saved · local file"
            updateTitle()
        } catch {
            externalConflict = true
            report(error)
        }
    }

    func reloadFromDisk() async {
        guard !isSyncSuspended, !busy, !saving, !isClosing else { return }
        NSApplication.shared.keyWindow?.makeFirstResponder(nil)
        guard await flushPreviewEdits(), !isSyncSuspended, !busy, !saving, !isClosing else { return }
        guard let url = documentURL else { return }
        busy = true
        defer { busy = false }
        if isDirty {
            guard confirmDiscardForReload() else { return }
        }
        let previousContent = content
        if let identity = packageReloadIdentity() {
            await reloadPackage(identity)
        } else {
            await reloadLocalDocument(url, previousContent: previousContent)
        }
    }
}
