import AppKit
import Observation

@MainActor
struct DocumentTab: Identifiable {
    let id = UUID()
    let session: AppSession
    var title: String { session.documentURL?.lastPathComponent ?? session.projectURL?.lastPathComponent ?? "Nueva pestaña" }
    var location: URL? { session.documentURL ?? session.projectURL }
}

/// Each tab owns the existing editor session, including async saves and project operations.
@MainActor @Observable
final class DocumentTabs {
    private(set) var tabs: [DocumentTab] = []
    private(set) var activeID: UUID?
    private(set) var closing = false
    var updateWindow: ((String, URL?, Bool) -> Void)?
    let dragOwnerID = UUID()
    private var stopped = false
    private let preferencesURL: URL

    init(preferencesURL: URL = AppSession.preferencesURL) {
        self.preferencesURL = preferencesURL
        addTab()
    }

    var activeSession: AppSession { tabs.first { $0.id == activeID }!.session }
    var hasPendingWork: Bool { tabs.contains { $0.session.isDirty || $0.session.saving || $0.session.settingsTask != nil || $0.session.gitBusy } }
    var acceptsExternalDrops: Bool { !closing && !stopped }

    @discardableResult
    func addTab() -> UUID? {
        guard !closing, !stopped else { return nil }
        NSApplication.shared.keyWindow?.makeFirstResponder(nil)
        let session = AppSession(preferencesURL: preferencesURL)
        let tab = DocumentTab(session: session)
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
        guard !closing, !stopped, abs(offset) == 1,
              let index = tabs.firstIndex(where: { $0.id == id }),
              tabs.indices.contains(index + offset) else { return nil }
        return tabs[index + offset].id
    }

    func acceptTabDrop(_ items: [DocumentTabDrag], onto targetID: UUID) -> Bool {
        guard items.count == 1, let item = items.first, item.ownerID == dragOwnerID else { return false }
        return move(item.tabID, to: targetID)
    }

    func activateDocument(_ url: URL, line: Int? = nil) -> Bool {
        guard !closing, let tab = tabs.first(where: {
            $0.session.documentURL?.standardizedFileURL.resolvingSymlinksInPath() == url.standardizedFileURL.resolvingSymlinksInPath()
        }) else { return false }
        select(tab.id)
        if let line { tab.session.mode = .edit; tab.session.requestedLine = line }
        return true
    }

    static func acceptsDrop(_ urls: [URL]) -> Bool {
        !urls.isEmpty && urls.allSatisfy { url in
            guard url.isFileURL, ["md", "markdown"].contains(url.pathExtension.lowercased()) else { return false }
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
            if activateDocument(url) { continue }
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
        guard await session.prepareNavigation() else {
            activeID = id
            updateTitle()
            return
        }
        session.stop()
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
        defer { closing = false }
        for tab in tabs {
            guard await tab.session.prepareNavigation() else {
                activeID = tab.id
                updateTitle()
                return false
            }
        }
        return !hasPendingWork
    }

    func reveal(_ id: UUID) {
        guard let url = tabs.first(where: { $0.id == id })?.location else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func stop() {
        stopped = true
        tabs.forEach { $0.session.stop() }
    }
    func updateTitle() {
        let session = activeSession
        updateWindow?(session.documentURL?.lastPathComponent ?? session.projectURL?.lastPathComponent ?? "LeonardoMD", session.documentURL, tabs.contains { $0.session.isDirty })
    }
}
