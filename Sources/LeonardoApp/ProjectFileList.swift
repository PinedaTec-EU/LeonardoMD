import SwiftUI

struct ProjectFileList: View {
    @Bindable var session: AppSession
    var isActiveTab = true
    @Binding var rootDropState: ProjectFolderDropState
    private var tree: ProjectFileTree { session.projectFileTree }
    @State private var rowStackHeight: CGFloat = 0
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
            let visibleRows = session.searchQuery.isEmpty ? tree.rows(roots: session.rootEntries) : []
            GeometryReader { viewport in
                ScrollView {
                    VStack(spacing: 0) {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            if session.searchQuery.isEmpty {
                                ForEach(visibleRows) { row in
                                    FileTreeRow(entry: row.entry, session: session, tree: tree, rows: visibleRows,
                                                isActiveTab: isActiveTab,
                                                depth: row.depth + 1, expanded: tree.expanded.contains(row.id)) {
                                        Task { await tree.toggle(row.entry, session: session) }
                                    }.id(row.id)
                                }
                            } else {
                                searchResults
                            }
                        }
                        .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { rowStackHeight = $0 }

                        if let root = session.projectURL, session.searchQuery.isEmpty {
                            Rectangle()
                                .fill(.clear)
                                .frame(height: max(0, viewport.size.height - rowStackHeight))
                                .contentShape(Rectangle())
                                .onDrop(of: ProjectFolderDropDelegate.acceptedTypes, delegate: ProjectFolderDropDelegate(
                                    folder: root, session: session, state: $rootDropState, acceptsExternalFiles: false
                                ))
                        }
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
                    .contextMenu {
                        Button(L10n.text("Open in new tab")) {
                            Task { await session.openProjectDocumentInTab?(match.url, match.line) }
                        }
                    }
                    .modifier(FileRowHighlight(accent: session.accentColor))
            }
            if session.searching { ProgressView().controlSize(.small) }
        }
    }
}

struct ProjectFileSelectionSummary: View {
    let tree: ProjectFileTree
    let accent: Color

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(accent)
                .accessibilityHidden(true)
            Text("\(tree.selection.count)")
                .font(.caption.weight(.semibold).monospacedDigit())
            Text(L10n.text(tree.selection.count == 1 ? "item selected" : "items selected"))
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 4)
            Button {
                tree.clearSelection()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help(L10n.text("Clear selection"))
            .accessibilityLabel(L10n.text("Clear selection"))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
        .padding(.horizontal, 6)
        .padding(.top, 4)
    }
}
