import AppKit
import LeonardoCore

extension AppSession {
    @discardableResult
    func delete(_ url: URL) -> Task<Void, Never>? {
        guard let root = projectURL else { return nil }
        let identity = SessionFileOperationIdentity(sourceURL: url, session: self)
        return Task {
            guard identity.isCurrent(in: self) else { return }
            let project = ProjectDescriptor(name: root.lastPathComponent, rootURL: root)
            let mode: FileDeletionMode
            do {
                mode = try await files.trashAvailability(relative(url), in: project) == .unavailable
                    ? .permanentlyConfirmed : .trash
            } catch { report(error); return }
            guard identity.isCurrent(in: self), await confirmDeletion(url, mode: mode) else { return }
            guard identity.isCurrent(in: self) else { return }
            fileOperationCount += 1
            defer { fileOperationCount -= 1 }
            guard await prepareNavigation(), await prepareRelatedFileOperation?(url) ?? true,
                  identity.isCurrent(in: self) else { return }
            do {
                let intent: DesktopPeerPathIntent = (try url.resourceValues(forKeys: [.isDirectoryKey])).isDirectory == true ? .directoryMutation : .document
                try await authorizePath(url, intent)
                guard identity.isCurrent(in: self) else { return }
                do {
                    try await files.delete(relative(url), in: project, mode: mode)
                } catch FileDeletionError.trashUnavailable where mode == .trash {
                    guard await confirmDeletion(url, mode: .permanentlyConfirmed),
                          identity.isCurrent(in: self) else { return }
                    guard await prepareNavigation(), await prepareRelatedFileOperation?(url) ?? true,
                          identity.isCurrent(in: self) else { return }
                    // Another window or a synchronization lease may change while
                    // the warning is open. Recheck authorization before removal.
                    try await authorizePath(url, intent)
                    guard identity.isCurrent(in: self) else { return }
                    try await files.delete(relative(url), in: project, mode: .permanentlyConfirmed)
                }
                clearDeletedDocument(at: url)
                relatedPathDeleted?(url)
                await refreshTree()
            } catch { report(error) }
        }
    }

    func confirmDeletion(_ url: URL, mode: FileDeletionMode) async -> Bool {
        let alert = NSAlert()
        if mode == .permanentlyConfirmed {
            alert.alertStyle = .warning
            alert.messageText = L10n.format("Permanently delete %@?", url.lastPathComponent)
            alert.informativeText = L10n.text("Trash is unavailable in this location. The item and its contents will be permanently deleted. This cannot be undone.")
        } else {
            alert.messageText = L10n.format("Move %@ to Trash?", url.lastPathComponent)
            alert.informativeText = L10n.text("The item will be moved to Trash. You can recover it from Trash.")
        }
        alert.addButton(withTitle: L10n.text("Cancel"))
        alert.addButton(withTitle: L10n.text(mode == .trash ? "Move to Trash" : "Delete Permanently"))
        alert.buttons[1].hasDestructiveAction = true
        return await NativeDialog.present(alert, on: presentationWindow) == .alertSecondButtonReturn
    }
}
