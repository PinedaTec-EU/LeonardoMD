import SwiftUI
import AppKit

struct FileTreeRow: View {
    let entry: NavigationEntry
    @Bindable var session: AppSession
    let tree: ProjectFileTree
    let depth: Int
    let expanded: Bool
    let toggle: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    @State private var dropState = ProjectFolderDropState.idle
    @State private var clickModifiers: NSEvent.ModifierFlags = []

    var isActiveDocument: Bool {
        !entry.isDirectory && session.displayDocumentURL?.resolvingSymlinksInPath().path ==
            entry.url.resolvingSymlinksInPath().path
    }
    private var isMultiSelected: Bool { tree.selection.contains(entry.url) }
    private var isColoredLeonardo: Bool {
        session.colorLeonardoFiles && !entry.isDirectory &&
        AppDocumentKind.classify(entry.url).isLeonardo
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Button {
                if entry.isDirectory {
                    toggle()
                } else { Task { await session.openDocument(entry.url) } }
            } label: {
                HStack(spacing: 7) {
                    if entry.isDirectory {
                        Image(systemName: expanded ? "chevron.down" : "chevron.right").font(.caption2).frame(width: 10)
                    } else { Color.clear.frame(width: 10, height: 1) }
                    Image(systemName: entry.symbol).foregroundStyle(isActiveDocument ? Color(nsColor: .alternateSelectedControlTextColor) : isColoredLeonardo ? LeonardoFileStyle.foreground(for: colorScheme) : .secondary)
                    Text(entry.name).lineLimit(1)
                        .foregroundStyle(isActiveDocument ? Color(nsColor: .alternateSelectedControlTextColor) : isColoredLeonardo ? LeonardoFileStyle.foreground(for: colorScheme) : .primary)
                    Spacer(minLength: 0)
                    if let label = dropState.label, let symbol = dropState.symbol {
                        Label(L10n.text(label), systemImage: symbol)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(session.accentColor)
                            .fixedSize()
                    }
                }.padding(.vertical, 6).padding(.horizontal, 6)
                    .modifier(FileRowHighlight(accent: session.accentColor, selected: isActiveDocument,
                                               multiSelected: isMultiSelected,
                                               dropTarget: dropState.isTarget))
                    .background(isActiveDocument ? Color(nsColor: .selectedContentBackgroundColor) : .clear,
                                in: RoundedRectangle(cornerRadius: 6))
            }
                .highPriorityGesture(
                    TapGesture(count: 2).exclusively(before: TapGesture())
                        .onEnded { value in
                            if selectUsingCurrentModifiers(clickModifiers) { return }
                            switch value {
                            case .first:
                                if !entry.isDirectory {
                                    Task {
                                        if AppSession.supportedDocumentExtensions.contains(entry.url.pathExtension.lowercased()) {
                                            await session.openProjectDocumentInTab?(entry.url, nil)
                                        } else { await session.openDocument(entry.url) }
                                    }
                                } else { toggle() }
                            case .second:
                                if entry.isDirectory { toggle() }
                                else { Task { await session.openDocument(entry.url) } }
                            }
                        }
                )
                .contextMenu {
                    if !entry.isDirectory && AppSession.supportedDocumentExtensions.contains(entry.url.pathExtension.lowercased()) {
                        Button(L10n.text("Open in new tab")) {
                            Task { await session.openProjectDocumentInTab?(entry.url, nil) }
                        }
                        Divider()
                    }
                    Button(L10n.text("Show in Finder")) { NSWorkspace.shared.activateFileViewerSelecting([entry.url]) }
                    Button(L10n.text("Rename…")) { session.rename(entry.url) }
                    Button(L10n.text("Move…")) { session.move(entry.url) }
                    if entry.isDirectory {
                        Button(L10n.text("New note…")) { session.createItem(directory: false, parent: entry.url) }
                        Button(L10n.text("New folder…")) { session.createItem(directory: true, parent: entry.url) }
                    }
                    Divider()
                    Button(L10n.text("Move to Trash…"), role: .destructive) { session.delete(entry.url) }
                }
                // Keep the context menu in the plain-style scope so it cannot
                // inherit the sidebar's stateful PremiumButtonStyle.
                .buttonStyle(.plain)
        }
        .padding(.leading, CGFloat(depth) * 16)
        .overlay {
            ProjectTreeDragSource(url: entry.url, selectedURLs: {
                tree.dragSelection(startingAt: entry.url, rows: tree.rows(roots: session.rootEntries))
            }, onMouseDown: { clickModifiers = $0 })
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .allowsHitTesting(false)
        }
        .onDrop(of: [DocumentDropProviders.projectTreeItemType, .fileURL], delegate: ProjectFolderDropDelegate(
            folder: entry.url,
            session: session,
            state: $dropState
        ))
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityIdentifier("project-file-" + entry.url.path)
        .accessibilityAddTraits(isActiveDocument || isMultiSelected ? [.isSelected] : [])
    }

    private func selectUsingCurrentModifiers(_ modifiers: NSEvent.ModifierFlags) -> Bool {
        let rows = tree.rows(roots: session.rootEntries)
        if modifiers.contains(.shift) {
            tree.select(entry.url, among: rows, gesture: .extend(additive: modifiers.contains(.command)))
            return true
        }
        if modifiers.contains(.command) {
            tree.select(entry.url, among: rows, gesture: .toggle)
            return true
        }
        tree.select(entry.url, among: rows, gesture: .replace)
        return false
    }
}
