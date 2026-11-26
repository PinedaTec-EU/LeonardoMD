import SwiftUI
import AppKit

struct FileTreeRow: View {
    let entry: NavigationEntry
    @Bindable var session: AppSession
    let tree: ProjectFileTree
    var rows: [ProjectFileTree.Row]? = nil
    var isActiveTab = true
    let depth: Int
    let expanded: Bool
    let toggle: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    @FocusState private var hasKeyboardFocus: Bool
    @State private var dropState = ProjectFolderDropState.idle
    @State private var pointerMouseUpHandled = false

    var isActiveDocument: Bool {
        !entry.isDirectory && session.displayDocumentURL?.resolvingSymlinksInPath().path ==
            entry.url.resolvingSymlinksInPath().path
    }
    private var isInSelection: Bool { tree.selection.contains(entry.url) }
    private var isColoredLeonardo: Bool {
        session.colorLeonardoFiles && !entry.isDirectory &&
        AppDocumentKind.classify(entry.url).isLeonardo
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            let rowButton = Button {
                guard !pointerMouseUpHandled else { return }
                activateSingleClick()
            } label: {
                HStack(spacing: 7) {
                    if entry.isDirectory {
                        Image(systemName: expanded ? "chevron.down" : "chevron.right").font(.caption2).frame(width: 10)
                    } else { Color.clear.frame(width: 10, height: 1) }
                    Image(systemName: entry.symbol).foregroundStyle(isActiveDocument ? Color(nsColor: .alternateSelectedControlTextColor) : isColoredLeonardo ? LeonardoFileStyle.foreground(for: colorScheme) : .secondary)
                    Text(entry.name).lineLimit(1)
                        .foregroundStyle(isActiveDocument ? Color(nsColor: .alternateSelectedControlTextColor) : isColoredLeonardo ? LeonardoFileStyle.foreground(for: colorScheme) : .primary)
                    Spacer(minLength: 0)
                    if isInSelection {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption2)
                            .foregroundStyle(session.accentColor)
                            .accessibilityHidden(true)
                    }
                    if let label = dropState.label, let symbol = dropState.symbol {
                        Label(L10n.text(label), systemImage: symbol)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(session.accentColor)
                            .fixedSize()
                    }
                }.padding(.vertical, 6).padding(.horizontal, 6)
                    .modifier(FileRowHighlight(accent: session.accentColor, selected: isActiveDocument,
                                               multiSelected: isInSelection,
                                               dropTarget: dropState.isTarget))
                    .background(isActiveDocument ? Color(nsColor: .selectedContentBackgroundColor) : .clear,
                                in: RoundedRectangle(cornerRadius: 6))
            }
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
            if entry.isDirectory {
                rowButton
            } else {
                rowButton
                    .focusable()
                    .focused($hasKeyboardFocus)
                    .onKeyPress(keys: [.delete, .deleteForward, KeyEquivalent("\u{7F}")], phases: .down) { press in
                        guard hasKeyboardFocus,
                              press.modifiers.intersection([.shift, .control, .option, .command]).isEmpty else {
                            return .ignored
                        }
                        session.delete(entry.url)
                        return .handled
                    }
            }
        }
        .padding(.leading, CGFloat(depth) * 16)
        .overlay {
            ProjectTreeDragSource(url: entry.url, session: session, isActiveTab: isActiveTab, selectedURLs: {
                tree.dragSelection(startingAt: entry.url, rows: rows ?? tree.rows(roots: session.rootEntries))
            }, onMouseDown: { modifiers, _ in
                ProjectTreeRowClickDelay.cancel(in: tree)
                selectOnMouseDown(modifiers)
            }, onMouseUp: { modifiers, count in
                pointerMouseUpHandled = true
                DispatchQueue.main.async { pointerMouseUpHandled = false }
                handleMouseUp(modifiers, clickCount: count)
            })
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .allowsHitTesting(false)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onDrop(of: [DocumentDropProviders.projectTreeItemType, .fileURL], delegate: ProjectFolderDropDelegate(
            folder: entry.isDirectory ? entry.url : entry.url.deletingLastPathComponent(),
            session: session,
            state: $dropState,
            acceptsExternalFiles: entry.isDirectory
        ))
        .accessibilityIdentifier("project-file-" + entry.url.path)
        .accessibilityAddTraits(isActiveDocument || isInSelection ? [.isSelected] : [])
    }

    private func selectOnMouseDown(_ modifiers: NSEvent.ModifierFlags) {
        let visibleRows = rows ?? tree.rows(roots: session.rootEntries)
        if modifiers.contains(.shift) {
            tree.select(entry.url, among: visibleRows, gesture: .extend(additive: modifiers.contains(.command)))
        } else if modifiers.contains(.command) {
            tree.select(entry.url, among: visibleRows, gesture: .toggle)
        } else if !tree.selection.contains(entry.url) {
            tree.select(entry.url, among: visibleRows, gesture: .replace)
        }
    }

    private func handleMouseUp(_ modifiers: NSEvent.ModifierFlags, clickCount: Int) {
        guard !modifiers.contains(.command), !modifiers.contains(.shift) else { return }
        if !entry.isDirectory { hasKeyboardFocus = true }
        let visibleRows = rows ?? tree.rows(roots: session.rootEntries)
        tree.select(entry.url, among: visibleRows, gesture: .replace)
        if entry.isDirectory {
            if clickCount == 1 { toggle() }
            return
        }
        guard clickCount > 1 else {
            ProjectTreeRowClickDelay.schedule(in: tree) { activateSingleClick() }
            return
        }
        ProjectTreeRowClickDelay.cancel(in: tree)
        activateDoubleClick()
    }

    private func activateSingleClick() {
        let visibleRows = rows ?? tree.rows(roots: session.rootEntries)
        tree.select(entry.url, among: visibleRows, gesture: .replace)
        if entry.isDirectory {
            toggle()
        } else {
            hasKeyboardFocus = true
            Task { await session.openDocument(entry.url) }
        }
    }

    private func activateDoubleClick() {
        guard !entry.isDirectory else { return }
        if AppSession.supportedDocumentExtensions.contains(entry.url.pathExtension.lowercased()) {
            Task { await session.openProjectDocumentInTab?(entry.url, nil) }
        } else {
            Task { await session.openDocument(entry.url) }
        }
    }
}

@MainActor
private enum ProjectTreeRowClickDelay {
    private static var pending: [ObjectIdentifier: Task<Void, Never>] = [:]

    static func cancel(in tree: ProjectFileTree) {
        pending.removeValue(forKey: ObjectIdentifier(tree))?.cancel()
    }

    static func schedule(in tree: ProjectFileTree, action: @escaping @MainActor () -> Void) {
        let key = ObjectIdentifier(tree)
        cancel(in: tree)
        let delay = Int64(NSEvent.doubleClickInterval * 1_000)
        pending[key] = Task { @MainActor in
            do { try await Task.sleep(for: .milliseconds(delay)) }
            catch { return }
            guard !Task.isCancelled else { return }
            pending.removeValue(forKey: key)
            action()
        }
    }
}
