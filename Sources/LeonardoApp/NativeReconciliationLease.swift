import Foundation
import Observation
import LeonardoSync
import LeonardoDesktopSync

@MainActor @Observable
final class NativeReconciliationLease {
    static let shared = NativeReconciliationLease()
    private(set) var root: URL?
    var sessions: @MainActor () -> [AppSession] = { [] }

    func holds(_ url: URL?) -> Bool {
        guard let root, let url else { return false }
        let target = url.standardizedFileURL.resolvingSymlinksInPath()
        return target == root || target.path.hasPrefix(root.path + "/")
    }
    func check(_ url: URL, intent: DesktopPeerPathIntent = .document) throws {
        if holds(url) { throw DesktopRuntimeError.busy }
        if intent == .directoryMutation, let root {
            let target = url.standardizedFileURL.resolvingSymlinksInPath()
            if root.path.hasPrefix(target.path + "/") { throw DesktopRuntimeError.busy }
        }
    }
    /// Revocation must close editors and purge their cache after an application transaction
    /// has released ownership of the same working directory.
    func waitUntilReleased(_ folders: [URL]) async {
        while folders.contains(where: { holds($0) }) {
            try? await Task.sleep(for: .milliseconds(20))
        }
    }
    func run(projectRoot: URL, selection: CorpusSelection, operation: @MainActor () async throws -> DesktopPeerAcceptanceResult) async throws -> DesktopPeerAcceptanceResult {
        guard root == nil else { throw DesktopRuntimeError.busy }
        root = projectRoot.standardizedFileURL.resolvingSymlinksInPath()
        defer {
            root = nil
            for session in sessions() where session.isDirty { session.contentChanged() }
        }
        let affected = sessions().filter { holds($0.projectURL) || holds($0.documentURL) }
        for session in affected { session.saveTask?.cancel() }
        for session in affected { await session.saveTask?.value }
        while sessions().contains(where: {
            $0.saving || $0.busy || $0.gitBusy || $0.fileOperationCount > 0 || $0.settingsTask != nil
        }) {
            try Task.checkCancellation()
            try await Task.sleep(for: .milliseconds(20))
        }
        let frozen = sessions().compactMap { session -> (AppSession, URL, String)? in
            guard let url = session.documentURL, holds(url), let root else { return nil }
            let path = url.standardizedFileURL.resolvingSymlinksInPath().pathComponents.dropFirst(root.pathComponents.count).joined(separator: "/")
            return selection.contains(path) ? (session, url, session.content) : nil
        }
        let result = try await operation()
        // A recovered historical result performed no new source writes. Later buffers stay intact.
        if result.appliedNow {
            for (session, url, content) in frozen {
                guard session.documentURL == url, session.content == content, !session.stopped,
                      let root else { continue }
                let path = url.standardizedFileURL.resolvingSymlinksInPath().pathComponents.dropFirst(root.pathComponents.count).joined(separator: "/")
                guard !result.retainedBufferPaths.contains(path),
                      result.appliedSnapshot.files.contains(where: { $0.path == path }) || !FileManager.default.fileExists(atPath: url.path) else { continue }
                do {
                    if FileManager.default.fileExists(atPath: url.path) {
                        let loaded = try await session.documents.read(url)
                        guard session.documentURL == url, session.content == content else { continue }
                        session.syncUpdatingBuffer = true
                        session.snapshot = loaded; session.content = loaded.content
                        session.syncUpdatingBuffer = false
                        session.externalConflict = false; session.saveStatus = "Saved · local file"
                    } else {
                        session.syncUpdatingBuffer = true
                        session.snapshot = nil; session.documentURL = nil; session.content = ""
                        session.syncUpdatingBuffer = false
                        session.externalConflict = false; session.saveStatus = "Local file"
                        session.requestedLine = nil; session.editorScroll = 0
                        session.renderer.update(content: "", baseURL: nil)
                    }
                    session.updateTitle()
                } catch {
                    // The accepted filesystem result is already durable; preserve unreadable drafts.
                    session.externalConflict = true
                    session.report(error)
                }
            }
        }
        return result
    }
}
