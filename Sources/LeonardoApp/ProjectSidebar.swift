import SwiftUI
import AppKit

struct NavigationEntry: Identifiable, Hashable {
    let url: URL
    let isDirectory: Bool
    var id: URL { url }
    var name: String { url.lastPathComponent }
    var symbol: String {
        if isDirectory { return "folder" }
        if ["md", "markdown"].contains(url.pathExtension.lowercased()) { return "doc.text" }
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
                Text(session.projectURL?.lastPathComponent ?? "Proyecto").font(.headline)
                Spacer()
                Button { session.chooseProject() } label: { Image(systemName: "folder.badge.plus") }
                    .help("Abrir otro proyecto")
            }
            TextField("Buscar archivos y contenido", text: $session.searchQuery)
                .textFieldStyle(PremiumTextFieldStyle(compact: true))
                .accessibilityIdentifier("project-search")
                .onChange(of: session.searchQuery) { _, _ in session.scheduleSearch() }
            HStack {
                Button { session.createItem(directory: false) } label: { Label("Nota", systemImage: "doc.badge.plus") }
                Button { session.createItem(directory: true) } label: { Image(systemName: "folder.badge.plus") }
                Spacer()
                Toggle("Ocultos", isOn: $session.showHidden).toggleStyle(PremiumSwitchStyle()).fixedSize().font(.caption)
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    if session.searchQuery.isEmpty {
                        ForEach(session.rootEntries) { entry in
                            FileTreeRow(entry: entry, session: session)
                        }
                    } else {
                        ForEach(session.searchResults) { match in
                            Button {
                                Task { await session.openDocument(match.url, line: match.line) }
                            } label: {
                                VStack(alignment: .leading, spacing: 3) {
                                    Label(match.url.lastPathComponent, systemImage: "doc.text")
                                    Text(session.relative(match.url) + " · L\(match.line)").font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                                    Text(match.snippet).font(.caption).lineLimit(2).foregroundStyle(.secondary)
                                }.frame(maxWidth: .infinity, alignment: .leading).padding(7)
                            }.buttonStyle(.plain)
                        }
                        if session.searching { ProgressView().controlSize(.small) }
                    }
                }
            }
            Spacer(minLength: 0)
            if session.gitEnabled {
                Button { session.showGit = true } label: {
                    Label(session.gitSummary, systemImage: "arrow.triangle.branch")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }.buttonStyle(PremiumButtonStyle(compact: true)).accessibilityIdentifier("git-panel")
            }
            Divider()
            Button { session.showPreferences = true } label: { Label("Configuración", systemImage: "gearshape") }
                .buttonStyle(PremiumButtonStyle(compact: true))
        }
        .buttonStyle(PremiumButtonStyle(compact: true))
        .padding(16)
        .frame(width: 250)
        .background(.regularMaterial)
        .onChange(of: session.showHidden) { _, _ in Task { await session.refreshTree() } }
    }
}

struct FileTreeRow: View {
    let entry: NavigationEntry
    @Bindable var session: AppSession
    @State private var expanded = false
    @State private var children: [NavigationEntry] = []
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Button {
                if entry.isDirectory {
                    expanded.toggle()
                    if expanded { Task { children = await session.children(of: entry.url) } }
                } else { Task { await session.openDocument(entry.url) } }
            } label: {
                HStack(spacing: 7) {
                    if entry.isDirectory {
                        Image(systemName: expanded ? "chevron.down" : "chevron.right").font(.caption2).frame(width: 10)
                    } else { Color.clear.frame(width: 10, height: 1) }
                    Image(systemName: entry.symbol).foregroundStyle(.secondary)
                    Text(entry.name).lineLimit(1)
                    Spacer(minLength: 0)
                }.padding(.vertical, 6).padding(.horizontal, 6)
                    .background(session.documentURL == entry.url ? session.accentColor.opacity(0.14) : .clear, in: RoundedRectangle(cornerRadius: 6))
            }.buttonStyle(.plain)
                .contextMenu {
                    Button("Mostrar en Finder") { NSWorkspace.shared.activateFileViewerSelecting([entry.url]) }
                    Button("Renombrar…") { session.rename(entry.url) }
                    Button("Mover…") { session.move(entry.url) }
                    if entry.isDirectory {
                        Button("Nueva nota…") { session.createItem(directory: false, parent: entry.url) }
                        Button("Nueva carpeta…") { session.createItem(directory: true, parent: entry.url) }
                    }
                    Divider()
                    Button("Eliminar…", role: .destructive) { session.delete(entry.url) }
                }
                .onDrag { NSItemProvider(object: entry.url as NSURL) }
                .onDrop(of: [.fileURL], isTargeted: nil) { providers in
                    guard entry.isDirectory else { return false }
                    return session.acceptDrop(providers, into: entry.url)
                }
            if expanded {
                ForEach(children) { child in FileTreeRow(entry: child, session: session) }.padding(.leading, 16)
            }
        }
        .task(id: session.treeRevision) {
            if expanded { children = await session.children(of: entry.url) }
        }
    }
}

struct SearchResult: Identifiable {
    let url: URL
    let line: Int
    let snippet: String
    var id: String { "\(url.path):\(line):\(snippet)" }
}
