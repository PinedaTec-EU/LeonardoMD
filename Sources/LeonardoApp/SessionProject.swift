import AppKit
import Foundation
import UniformTypeIdentifiers
import LeonardoCore

extension AppSession {
    func chooseDocument() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.plainText, UTType(filenameExtension: "md") ?? .plainText]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { await open(url) }
    }
    func chooseProject() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = "Abrir proyecto"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { await openProject(url) }
    }
    func openProject(_ url: URL) async {
        await initialize()
        guard await prepareNavigation() else { return }
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do {
            _ = try await files.project(at: url)
            let configuration = try await configurations.loadProjectConfiguration(for: url)
            projectURL = url
            git = GitRepository(rootURL: url)
            projectConfiguration = configuration
            projectBaseline = configuration
            resetSearch()
            focus = false
            if let documentURL, !documentURL.path.hasPrefix(url.path + "/") {
                self.documentURL = nil; snapshot = nil; content = ""
            }
            globalPreferences.recentProjectPaths.removeAll { $0 == url }
            globalPreferences.recentProjectPaths.insert(url, at: 0)
            globalPreferences.recentProjectPaths = Array(globalPreferences.recentProjectPaths.prefix(12))
            persistSettings()
            await refreshTree()
            await refreshGit()
            updateTitle()
        } catch { report(error) }
    }
    func detachProject() async {
        guard await prepareNavigation() else { return }
        projectURL = nil
        projectConfiguration = .default
        projectBaseline = .default
        rootEntries = []
        searchResults = []
        searchQuery = ""
        focus = false
        resetSearch()
        updateTitle()
    }
    func resetSearch() {
        searchTask?.cancel()
        searchTask = nil
        searchQuery = ""
        searchResults = []
        searching = false
    }
    func children(of url: URL) async -> [NavigationEntry] {
        guard let root = projectURL else { return [] }
        do {
            return try await files.children(of: url, in: root, showHidden: showHidden)
                .map { NavigationEntry(url: $0.url, isDirectory: $0.isDirectory) }
        } catch { report(error); return [] }
    }
    func refreshTree() async {
        guard let root = projectURL else { return }
        let entries = await children(of: root)
        if entries != rootEntries { rootEntries = entries }
        treeRevision += 1
    }
    func scheduleSearch() {
        searchTask?.cancel()
        guard let root = projectURL, !searchQuery.isEmpty else { searchResults = []; searching = false; return }
        let query = searchQuery
        searchTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
            guard let self else { return }
            self.searching = true
            self.searchResults = []
            do {
                let project = ProjectDescriptor(name: root.lastPathComponent, rootURL: root)
                let stream = await self.files.searchStream(in: project, query: query, showHidden: self.showHidden)
                for try await results in stream {
                    guard !Task.isCancelled, self.projectURL == root, self.searchQuery == query else { return }
                    self.searchResults += results.map { SearchResult(url: $0.url, line: $0.lineNumber ?? 1, snippet: $0.snippet) }
                }
            } catch { if !Task.isCancelled { self.report(error) } }
            if !Task.isCancelled { self.searching = false }
        }
    }
    func createItem(directory: Bool, parent: URL? = nil) {
        guard let root = projectURL,
              let name = prompt(title: directory ? "Nueva carpeta" : "Nuevo Markdown", initial: directory ? "Carpeta" : "nota.md") else { return }
        let project = ProjectDescriptor(name: root.lastPathComponent, rootURL: root)
        let parentPath = relative(parent ?? root)
        Task {
            do {
                if directory { _ = try await files.createFolder(named: name, in: project, at: parentPath) }
                else {
                    let node = try await files.createMarkdown(named: name, in: project, at: parentPath)
                    await openDocument(node.url)
                    mode = .edit
                }
                await refreshTree()
            } catch { report(error) }
        }
    }
    func rename(_ url: URL) {
        guard let root = projectURL, let name = prompt(title: "Renombrar", initial: url.lastPathComponent) else { return }
        Task {
            guard await prepareNavigation() else { return }
            do {
                let node = try await files.rename(relative(url), in: ProjectDescriptor(name: root.lastPathComponent, rootURL: root), to: name)
                await updateMovedDocument(from: url, to: node.url)
                await refreshTree()
            } catch { report(error) }
        }
    }
    func move(_ url: URL) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.directoryURL = projectURL
        panel.prompt = "Mover aquí"
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        move(url, into: destination)
    }
    func move(_ url: URL, into parent: URL) {
        guard let root = projectURL else { return }
        Task {
            guard await prepareNavigation() else { return }
            do {
                let node = try await files.move(relative(url), in: ProjectDescriptor(name: root.lastPathComponent, rootURL: root), to: relative(parent))
                await updateMovedDocument(from: url, to: node.url)
                await refreshTree()
            } catch { report(error) }
        }
    }
    func updateMovedDocument(from source: URL, to destination: URL) async {
        guard let current = documentURL else { return }
        let previousMode = mode
        if current == source { await openDocument(destination) }
        else if current.path.hasPrefix(source.path + "/") {
            let suffix = String(current.path.dropFirst(source.path.count + 1))
            await openDocument(destination.appendingPathComponent(suffix))
        }
        mode = previousMode
    }
    func delete(_ url: URL) {
        guard let root = projectURL else { return }
        let alert = NSAlert()
        alert.messageText = "¿Eliminar \(url.lastPathComponent)?"
        alert.informativeText = "Esta operación elimina el elemento del disco."
        alert.addButton(withTitle: "Cancelar")
        alert.addButton(withTitle: "Eliminar")
        guard alert.runModal() == .alertSecondButtonReturn else { return }
        Task {
            guard await prepareNavigation() else { return }
            do {
                try await files.delete(relative(url), in: ProjectDescriptor(name: root.lastPathComponent, rootURL: root))
                if let current = documentURL, current == url || current.path.hasPrefix(url.path + "/") {
                    documentURL = nil; snapshot = nil; content = ""; updateTitle()
                }
                await refreshTree()
            } catch { report(error) }
        }
    }
    func acceptDrop(_ providers: [NSItemProvider], into parent: URL) -> Bool {
        guard let provider = providers.first else { return false }
        provider.loadObject(ofClass: NSURL.self) { [weak self] object, _ in
            guard let url = object as? URL else { return }
            Task { @MainActor in self?.move(url, into: parent) }
        }
        return true
    }
    func relative(_ url: URL) -> String {
        guard let root = projectURL else { return url.path }
        if url == root { return "" }
        guard url.standardizedFileURL.path.hasPrefix(root.standardizedFileURL.path + "/") else { return "../" }
        return String(url.standardizedFileURL.path.dropFirst(root.standardizedFileURL.path.count + 1))
    }
    func prompt(title: String, initial: String) -> String? {
        let alert = NSAlert()
        alert.messageText = title
        let input = NSTextField(string: initial)
        input.frame = NSRect(x: 0, y: 0, width: 300, height: 24)
        alert.accessoryView = input
        alert.addButton(withTitle: "Guardar")
        alert.addButton(withTitle: "Cancelar")
        alert.window.initialFirstResponder = input
        return alert.runModal() == .alertFirstButtonReturn ? input.stringValue : nil
    }
}
