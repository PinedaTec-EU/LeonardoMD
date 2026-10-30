import AppKit
import Foundation
import UniformTypeIdentifiers
import LeonardoCore

extension AppSession {
    func chooseDocument() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.plainText] + AppDocumentKind.allCases.compactMap { kind in
            switch kind {
            case .markdown: return nil
            case .leonardoTemplate: return UTType(filenameExtension: "mdlf")
            case .leonardoResponse: return UTType(filenameExtension: "mdlr")
            case .leonardoPackage: return UTType(filenameExtension: "mdlz")
            }
        } + [UTType(filenameExtension: "md") ?? .plainText]
        panel.allowsMultipleSelection = false
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        presentFilePanel(panel) { [weak self] url in Task { await self?.open(url) } }
    }
    func chooseProject() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = L10n.text("Open project")
        presentFilePanel(panel) { [weak self] url in Task { await self?.openProject(url) } }
    }
    @discardableResult
    func openProject(_ url: URL, retainingCurrentDocument: Bool = false) async -> Bool {
        guard !isClosing, !stopped else { return false }
        fileOperationCount += 1
        defer { fileOperationCount -= 1 }
        do {
            try InstancePathOwnership.shared.claim(url)
            try await authorizePath(url, .directory)
        } catch { report(error); return false }
        guard !stopped, !isClosing else { return false }
        await initialize()
        let rootPath = url.standardizedFileURL.resolvingSymlinksInPath().path
        let retainsDocument = retainingCurrentDocument && displayDocumentURL.map {
            $0.standardizedFileURL.resolvingSymlinksInPath().path.hasPrefix(rootPath == "/" ? "/" : rootPath + "/")
        } == true
        if !retainsDocument {
            guard await prepareNavigation() else { return false }
        }
        guard !busy, !isClosing, !stopped else { return false }
        busy = true
        defer { busy = false }
        do {
            _ = try await files.project(at: url)
            let configuration = try await configurations.loadProjectConfiguration(for: url)
            guard !isClosing, !stopped else { return false }
            await refreshFavoriteAssociations()
            guard !isClosing, !stopped else { return false }
            projectURL = url
            git = GitRepository(rootURL: url)
            projectConfiguration = configuration
            projectBaseline = configuration
            resetSearch()
            focus = false
            if let currentDocument = displayDocumentURL,
               !currentDocument.standardizedFileURL.resolvingSymlinksInPath().path.hasPrefix(rootPath == "/" ? "/" : rootPath + "/") {
                discardPackageWorkspace()
                self.documentURL = nil; documentSourceURL = nil; snapshot = nil; content = ""
                documentKind = .markdown; documentStorage = .localFile; leonardoFormatWarning = false
            }
            globalPreferences.recentProjectPaths.removeAll { $0 == url }
            globalPreferences.recentProjectPaths.insert(url, at: 0)
            globalPreferences.recentProjectPaths = Array(globalPreferences.recentProjectPaths.prefix(12))
            persistSettings()
            await refreshTree()
            await refreshGit()
            updateTitle()
            return true
        } catch { report(error); return false }
    }
    func detachProject() async {
        guard !isClosing, !stopped else { return }
        fileOperationCount += 1
        defer { fileOperationCount -= 1 }
        guard await prepareNavigation(), !isClosing, !stopped else { return }
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
            let include = try await entryFilter(url)
            let nodes = try await files.children(of: url, in: root, showHidden: showHidden)
            guard !stopped, projectURL == root else { return [] }
            return nodes.filter { include($0.url, $0.isDirectory) }
                .map { NavigationEntry(url: $0.url, isDirectory: $0.isDirectory) }
                .filter { showAllFiles || $0.isDirectory || AppDocumentKind.isSupportedExtension($0.url.pathExtension) }
                .sorted { left, right in
                    if foldersFirst, left.isDirectory != right.isDirectory { return left.isDirectory }
                    let order = left.name.localizedStandardCompare(right.name)
                    return fileSortDescending ? order == .orderedDescending : order == .orderedAscending
                }
        } catch { report(error); return [] }
    }
    func refreshTree() async {
        guard let root = projectURL else { return }
        let entries = await children(of: root)
        guard !stopped, projectURL == root else { return }
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
                let include = try await self.entryFilter(root)
                guard !self.stopped, !Task.isCancelled else { return }
                let stream = await self.files.searchStream(in: project, query: query, showHidden: self.showHidden, include: include)
                for try await results in stream {
                    guard !self.stopped, !Task.isCancelled, self.projectURL == root, self.searchQuery == query else { return }
                    self.searchResults += results.map { SearchResult(url: $0.url, line: $0.lineNumber ?? 1, snippet: $0.snippet) }
                }
            } catch { if !Task.isCancelled { self.report(error) } }
            if !Task.isCancelled { self.searching = false }
        }
    }
    func createItem(directory: Bool, parent: URL? = nil) {
        guard let root = projectURL else { return }
        let identity = SessionFileOperationIdentity(sourceURL: parent ?? root, session: self)
        Task {
            guard identity.isCurrent(in: self),
                  let name = await prompt(title: directory ? L10n.text("New folder") : L10n.text("New Markdown"), initial: directory ? L10n.text("Folder") : L10n.text("New note filename")) else { return }
            guard identity.isCurrent(in: self) else { return }
            let project = ProjectDescriptor(name: root.lastPathComponent, rootURL: root)
            let parentPath = relative(parent ?? root)
            fileOperationCount += 1
            defer { fileOperationCount -= 1 }
            do {
                let filename = !directory && URL(fileURLWithPath: name).pathExtension.isEmpty ? name + ".md" : name
                try await authorizePath((parent ?? root).appendingPathComponent(filename), directory ? .directoryMutation : .document)
                guard identity.isCurrent(in: self) else { return }
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
    @discardableResult
    func rename(_ url: URL) -> Task<Void, Never>? {
        guard let root = projectURL else { return nil }
        let identity = SessionFileOperationIdentity(sourceURL: url, session: self)
        return Task {
            guard identity.isCurrent(in: self), let name = await prompt(title: L10n.text("Rename"), initial: url.lastPathComponent) else { return }
            guard identity.isCurrent(in: self) else { return }
            fileOperationCount += 1
            defer { fileOperationCount -= 1 }
            guard await prepareNavigation(), await prepareRelatedFileOperation?(url) ?? true,
                  identity.isCurrent(in: self) else { return }
            do {
                let intent: DesktopPeerPathIntent = (try url.resourceValues(forKeys: [.isDirectoryKey])).isDirectory == true ? .directoryMutation : .document
                try await authorizePath(url, intent)
                guard identity.isCurrent(in: self) else { return }
                try await authorizePath(url.deletingLastPathComponent().appendingPathComponent(name), intent)
                guard identity.isCurrent(in: self) else { return }
                let node = try await files.rename(relative(url), in: ProjectDescriptor(name: root.lastPathComponent, rootURL: root), to: name)
                await updateMovedDocument(from: url, to: node.url)
                await relatedPathMoved?(url, node.url)
                await refreshTree()
            } catch { report(error) }
        }
    }
    func move(_ url: URL) {
        let identity = SessionFileOperationIdentity(sourceURL: url, session: self)
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.directoryURL = projectURL
        panel.prompt = L10n.text("Move here")
        presentFilePanel(panel) { [weak self] destination in
            guard let self, identity.isCurrent(in: self) else { return }
            self.move(identity.sourceURL, into: destination)
        }
    }
    @discardableResult
    func move(_ url: URL, into parent: URL) -> Task<Void, Never>? {
        guard let root = projectURL else { return nil }
        let identity = SessionFileOperationIdentity(sourceURL: url, session: self)
        return Task {
            guard identity.isCurrent(in: self) else { return }
            fileOperationCount += 1
            defer { fileOperationCount -= 1 }
            guard await prepareNavigation(), await prepareRelatedFileOperation?(url) ?? true,
                  identity.isCurrent(in: self) else { return }
            do {
                let intent: DesktopPeerPathIntent = (try url.resourceValues(forKeys: [.isDirectoryKey])).isDirectory == true ? .directoryMutation : .document
                try await authorizePath(url, intent)
                guard identity.isCurrent(in: self) else { return }
                try await authorizePath(parent.appendingPathComponent(url.lastPathComponent), intent)
                guard identity.isCurrent(in: self) else { return }
                let node = try await files.move(relative(url), in: ProjectDescriptor(name: root.lastPathComponent, rootURL: root), to: relative(parent))
                await updateMovedDocument(from: url, to: node.url)
                await relatedPathMoved?(url, node.url)
                await refreshTree()
            } catch { report(error) }
        }
    }
    func updateMovedDocument(from source: URL, to destination: URL) async {
        let previousMode = mode
        // Package tabs edit an extracted temporary document, so documentURL
        // is outside the moved project. Remap the package identity first;
        // regular documents continue through the existing reopen path.
        remapPackageIdentity(from: source, to: destination)
        if let current = documentURL {
            if current == source { await openDocument(destination) }
            else if current.path.hasPrefix(source.path + "/") {
                let suffix = String(current.path.dropFirst(source.path.count + 1))
                await openDocument(destination.appendingPathComponent(suffix))
            }
        }
        mode = previousMode
    }
    func acceptDrop(_ providers: [NSItemProvider], into parent: URL) -> Bool {
        guard DocumentDropProviders.canLoad(providers) else { return false }
        Task {
            guard let urls = await DocumentDropProviders.urls(providers) else { return }
            if DocumentTabs.acceptsDrop(urls), let openDroppedDocuments {
                await openDroppedDocuments(urls)
            } else if urls.count == 1, let url = urls.first, let root = projectURL,
                      DocumentDropProviders.isProjectMove(url, in: root) {
                move(url, into: parent)
            }
        }
        return true
    }

    func relative(_ url: URL) -> String {
        guard let root = projectURL else { return url.path }
        if url == root { return "" }
        guard url.standardizedFileURL.path.hasPrefix(root.standardizedFileURL.path + "/") else { return "../" }
        return String(url.standardizedFileURL.path.dropFirst(root.standardizedFileURL.path.count + 1))
    }
    func prompt(title: String, initial: String) async -> String? {
        let alert = NSAlert()
        alert.messageText = title
        let input = NSTextField(string: initial)
        input.frame = NSRect(x: 0, y: 0, width: 300, height: 24)
        alert.accessoryView = input
        alert.addButton(withTitle: L10n.text("Save"))
        alert.addButton(withTitle: L10n.text("Cancel"))
        alert.window.initialFirstResponder = input
        return await NativeDialog.present(alert, on: presentationWindow) == .alertFirstButtonReturn ? input.stringValue : nil
    }
}
