import SwiftUI
import LeonardoSync

struct SharedProjectSelectionView: View {
    let root: URL
    let controller: DesktopSyncController
    @Environment(\.dismiss) private var dismiss
    @State private var folders: [String] = []
    @State private var documents: [String] = []
    @State private var error: String?

    init(root: URL, controller: DesktopSyncController, selection: CorpusSelection? = nil) {
        self.root = root
        self.controller = controller
        _folders = State(initialValue: selection?.folders ?? [])
        _documents = State(initialValue: selection?.documents ?? [])
    }

    private var selection: CorpusSelection? { try? CorpusSelection(folders: folders, documents: documents) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L10n.text("Select shared content")).font(.title2)
            Text(root.lastPathComponent).foregroundStyle(.secondary)
            HStack {
                Button(L10n.text("Choose folders and documents")) { choose() }
                Button(L10n.text("Entire project")) { folders = [""]; documents = [] }
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(folders, id: \.self) { folder in
                        HStack {
                            Label(folder.isEmpty ? L10n.text("Entire project") : folder, systemImage: "folder")
                                .lineLimit(1).truncationMode(.middle).help(folder)
                            Spacer()
                            Button(L10n.text("Remove")) { folders.removeAll { $0 == folder } }
                        }
                        Divider()
                    }
                    ForEach(documents, id: \.self) { path in
                        HStack {
                            Label(path, systemImage: "doc").lineLimit(1).truncationMode(.middle).help(path)
                            Spacer()
                            Button(L10n.text("Remove")) { documents.removeAll { $0 == path } }
                        }
                        Divider()
                    }
                }.padding(8)
            }.frame(minHeight: 160)
            if let error { Text(error).foregroundStyle(.red) }
            HStack {
                Button(L10n.text("Cancel")) { dismiss() }
                Spacer()
                Button(L10n.text("Share selected content")) {
                    guard let selection else { return }
                    Task {
                        await controller.share(root, selection: selection)
                        if controller.error == nil { dismiss() }
                    }
                }.disabled(selection == nil || controller.busy)
            }
        }.padding(24).frame(width: 540).background(.background).buttonStyle(PremiumButtonStyle())
    }

    private func choose() {
        let normalizedRoot = root.standardizedFileURL.resolvingSymlinksInPath()
        let panel = NSOpenPanel()
        panel.directoryURL = normalizedRoot
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = true
        panel.begin { response in
            guard response == .OK else { return }
            do {
                var nextFolders = folders, nextDocuments = documents
                for url in panel.urls {
                    let normalized = url.standardizedFileURL
                    let rootComponents = normalizedRoot.pathComponents
                    guard normalized.pathComponents.starts(with: rootComponents) else { throw SyncError.outsideScope }
                    let path = normalized.pathComponents.dropFirst(rootComponents.count).joined(separator: "/")
                    let metadata = try FileManager.default.attributesOfItem(atPath: normalized.path)
                    guard metadata[.type] as? FileAttributeType != .typeSymbolicLink else { throw SyncError.invalidPath }
                    let scope = try CorpusScope(folder: "")
                    if metadata[.type] as? FileAttributeType == .typeDirectory {
                        _ = try scope.fileURL(for: path.isEmpty ? "selection.md" : path + "/selection.md", under: normalizedRoot)
                        nextFolders.append(path)
                    } else {
                        _ = try scope.fileURL(for: path, under: normalizedRoot)
                        nextDocuments.append(path)
                    }
                }
                let next = try CorpusSelection(folders: nextFolders, documents: nextDocuments)
                folders = next.folders; documents = next.documents; error = nil
            } catch {
                switch error as? SyncError {
                case .outsideScope: self.error = L10n.text("Select content inside the current project.")
                case .excludedFile: self.error = L10n.text("Select Markdown, text or image files outside generated folders.")
                case .invalidPath: self.error = L10n.text("Select regular folders and documents without symbolic links.")
                case .sizeLimitExceeded: self.error = L10n.text("Too many selected folders or documents.")
                default: self.error = error.localizedDescription
                }
            }
        }
    }
}
