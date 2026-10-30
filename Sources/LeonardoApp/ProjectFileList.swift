import SwiftUI

/// A flat list keeps every expanded row addressable by ScrollViewReader,
/// including descendants whose ancestors started outside the viewport.
@MainActor @Observable
final class ProjectFileTree {
    struct Row: Identifiable {
        let entry: NavigationEntry
        let depth: Int
        var id: URL { entry.id }
    }
    private(set) var expanded: Set<URL> = []
    private var children: [URL: [NavigationEntry]] = [:]
    private var projectRoot: URL?

    private func synchronizeProject(_ session: AppSession) -> URL? {
        let root = session.projectURL?.standardizedFileURL
        if root != projectRoot {
            expanded.removeAll()
            children.removeAll()
            projectRoot = root
        }
        return root
    }

    private func belongsToProject(_ url: URL, root: URL) -> Bool {
        url.standardizedFileURL.path.hasPrefix(root.path == "/" ? "/" : root.path + "/")
    }

    private func isCurrent(_ root: URL, session: AppSession) -> Bool {
        !Task.isCancelled && projectRoot == root && session.projectURL?.standardizedFileURL == root
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
        guard let root = synchronizeProject(session), entry.isDirectory,
              belongsToProject(entry.url, root: root) else { return }
        if expanded.contains(entry.url) { expanded.remove(entry.url) }
        else {
            expanded.insert(entry.url)
            let loaded = await session.children(of: entry.url)
            guard isCurrent(root, session: session), expanded.contains(entry.url) else { return }
            children[entry.url] = loaded
        }
    }

    private func refreshExpandedFolders(session: AppSession, root: URL) async -> Bool {
        let previousExpansion = expanded
        var pending = session.rootEntries
        var retained: Set<URL> = []
        var index = 0
        while index < pending.count {
            let entry = pending[index]
            index += 1
            guard entry.isDirectory, expanded.contains(entry.url) else { continue }
            guard isCurrent(root, session: session), belongsToProject(entry.url, root: root) else { return false }
            let loaded = await session.children(of: entry.url)
            guard isCurrent(root, session: session) else { return false }
            children[entry.url] = loaded
            retained.insert(entry.url)
            pending.append(contentsOf: loaded)
        }
        // Prune only state that belonged to this refresh. A user may have
        // expanded another folder while an earlier child load was suspended.
        expanded.subtract(previousExpansion.subtracting(retained))
        children = children.filter { expanded.contains($0.key) }
        return true
    }

    func refreshAndReveal(_ target: URL?, session: AppSession) async -> URL? {
        guard let root = synchronizeProject(session) else { return nil }
        guard await refreshExpandedFolders(session: session, root: root) else { return nil }
        guard let target, belongsToProject(target, root: root) else { return nil }
        var entries = session.rootEntries
        while let ancestor = entries.first(where: {
            $0.isDirectory && target.path.hasPrefix($0.url.standardizedFileURL.path + "/")
        }) {
            guard isCurrent(root, session: session), belongsToProject(ancestor.url, root: root) else { return nil }
            let loaded = await session.children(of: ancestor.url)
            guard isCurrent(root, session: session) else { return nil }
            children[ancestor.url] = loaded
            expanded.insert(ancestor.url)
            entries = loaded
        }
        return entries.first(where: { !$0.isDirectory && $0.url.standardizedFileURL == target })?.url
    }
}

struct ProjectFileList: View {
    @Bindable var session: AppSession
    var isActiveTab = true
    @State private var tree = ProjectFileTree()
    @State private var revealed: URL?
    @State private var revealRevision = 0
    @State private var lastFollow: FollowIdentity?

    private struct FollowIdentity: Equatable {
        let target: URL?
        let active: Bool
        let searching: Bool
    }

    private struct Request: Equatable {
        let target: URL?
        let roots: [NavigationEntry]
        let treeRevision: Int
        let searching: Bool
        let active: Bool
    }
    private var request: Request {
        Request(target: session.globalPreferences.followActiveFile
                    ? (session.documentSourceURL ?? session.documentURL)?.standardizedFileURL : nil,
                roots: session.rootEntries, treeRevision: session.treeRevision,
                searching: !session.searchQuery.isEmpty, active: isActiveTab)
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    if session.searchQuery.isEmpty {
                        ForEach(tree.rows(roots: session.rootEntries)) { row in
                            FileTreeRow(entry: row.entry, session: session, depth: row.depth,
                                        expanded: tree.expanded.contains(row.id)) {
                                Task { await tree.toggle(row.entry, session: session) }
                            }.id(row.id)
                        }
                    } else {
                        searchResults
                    }
                }
            }
            .task(id: request) {
                let current = request
                let follow = FollowIdentity(target: current.target, active: current.active, searching: current.searching)
                let needsReveal = follow != lastFollow || revealed == nil
                guard current.active, !current.searching else { lastFollow = follow; return }
                let target = needsReveal ? current.target : nil
                let result = await tree.refreshAndReveal(target, session: session)
                guard !Task.isCancelled else { return }
                lastFollow = follow
                if needsReveal {
                    revealed = result
                    revealRevision += 1
                }
            }
            .onChange(of: revealRevision) { _, _ in
                if let revealed { proxy.scrollTo(revealed, anchor: .center) }
            }
        }
    }

    private var searchResults: some View {
        Group {
            ForEach(session.searchResults) { match in
                Button {
                    Task { await session.openDocument(match.url, line: match.line) }
                } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Label(match.url.lastPathComponent, systemImage: "doc.text")
                        Text(session.relative(match.url) + " · L\(match.line)")
                            .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                        Text(match.snippet).font(.caption).lineLimit(2).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(7)
                }.buttonStyle(.plain)
                    .modifier(FileRowHighlight(accent: session.accentColor))
            }
            if session.searching { ProgressView().controlSize(.small) }
        }
    }
}
