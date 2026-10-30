import SwiftUI

struct ProjectFileList: View {
    @Bindable var session: AppSession
    var isActiveTab = true
    @State private var tree = ProjectFileTree()
    @State private var revealed: ProjectFileTree.Reveal?
    @State private var retryReveal = true
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
                let needsReveal = follow != lastFollow || retryReveal
                guard current.active, !current.searching else { lastFollow = follow; return }
                let target = needsReveal ? current.target : nil
                let result = await tree.refreshAndReveal(target, session: session)
                guard !Task.isCancelled else { return }
                lastFollow = follow
                guard needsReveal else { return }
                switch result {
                case .revealed(let file):
                    revealed = file
                    retryReveal = false
                    revealRevision += 1
                case .unavailable:
                    revealed = nil
                    retryReveal = current.target != nil
                case .superseded:
                    revealed = nil
                    retryReveal = false
                }
            }
            .onChange(of: revealRevision) { _, _ in
                if let revealed, isActiveTab, session.searchQuery.isEmpty,
                   session.globalPreferences.followActiveFile,
                   tree.canReveal(revealed, session: session),
                   revealed.url.standardizedFileURL == (session.documentSourceURL ?? session.documentURL)?.standardizedFileURL {
                    proxy.scrollTo(revealed.url, anchor: .center)
                }
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
