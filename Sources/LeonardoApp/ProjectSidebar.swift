import SwiftUI
import AppKit
import LeonardoCore

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
    var isActiveTab = true
    @State private var rootDropState = ProjectFolderDropState.idle

    var body: some View {
        VStack(spacing: 0) {
            sidebarContent
            let tree = session.projectFileTree
            let hasSelection = session.searchQuery.isEmpty && !tree.selection.isEmpty
            ProjectFileSelectionSummary(tree: tree, accent: session.accentColor)
                .opacity(hasSelection ? 1 : 0)
                .allowsHitTesting(hasSelection)
                .accessibilityHidden(!hasSelection)
        }
        .background(.regularMaterial)
    }

    private var sidebarContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                TextField(L10n.text("Search files and content"), text: $session.searchQuery)
                    .textFieldStyle(PremiumTextFieldStyle(compact: true))
                    .accessibilityIdentifier("project-search")
                    .onChange(of: session.searchQuery) { _, _ in session.scheduleSearch() }
                Menu {
                    Button { session.createItem(directory: false) } label: {
                        Label(L10n.text("Note"), systemImage: "doc.badge.plus")
                    }
                    Button { session.createItem(directory: true) } label: {
                        Label(L10n.text("New folder"), systemImage: "folder.badge.plus")
                    }
                    Button { session.chooseProject() } label: {
                        Label(L10n.text("Open another project"), systemImage: "folder")
                    }
                } label: {
                    Image(systemName: "plus")
                }
                .fixedSize()
                .help(L10n.text("Project actions"))
                .accessibilityLabel(L10n.text("Project actions"))
                FileListMenu(session: session)
            }
            if let root = session.projectURL {
                rootDropTarget(root)
            }
            ProjectFileList(session: session, isActiveTab: isActiveTab, rootDropState: $rootDropState)
                .id(session.projectURL)
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
        .onChange(of: session.showNonDocumentFiles) { _, _ in Task { await session.refreshTree() } }
        .onChange(of: session.foldersFirst) { _, _ in Task { await session.refreshTree() } }
        .onChange(of: session.fileSortDescending) { _, _ in Task { await session.refreshTree() } }
        .onChange(of: session.showHidden) { _, _ in Task { await session.refreshTree() } }
    }

    private func rootDropTarget(_ root: URL) -> some View {
        let presentation = DesktopProjectPresentation.resolve(root, session: session)
        return HStack {
            ProjectIdentityLabel(name: root.lastPathComponent,
                                 identity: presentation.identity, detail: presentation.detail)
                .font(.headline)
            Spacer(minLength: 0)
            if let label = rootDropState.label, let symbol = rootDropState.symbol {
                Label(L10n.text(label), systemImage: symbol)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(session.accentColor)
            }
        }
        .padding(6)
        .contentShape(Rectangle())
        .modifier(FileRowHighlight(accent: session.accentColor, dropTarget: rootDropState.isTarget))
        .onDrop(of: ProjectFolderDropDelegate.acceptedTypes, delegate: ProjectFolderDropDelegate(
            folder: root, session: session, state: $rootDropState, acceptsExternalFiles: false
        ))
        .accessibilityIdentifier("project-root-drop-target")
    }

}

struct SearchResult: Identifiable {
    let url: URL
    let line: Int
    let snippet: String
    var id: String { "\(url.path):\(line):\(snippet)" }
}
