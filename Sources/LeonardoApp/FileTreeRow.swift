import SwiftUI
import AppKit

struct FileTreeRow: View {
    let entry: NavigationEntry
    @Bindable var session: AppSession
    let depth: Int
    let expanded: Bool
    let toggle: () -> Void
    private var selected: Bool {
        session.globalPreferences.followActiveFile && !entry.isDirectory &&
        (session.documentSourceURL ?? session.documentURL)?.standardizedFileURL == entry.url.standardizedFileURL
    }
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
                    Image(systemName: entry.symbol).foregroundStyle(selected ? Color(nsColor: .selectedTextColor) : isColoredLeonardo ? LeonardoFileStyle.wine : .secondary)
                    Text(entry.name).lineLimit(1)
                        .foregroundStyle(selected ? Color(nsColor: .selectedTextColor) : isColoredLeonardo ? LeonardoFileStyle.wine : .primary)
                    Spacer(minLength: 0)
                }.padding(.vertical, 6).padding(.horizontal, 6)
                    .modifier(FileRowHighlight(accent: session.accentColor))
                    .background(selected ? Color(nsColor: .selectedTextBackgroundColor) : .clear,
                                in: RoundedRectangle(cornerRadius: 6))
            }
                .contextMenu {
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
                // Include the context menu in the plain-style scope so it cannot
                // inherit the sidebar's stateful PremiumButtonStyle.
                .buttonStyle(.plain)
                .onDrag { NSItemProvider(object: entry.url as NSURL) }
                .onDrop(of: [.fileURL], isTargeted: nil) { providers in
                    guard entry.isDirectory else { return false }
                    return session.acceptDrop(providers, into: entry.url)
                }
        }
        .padding(.leading, CGFloat(depth) * 16)
        .accessibilityIdentifier("project-file-" + entry.url.path)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}
