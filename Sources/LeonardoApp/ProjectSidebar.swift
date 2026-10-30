import SwiftUI
import AppKit

struct NavigationEntry: Identifiable, Hashable {
    let url: URL
    let isDirectory: Bool
    var id: URL { url }
    var name: String { url.lastPathComponent }
    var symbol: String {
        if isDirectory { return "folder" }
        if AppDocumentKind.isSupportedExtension(url.pathExtension) {
            return AppDocumentKind.classify(url).iconName
        }
        if ["png", "jpg", "jpeg", "svg", "gif", "webp"].contains(url.pathExtension.lowercased()) { return "photo" }
        return "doc"
    }
}

struct ProjectSidebar: View {
    @Bindable var session: AppSession
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "folder.fill")
                Text(session.projectURL?.lastPathComponent ?? L10n.text("Project")).font(.headline)
                Spacer()
                Button { session.chooseProject() } label: { Image(systemName: "folder.badge.plus") }
                    .help(L10n.text("Open another project"))
            }
            TextField(L10n.text("Search files and content"), text: $session.searchQuery)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("project-search")
                .onChange(of: session.searchQuery) { _, _ in session.scheduleSearch() }
            HStack {
                Button { session.createItem(directory: false) } label: { Label(L10n.text("Note"), systemImage: "doc.badge.plus") }
                Button { session.createItem(directory: true) } label: { Image(systemName: "folder.badge.plus") }
                Spacer()
                FileListMenu(session: session)
            }
            ProjectFileList(session: session)
            Spacer(minLength: 0)
            if session.gitEnabled {
                Button { session.showGit = true } label: {
                    Label(session.gitSummary, systemImage: "arrow.triangle.branch")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }.buttonStyle(PremiumButtonStyle(compact: true)).accessibilityIdentifier("git-panel")
            }
        }
        .buttonStyle(PremiumButtonStyle(compact: true))
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial)
        .onChange(of: session.showAllFiles) { _, _ in Task { await session.refreshTree() } }
        .onChange(of: session.foldersFirst) { _, _ in Task { await session.refreshTree() } }
        .onChange(of: session.fileSortDescending) { _, _ in Task { await session.refreshTree() } }
        .onChange(of: session.showHidden) { _, _ in Task { await session.refreshTree() } }
    }
}

struct SearchResult: Identifiable {
    let url: URL
    let line: Int
    let snippet: String
    var id: String { "\(url.path):\(line):\(snippet)" }
}
