import Foundation
import LeonardoSync

/// Navigation can traverse selected ancestors; mutation cannot enlarge a grant.
enum DesktopPeerPathIntent { case document, directory, directoryMutation }

@MainActor
struct DesktopPeerPathPolicy {
    let root: URL
    let selection: @MainActor (UUID) async throws -> CorpusSelection

    func authorize(_ url: URL, intent: DesktopPeerPathIntent) async throws {
        let root = root.standardizedFileURL.resolvingSymlinksInPath()
        let lexical = url.standardizedFileURL
        let resolved = lexical.resolvingSymlinksInPath()
        let prefix = root.path + "/"
        guard lexical.path == root.path || lexical.path.hasPrefix(prefix) || resolved.path == root.path || resolved.path.hasPrefix(prefix) else { return }
        // Do not follow an untrusted alias out of (or into) the managed cache.
        guard lexical.path == resolved.path, resolved.path.hasPrefix(prefix) else { throw SyncError.invalidPath }
        let components = Array(resolved.pathComponents.dropFirst(root.pathComponents.count))
        guard let first = components.first, let id = UUID(uuidString: first) else { throw SyncError.invalidPath }
        var candidate = root
        for component in components {
            candidate.appendPathComponent(component)
            if let attributes = try? FileManager.default.attributesOfItem(atPath: candidate.path),
               attributes[.type] as? FileAttributeType == .typeSymbolicLink { throw SyncError.invalidPath }
        }
        let grant = try await selection(id)
        let path = components.dropFirst().joined(separator: "/")
        switch intent {
        case .document: try grant.validate(path)
        case .directory:
            if path.isEmpty { return }
            _ = try CorpusScope(folder: path)
            guard grant.folders.contains(path) || grant.contains(path + "/selection.md") ||
                    (grant.folders + grant.documents).contains(where: { $0.hasPrefix(path + "/") }) else { throw SyncError.outsideScope }
        case .directoryMutation:
            guard !path.isEmpty, grant.folders.contains(where: { $0.isEmpty || path == $0 || path.hasPrefix($0 + "/") }) else { throw SyncError.outsideScope }
            try grant.validate(path + "/selection.md")
        }
    }
}
