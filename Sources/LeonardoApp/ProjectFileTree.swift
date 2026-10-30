import SwiftUI

/// Owns project-scoped tree state. Every asynchronous write belongs to both
/// a project generation and the latest load of that exact folder.
@MainActor @Observable
final class ProjectFileTree {
    struct Row: Identifiable {
        let entry: NavigationEntry
        let depth: Int
        var id: URL { entry.id }
    }
    fileprivate struct Context: Equatable {
        let root: URL
        let projectGeneration: Int
        let interactionRevision: Int
    }
    struct Reveal: Equatable {
        let url: URL
        fileprivate let context: Context
    }
    enum RevealOutcome: Equatable {
        case revealed(Reveal)
        case unavailable
        case superseded

        var url: URL? {
            if case .revealed(let result) = self { return result.url }
            return nil
        }
    }
    private enum LoadPurpose: Equatable { case manualExpansion, refresh, reveal }

    private(set) var expanded: Set<URL> = []
    private var children: [URL: [NavigationEntry]] = [:]
    private var projectRoot: URL?
    private var projectGeneration = 0
    private var interactionRevision = 0
    private var nextLoadGeneration = 0
    private var loadGenerations: [URL: Int] = [:]

    private func context(for session: AppSession) -> Context? {
        let root = session.projectURL?.standardizedFileURL
        if root != projectRoot {
            projectRoot = root
            projectGeneration += 1
            expanded.removeAll()
            children.removeAll()
            loadGenerations.removeAll()
        }
        guard let root else { return nil }
        return Context(root: root, projectGeneration: projectGeneration, interactionRevision: interactionRevision)
    }

    private func belongsToProject(_ url: URL, root: URL) -> Bool {
        url.standardizedFileURL.path.hasPrefix(root.path == "/" ? "/" : root.path + "/")
    }

    private func matches(_ context: Context, session: AppSession, purpose: LoadPurpose) -> Bool {
        projectRoot == context.root && projectGeneration == context.projectGeneration &&
        session.projectURL?.standardizedFileURL == context.root &&
        (purpose == .manualExpansion || interactionRevision == context.interactionRevision)
    }

    func canReveal(_ reveal: Reveal, session: AppSession) -> Bool {
        matches(reveal.context, session: session, purpose: .reveal)
    }

    func rows(roots: [NavigationEntry]) -> [Row] {
        func flatten(_ entries: [NavigationEntry], depth: Int) -> [Row] {
            entries.flatMap { entry in
                [Row(entry: entry, depth: depth)] + (expanded.contains(entry.url)
                    ? flatten(children[entry.url] ?? [], depth: depth + 1) : [])
            }
        }
        return flatten(roots, depth: 0)
    }

    func toggle(_ entry: NavigationEntry, session: AppSession) async {
        guard let context = context(for: session), entry.isDirectory,
              belongsToProject(entry.url, root: context.root) else { return }
        interactionRevision += 1
        if expanded.contains(entry.url) { collapse(entry.url) }
        else {
            expanded.insert(entry.url)
            _ = await loadFolder(entry.url, context: context, purpose: .manualExpansion, session: session)
        }
    }

    private func collapse(_ folder: URL) {
        let keep: (URL) -> Bool = { url in
            url.standardizedFileURL != folder.standardizedFileURL && !self.belongsToProject(url, root: folder)
        }
        expanded = Set(expanded.filter(keep))
        children = children.filter { keep($0.key) }
        loadGenerations = loadGenerations.filter { keep($0.key) }
    }

    private func loadFolder(_ folder: URL, context: Context, purpose: LoadPurpose,
                            session: AppSession) async -> [NavigationEntry]? {
        guard !Task.isCancelled, matches(context, session: session, purpose: purpose),
              belongsToProject(folder, root: context.root),
              purpose == .reveal || expanded.contains(folder) else { return nil }
        nextLoadGeneration += 1
        let generation = nextLoadGeneration
        loadGenerations[folder] = generation
        let loaded = await session.children(of: folder)
        guard !Task.isCancelled, matches(context, session: session, purpose: purpose),
              loadGenerations[folder] == generation,
              purpose == .reveal || expanded.contains(folder) else { return nil }
        children[folder] = loaded
        if purpose == .reveal { expanded.insert(folder) }
        return loaded
    }

    private func refreshExpandedFolders(context: Context, session: AppSession) async -> Bool {
        var pending = session.rootEntries
        var retained: Set<URL> = []
        var index = 0
        while index < pending.count {
            let entry = pending[index]
            index += 1
            guard entry.isDirectory, expanded.contains(entry.url) else { continue }
            guard let loaded = await loadFolder(entry.url, context: context, purpose: .refresh, session: session)
            else { return false }
            retained.insert(entry.url)
            pending.append(contentsOf: loaded)
        }
        guard !Task.isCancelled, matches(context, session: session, purpose: .refresh) else { return false }
        expanded.formIntersection(retained)
        children = children.filter { expanded.contains($0.key) }
        loadGenerations = loadGenerations.filter { expanded.contains($0.key) }
        return true
    }

    func refreshAndReveal(_ target: URL?, session: AppSession) async -> RevealOutcome {
        guard let context = context(for: session) else { return .unavailable }
        guard await refreshExpandedFolders(context: context, session: session) else { return .superseded }
        guard let target, belongsToProject(target, root: context.root) else { return .unavailable }
        var entries = session.rootEntries
        while let ancestor = entries.first(where: {
            $0.isDirectory && target.path.hasPrefix($0.url.standardizedFileURL.path + "/")
        }) {
            guard belongsToProject(ancestor.url, root: context.root) else { return .unavailable }
            guard let loaded = await loadFolder(ancestor.url, context: context, purpose: .reveal, session: session)
            else { return .superseded }
            entries = loaded
        }
        guard !Task.isCancelled, matches(context, session: session, purpose: .reveal) else { return .superseded }
        guard let file = entries.first(where: { !$0.isDirectory && $0.url.standardizedFileURL == target })
        else { return .unavailable }
        return .revealed(Reveal(url: file.url, context: context))
    }
}
