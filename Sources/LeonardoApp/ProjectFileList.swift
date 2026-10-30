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
        if expanded.contains(entry.url) { expanded.remove(entry.url) }
        else {
            children[entry.url] = await session.children(of: entry.url)
            guard !Task.isCancelled else { return }
            expanded.insert(entry.url)
        }
    }

    func refreshAndReveal(_ target: URL?, session: AppSession) async -> URL? {
        for folder in expanded {
            let entries = await session.children(of: folder)
            guard !Task.isCancelled else { return nil }
            children[folder] = entries
        }
        guard let target else { return nil }
        var entries = session.rootEntries
        while let ancestor = entries.first(where: {
            $0.isDirectory && target.path.hasPrefix($0.url.standardizedFileURL.path + "/")
        }) {
            let loaded = await session.children(of: ancestor.url)
            guard !Task.isCancelled else { return nil }
            children[ancestor.url] = loaded
            expanded.insert(ancestor.url)
            entries = loaded
        }
        return entries.first(where: { !$0.isDirectory && $0.url.standardizedFileURL == target })?.url
    }
}

struct ProjectFileList: View {
    @Bindable var session: AppSession
    @State private var tree = ProjectFileTree()
    @State private var revealed: URL?
    @State private var revealRevision = 0

    private struct Request: Equatable {
        let target: URL?
        let roots: [NavigationEntry]
        let treeRevision: Int
        let searching: Bool
    }
    private var request: Request {
        Request(target: session.globalPreferences.followActiveFile
                    ? (session.documentSourceURL ?? session.documentURL)?.standardizedFileURL : nil,
                roots: session.rootEntries, treeRevision: session.treeRevision,
                searching: !session.searchQuery.isEmpty)
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
                guard !current.searching else { return }
                revealed = await tree.refreshAndReveal(current.target, session: session)
                guard !Task.isCancelled else { return }
                revealRevision += 1
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
