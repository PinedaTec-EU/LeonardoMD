import AppKit
import Foundation
import SwiftUI
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
                .filter { $0.isDirectory || showNonDocumentFiles || AppDocumentKind.isSupportedExtension($0.url.pathExtension) }
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
                let showNonDocumentFiles = self.showNonDocumentFiles
                let searchInclude: @Sendable (URL, Bool) -> Bool = { url, isDirectory in
                    include(url, isDirectory) &&
                        (isDirectory || LeonardoProjectFileVisibility.shouldShowFile(
                            at: url.path,
                            showNonDocumentFiles: showNonDocumentFiles
                        ))
                }
                let stream = await self.files.searchStream(in: project, query: query,
                                                           showHidden: self.showHidden, include: searchInclude)
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
        move([url], into: parent)
    }

    @discardableResult
    func move(_ urls: [URL], into parent: URL) -> Task<Void, Never>? {
        transfer(urls, into: parent, operation: .move)
    }

    @discardableResult
    func copy(_ url: URL, into parent: URL) -> Task<Void, Never>? {
        copy([url], into: parent)
    }

    @discardableResult
    func copy(_ urls: [URL], into parent: URL) -> Task<Void, Never>? {
        transfer(urls, into: parent, operation: .copy)
    }

    private enum ProjectItemTransferOperation: Equatable {
        case move
        case copy
    }

    private func transfer(
        _ urls: [URL],
        into parent: URL,
        operation: ProjectItemTransferOperation
    ) -> Task<Void, Never>? {
        guard let root = projectURL, !urls.isEmpty else { return nil }
        // Keep the supplied path components for the repository's symlink-aware resolver.
        guard let parentPath = projectRelativePath(parent, in: root) else {
            return Task { report(FileSystemRepositoryError.pathEscapesProject) }
        }
        let sourcePaths = urls.compactMap { projectRelativePath($0, in: root) }
        guard sourcePaths.count == urls.count, sourcePaths.allSatisfy({ !$0.isEmpty }) else {
            return Task { report(FileSystemRepositoryError.pathEscapesProject) }
        }
        // A move into the same parent is already satisfied. Compare resolved
        // parent paths so an external symlink alias (for example, /tmp) does
        // not turn that no-op into a repository collision. Internal symlink
        // components still flow to repository preflight for rejection.
        let destination = parent.resolvingSymlinksInPath().standardizedFileURL.path
        let transferItems = zip(urls, sourcePaths).filter { url, _ in
            guard operation == .move else { return true }
            let sourceParent = url.deletingLastPathComponent()
                .resolvingSymlinksInPath().standardizedFileURL.path
            guard sourceParent == destination else {
                return true
            }
            // A symlink must reach repository preflight even if its path looks
            // like a same-folder move.
            return containsSymbolicLinkComponent(in: parent, under: root)
                || containsSymbolicLinkComponent(in: url, under: root)
        }
        let transferURLs = transferItems.map { $0.0 }
        let transferPaths = transferItems.map { $0.1 }
        guard !transferURLs.isEmpty else { return nil }
        let operationName = operation == .copy ? "copy" : "move"
        let identity = SessionFileOperationIdentity(sourceURL: transferURLs[0], session: self)
        return Task {
            guard identity.isCurrent(in: self) else { return }
            fileOperationCount += 1
            defer { fileOperationCount -= 1 }
            guard await prepareNavigation(), identity.isCurrent(in: self) else {
                logger.info("Project-item transfer stopped during navigation preparation operation=\(operationName, privacy: .public)")
                return
            }
            for url in transferURLs {
                let canProceed = await prepareRelatedFileOperation?(url) ?? true
                guard canProceed, identity.isCurrent(in: self) else {
                    logger.info("Project-item transfer stopped by related-session preparation operation=\(operationName, privacy: .public)")
                    return
                }
            }
            do {
                let intents = try transferURLs.map { url -> DesktopPeerPathIntent in
                    try url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true ? .directoryMutation : .document
                }
                for (url, intent) in zip(transferURLs, intents) {
                    try await authorizePath(url, intent)
                    guard identity.isCurrent(in: self) else { return }
                    if operation == .move {
                        try await authorizePath(parent.appendingPathComponent(url.lastPathComponent), intent)
                        guard identity.isCurrent(in: self) else { return }
                    }
                }
                let project = ProjectDescriptor(name: root.lastPathComponent, rootURL: root)
                let nodes: [FileNode]
                switch operation {
                case .move:
                    nodes = try await files.move(transferPaths, in: project, to: parentPath)
                case .copy:
                    nodes = try await files.copy(transferPaths, in: project, to: parentPath) { @MainActor destinations in
                        for (destination, intent) in zip(destinations, intents) {
                            try Task.checkCancellation()
                            guard identity.isCurrent(in: self) else { throw CancellationError() }
                            try await self.authorizePath(destination, intent)
                        }
                        guard identity.isCurrent(in: self) else { throw CancellationError() }
                    }
                }
                if operation == .move {
                    for (source, node) in zip(transferURLs, nodes) {
                        await updateMovedDocument(from: source, to: node.url)
                        await relatedPathMoved?(source, node.url)
                    }
                }
                projectFileTree.clearSelection()
                await refreshTree()
                logger.info("Project-item transfer completed operation=\(operationName, privacy: .public) items=\(nodes.count, privacy: .public)")
            } catch is CancellationError {
                return
            } catch {
                logger.error("Project-item transfer failed operation=\(operationName, privacy: .public): \(String(describing: error), privacy: .private)")
                report(error)
            }
        }
    }

    private func containsSymbolicLinkComponent(in url: URL, under root: URL) -> Bool {
        let root = root.standardizedFileURL
        let candidate = url.standardizedFileURL
        let rootPath = root.path
        guard candidate.path == rootPath || candidate.path.hasPrefix(rootPath + "/") else {
            return true
        }

        var current = root
        let relative = String(candidate.path.dropFirst(rootPath.count))
        for component in relative.split(separator: "/", omittingEmptySubsequences: true) {
            current.appendPathComponent(String(component))
            if (try? current.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true {
                return true
            }
        }
        return false
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
    func acceptDrop(
        _ providers: [NSItemProvider],
        into parent: URL,
        copy: Bool = false,
        expectedProjectURLs: [URL]? = nil
    ) -> Bool {
        guard DocumentDropProviders.isSupportedFolderDrop(providers) else {
            logger.warning("Folder drop rejected unsupported providers=\(providers.count, privacy: .public)")
            return false
        }
        let isProjectTreeDrop = DocumentDropProviders.isProjectTreeDrop(providers)
        let dropProject = projectURL
        guard !isProjectTreeDrop || expectedProjectURLs != nil else { return false }
        logger.info("Folder drop accepted providerCount=\(providers.count, privacy: .public) projectTree=\(isProjectTreeDrop, privacy: .public) copy=\(copy, privacy: .public)")
        let urlLoad = isProjectTreeDrop
            ? DocumentDropProviders.startLoadingProjectTreeURLs(providers)
            : DocumentDropProviders.startLoadingURLs(providers)
        Task {
            guard let urls = await urlLoad.value else {
                logger.error("Folder drop payload did not produce file URLs projectTree=\(isProjectTreeDrop, privacy: .public)")
                return
            }
            if isProjectTreeDrop {
                guard urls == expectedProjectURLs, let root = dropProject, root == projectURL else {
                    logger.error("Folder drop payload or project context no longer matches the local drag")
                    return
                }
                guard urls.allSatisfy({ DocumentDropProviders.isProjectMove($0, in: root) }) else {
                    logger.error("Folder drop rejected out-of-project or root items count=\(urls.count, privacy: .public)")
                    return
                }
                guard let operationTask = copy ? self.copy(urls, into: parent) : self.move(urls, into: parent) else {
                    logger.debug("Folder move was a no-op because every item already belongs to the destination")
                    return
                }
                await operationTask.value
            } else if DocumentTabs.acceptsDrop(urls), let openDroppedDocuments {
                await openDroppedDocuments(urls)
            } else {
                logger.warning("External folder drop rejected URLs=\(urls.count, privacy: .public)")
            }
        }
        return true
    }

    func projectRelativePath(_ url: URL, in root: URL) -> String? {
        guard url.isFileURL, !url.pathComponents.contains(".."),
              !url.pathComponents.contains(".") else { return nil }
        let rootPath = root.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        if path == rootPath { return "" }
        let prefix = rootPath == "/" ? "/" : rootPath + "/"
        guard path.hasPrefix(prefix) else { return nil }
        return String(path.dropFirst(prefix.count))
    }

    func relative(_ url: URL) -> String {
        guard let root = projectURL else { return url.path }
        return projectRelativePath(url, in: root) ?? "../"
    }
    func prompt(title: String, initial: String) async -> String? {
        let alert = NSAlert()
        alert.messageText = title
        let value = PremiumNameValue(initial)
        let input = NSHostingView(rootView: PremiumNameInput(value: value)
            .modifier(SessionAppearance(session: self)))
        input.frame = NSRect(x: 0, y: 0, width: 312, height: 52)
        alert.accessoryView = input
        alert.addButton(withTitle: L10n.text("Save"))
        alert.addButton(withTitle: L10n.text("Cancel"))
        alert.window.initialFirstResponder = input
        return await NativeDialog.present(alert, on: presentationWindow) == .alertFirstButtonReturn ? value.text : nil
    }
}
