import AppKit
import Observation

@MainActor
struct DocumentTab: Identifiable {
    let id = UUID()
    let session: AppSession
    var title: String { session.displayDocumentURL?.lastPathComponent ?? session.projectURL?.lastPathComponent ?? L10n.text("New tab") }
    var location: URL? { session.displayDocumentURL ?? session.projectURL }
}

/// Each tab owns the existing editor session, including async saves and project operations.
@MainActor @Observable
final class DocumentTabs {
    private(set) var tabs: [DocumentTab] = []
    private(set) var activeID: UUID?
    private(set) var closing = false
    var updateWindow: ((String, URL?, Bool) -> Void)?
    private var stopped = false
    private var preparedForClose = false
    private let preferencesURL: URL

    init(preferencesURL: URL = AppSession.preferencesURL) {
        self.preferencesURL = preferencesURL
        addTab()
    }

    var activeSession: AppSession { tabs.first { $0.id == activeID }!.session }
    var hasPendingWork: Bool { tabs.contains { $0.session.isDirty || $0.session.busy || $0.session.fileOperationCount > 0 || $0.session.saving || $0.session.saveTask != nil || $0.session.settingsTask != nil || $0.session.gitBusy } }
    var acceptsExternalDrops: Bool { !closing && !stopped }

    @discardableResult
    func addTab() -> UUID? {
        guard !closing, !stopped else { return nil }
        NSApplication.shared.keyWindow?.makeFirstResponder(nil)
        let session = AppSession(preferencesURL: preferencesURL)
        let tab = DocumentTab(session: session)
        configureLeonardoTransport(for: session)
        session.activateExistingDocument = { [weak self] url, line in
            self?.activateDocument(url, line: line) ?? false
        }
        session.prepareRelatedFileOperation = { [weak self, weak session] source in
            guard let self else { return true }
            return await self.prepareFileOperation(source, excluding: session)
        }
        session.relatedPathMoved = { [weak self, weak session] source, destination in
            await self?.pathMoved(source, to: destination, excluding: session)
        }
        session.relatedPathDeleted = { [weak self, weak session] source in
            self?.pathDeleted(source, excluding: session)
        }
        session.openDroppedDocuments = { [weak self] urls in await self?.openDroppedDocuments(urls) }
        session.updateWindow = { [weak self] _, _, _ in self?.updateTitle() }
        tabs.append(tab)
        activeID = tab.id
        updateTitle()
        return tab.id
    }

    func select(_ id: UUID) {
        guard !closing, !stopped, tabs.contains(where: { $0.id == id }) else { return }
        NSApplication.shared.keyWindow?.makeFirstResponder(nil)
        activeID = id
        updateTitle()
    }

    /// Move the existing session to the target's original position without selecting it.
    @discardableResult
    func move(_ id: UUID, to targetID: UUID) -> Bool {
        guard !closing, !stopped, id != targetID,
              let source = tabs.firstIndex(where: { $0.id == id }),
              let destination = tabs.firstIndex(where: { $0.id == targetID }) else { return false }
        let tab = tabs.remove(at: source)
        tabs.insert(tab, at: destination)
        return true
    }

    func neighbor(of id: UUID, offset: Int) -> UUID? {
        guard !closing, !stopped, (offset == -1 || offset == 1),
              let index = tabs.firstIndex(where: { $0.id == id }),
              tabs.indices.contains(index + offset) else { return nil }
        return tabs[index + offset].id
    }

    func activateDocument(_ url: URL, line: Int? = nil) -> Bool {
        guard !closing, let tab = tabs.first(where: {
            $0.session.displayDocumentURL?.standardizedFileURL.resolvingSymlinksInPath() == url.standardizedFileURL.resolvingSymlinksInPath()
        }) else { return false }
        select(tab.id)
        if let line {
            Task { await tab.session.setDocumentMode(.edit); tab.session.requestedLine = line }
        }
        return true
    }

    static func acceptsDrop(_ urls: [URL]) -> Bool {
        !urls.isEmpty && urls.allSatisfy { url in
            guard url.isFileURL, AppDocumentKind.isSupportedDropExtension(url.pathExtension) else { return false }
            var directory: ObjCBool = false
            return FileManager.default.fileExists(atPath: url.path, isDirectory: &directory) && !directory.boolValue
        }
    }

    func openDroppedDocuments(_ urls: [URL]) async {
        guard !closing, !stopped, Self.acceptsDrop(urls) else { return }
        await openExternalDocuments(urls)
    }

    func openExternalDocuments(_ urls: [URL]) async {
        guard !closing, !stopped else { return }
        for url in urls where url.isFileURL {
            if activateDocument(url) {
                NSDocumentController.shared.noteNewRecentDocumentURL(url)
                continue
            }
            guard let id = addTab(), let tab = tabs.first(where: { $0.id == id }) else { return }
            await tab.session.open(url)
        }
    }

    func close(_ id: UUID) async {
        guard !closing, let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        NSApplication.shared.keyWindow?.makeFirstResponder(nil)
        closing = true
        defer { closing = false }
        let session = tabs[index].session
        guard await session.flushPreviewEdits() else { return }
        session.isClosing = true
        defer { if !session.stopped { session.isClosing = false } }
        guard await session.waitForCloseOperations(), await session.prepareNavigation() else {
            activeID = id
            updateTitle()
            return
        }
        session.stop()
        await session.waitForPackageWorkspaceDisposal()
        tabs.remove(at: index)
        if tabs.isEmpty {
            closing = false
            addTab()
        } else if activeID == id {
            activeID = tabs[min(index, tabs.count - 1)].id
        }
        updateTitle()
    }

    func prepareClose() async -> Bool {
        guard !closing else { return false }
        NSApplication.shared.keyWindow?.makeFirstResponder(nil)
        closing = true
        var approved = false
        defer { if !approved { releaseClosePreparation() } }
        for tab in tabs {
            guard await tab.session.flushPreviewEdits() else { return false }
            tab.session.isClosing = true
            guard await tab.session.waitForCloseOperations(), await tab.session.prepareNavigation() else {
                activeID = tab.id
                updateTitle()
                return false
            }
            tab.session.isClosing = true
        }
        guard !hasPendingWork else { return false }
        approved = true
        preparedForClose = true
        return true
    }

    /// Finalize only after every window has accepted close preparation.
    func finishPreparedClose() async {
        guard preparedForClose, !stopped else { return }
        stop()
        for tab in tabs { await tab.session.waitForPackageWorkspaceDisposal() }
    }

    func cancelPreparedClose() {
        guard preparedForClose, !stopped else { return }
        releaseClosePreparation()
    }

    private func releaseClosePreparation() {
        tabs.forEach { $0.session.isClosing = false }
        preparedForClose = false
        closing = false
    }

    func reveal(_ id: UUID) {
        guard let url = tabs.first(where: { $0.id == id })?.location else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    /// Revocation discards access to these copies; it never saves their drafts.
    /// Wait for existing I/O before the library removes the working directories.
    func revokeWorkspaces(_ roots: [URL]) async {
        let paths = roots.map { $0.standardizedFileURL.resolvingSymlinksInPath().path }
        let affected = tabs.filter { tab in
            tab.session.workspaceIdentityURLs.contains { url in
                let path = url.standardizedFileURL.resolvingSymlinksInPath().path
                return paths.contains { path == $0 || path.hasPrefix($0 + "/") }
            }
        }
        guard !affected.isEmpty else { return }
        for tab in affected {
            tab.session.stop()
            tab.session.clearRevokedContent()
        }
        // Active close iterations own indices; completed preparation no longer does.
        while closing && !preparedForClose { try? await Task.sleep(for: .milliseconds(20)) }
        let ids = Set(affected.map(\.id))
        tabs.removeAll { ids.contains($0.id) }
        if tabs.isEmpty {
            // Keep the active-session invariant even while a window is terminating.
            if addTab() == nil {
                tabs = [DocumentTab(session: AppSession(preferencesURL: preferencesURL))]
                activeID = tabs[0].id
            }
        } else if activeID.map(ids.contains) == true { activeID = tabs[0].id }
        updateTitle()
        for tab in affected { await tab.session.finishRevocation() }
    }

    func stop() {
        stopped = true
        tabs.forEach { $0.session.stop() }
    }
    func updateTitle() {
        let session = activeSession
        updateWindow?(session.displayDocumentURL?.lastPathComponent ?? session.projectURL?.lastPathComponent ?? "LeonardoMD", session.displayDocumentURL, tabs.contains { $0.session.isDirty })
    }
}
