import Foundation

public actor LocalProjectRepository {
    private let fileManager: FileManager
    private let configurationStore: ConfigurationStore

    public init(
        fileManager: FileManager = .default,
        configurationStore: ConfigurationStore = ConfigurationStore()
    ) {
        self.fileManager = fileManager
        self.configurationStore = configurationStore
    }

    public func createWorkspace(at url: URL) throws -> URL {
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        return url.standardizedFileURL
    }

    public func openWorkspace(at url: URL) throws -> URL {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            throw FileSystemRepositoryError.workspaceDoesNotExist(url)
        }
        guard !isSymbolicLink(url.standardizedFileURL) else {
            throw FileSystemRepositoryError.pathEscapesProject
        }
        guard isDirectory.boolValue else {
            throw FileSystemRepositoryError.workspaceIsNotDirectory(url)
        }
        return url.standardizedFileURL
    }

    public func projects(in workspaceURL: URL, showHidden: Bool = false) throws -> [ProjectDescriptor] {
        let workspace = try openWorkspace(at: workspaceURL)
        let urls = try fileManager.contentsOfDirectory(
            at: workspace,
            includingPropertiesForKeys: [.isDirectoryKey, .isHiddenKey],
            options: []
        )
        return urls.compactMap { url in
            guard !isSymbolicLink(url), isDirectory(url), showHidden || !isHidden(url) else { return nil }
            return ProjectDescriptor(name: url.lastPathComponent, rootURL: url)
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    public func project(at rootURL: URL) throws -> ProjectDescriptor {
        let root = try validateProjectRoot(rootURL)
        return ProjectDescriptor(name: root.lastPathComponent, rootURL: root)
    }

    @discardableResult
    public func renameProject(
        _ project: ProjectDescriptor,
        to newName: String,
        in workspaceURL: URL
    ) throws -> ProjectDescriptor {
        let workspace = try openWorkspace(at: workspaceURL)
        let source = try projectRoot(project, directChildOf: workspace)
        try validateName(newName)
        let destination = workspace.appendingPathComponent(newName, isDirectory: true)
        guard !isSymbolicLink(destination) else {
            throw FileSystemRepositoryError.pathEscapesProject
        }
        guard !fileManager.fileExists(atPath: destination.path) else {
            throw FileSystemRepositoryError.itemAlreadyExists(destination)
        }
        try fileManager.moveItem(at: source, to: destination)
        return ProjectDescriptor(name: newName, rootURL: destination)
    }

    @discardableResult
    public func moveProject(
        _ project: ProjectDescriptor,
        to workspaceURL: URL
    ) throws -> ProjectDescriptor {
        let destinationWorkspace = try openWorkspace(at: workspaceURL)
        let source = try validateProjectRoot(project.rootURL)
        let destination = destinationWorkspace.appendingPathComponent(source.lastPathComponent, isDirectory: true)
        let sourcePath = source.resolvingSymlinksInPath().path
        let destinationWorkspacePath = destinationWorkspace.resolvingSymlinksInPath().path
        guard destinationWorkspacePath != sourcePath,
              !destinationWorkspacePath.hasPrefix(sourcePath + "/") else {
            throw FileSystemRepositoryError.cannotMoveIntoDescendant
        }
        guard source != destination else { return ProjectDescriptor(name: source.lastPathComponent, rootURL: source) }
        guard !isSymbolicLink(destination) else {
            throw FileSystemRepositoryError.pathEscapesProject
        }
        guard !fileManager.fileExists(atPath: destination.path) else {
            throw FileSystemRepositoryError.itemAlreadyExists(destination)
        }
        try fileManager.moveItem(at: source, to: destination)
        return ProjectDescriptor(name: destination.lastPathComponent, rootURL: destination)
    }

    public func deleteProject(_ project: ProjectDescriptor) throws {
        let root = try validateProjectRoot(project.rootURL)
        try fileManager.removeItem(at: root)
    }

    public func children(
        of relativePath: String = "",
        in project: ProjectDescriptor,
        showHidden: Bool = false
    ) throws -> [FileNode] {
        try children(of: resolve(relativePath, under: project.rootURL), in: project.rootURL, showHidden: showHidden)
    }

    public func children(
        of directoryURL: URL,
        in projectRoot: URL,
        showHidden: Bool = false
    ) throws -> [FileNode] {
        let root = try validateProjectRoot(projectRoot)
        let directory = try resolve(directoryURL, under: root)
        guard isDirectory(directory) else {
            throw FileSystemRepositoryError.projectIsNotDirectory(directory)
        }
        let urls = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey, .isHiddenKey, .contentModificationDateKey],
            options: []
        )
        return urls.compactMap { url in
            guard !isSymbolicLink(url), showHidden || !isHidden(url) else { return nil }
            return makeNode(url: url, projectRoot: root)
        }
        .sorted { left, right in
            if left.isDirectory != right.isDirectory {
                return left.isDirectory
            }
            return left.name.localizedStandardCompare(right.name) == .orderedAscending
        }
    }

    @discardableResult
    public func createProject(
        named name: String,
        in workspaceURL: URL,
        configuration: ProjectConfiguration = .default
    ) async throws -> ProjectDescriptor {
        let workspace = try openWorkspace(at: workspaceURL)
        try validateName(name)
        let root = workspace.appendingPathComponent(name, isDirectory: true)
        guard !isSymbolicLink(root) else {
            throw FileSystemRepositoryError.pathEscapesProject
        }
        guard !fileManager.fileExists(atPath: root.path) else {
            throw FileSystemRepositoryError.itemAlreadyExists(root)
        }
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        var projectConfiguration = configuration
        if projectConfiguration.name == nil {
            projectConfiguration.name = name
        }
        try await configurationStore.saveProjectConfiguration(projectConfiguration, for: root)
        return ProjectDescriptor(name: name, rootURL: root)
    }

    @discardableResult
    public func createFolder(
        named name: String,
        in project: ProjectDescriptor,
        at parentRelativePath: String = ""
    ) throws -> FileNode {
        let root = try validateProjectRoot(project.rootURL)
        try validateName(name)
        let parent = try resolve(parentRelativePath, under: root)
        guard isDirectory(parent) else {
            throw FileSystemRepositoryError.projectIsNotDirectory(parent)
        }
        let destination = parent.appendingPathComponent(name, isDirectory: true)
        guard !isSymbolicLink(destination) else {
            throw FileSystemRepositoryError.pathEscapesProject
        }
        guard !fileManager.fileExists(atPath: destination.path) else {
            throw FileSystemRepositoryError.itemAlreadyExists(destination)
        }
        try fileManager.createDirectory(at: destination, withIntermediateDirectories: false)
        return makeNode(url: destination, projectRoot: root)
    }

    @discardableResult
    public func createMarkdown(
        named name: String,
        in project: ProjectDescriptor,
        at parentRelativePath: String = "",
        contents: String = ""
    ) throws -> FileNode {
        let root = try validateProjectRoot(project.rootURL)
        var filename = name
        if URL(fileURLWithPath: filename).pathExtension.isEmpty {
            filename += ".md"
        }
        try validateName(filename)
        let parent = try resolve(parentRelativePath, under: root)
        guard isDirectory(parent) else {
            throw FileSystemRepositoryError.projectIsNotDirectory(parent)
        }
        let destination = parent.appendingPathComponent(filename)
        guard !isSymbolicLink(destination) else {
            throw FileSystemRepositoryError.pathEscapesProject
        }
        guard !fileManager.fileExists(atPath: destination.path) else {
            throw FileSystemRepositoryError.itemAlreadyExists(destination)
        }
        guard let data = contents.data(using: .utf8) else {
            throw DocumentStoreError.unsupportedEncoding(destination)
        }
        try data.write(to: destination, options: [.atomic])
        return makeNode(url: destination, projectRoot: root)
    }

    @discardableResult
    public func rename(
        _ relativePath: String,
        in project: ProjectDescriptor,
        to newName: String
    ) throws -> FileNode {
        let root = try validateProjectRoot(project.rootURL)
        let source = try resolve(relativePath, under: root)
        guard source != root else { throw FileSystemRepositoryError.cannotDeleteProjectRoot }
        guard fileManager.fileExists(atPath: source.path) else {
            throw FileSystemRepositoryError.projectDoesNotExist(source)
        }
        try validateName(newName)
        let destination = source.deletingLastPathComponent().appendingPathComponent(newName)
        guard !isSymbolicLink(destination) else {
            throw FileSystemRepositoryError.pathEscapesProject
        }
        guard !fileManager.fileExists(atPath: destination.path) else {
            throw FileSystemRepositoryError.itemAlreadyExists(destination)
        }
        try fileManager.moveItem(at: source, to: destination)
        return makeNode(url: destination, projectRoot: root)
    }

    @discardableResult
    public func move(
        _ relativePath: String,
        in project: ProjectDescriptor,
        to parentRelativePath: String
    ) throws -> FileNode {
        let root = try validateProjectRoot(project.rootURL)
        let source = try resolve(relativePath, under: root)
        guard source != root else { throw FileSystemRepositoryError.cannotDeleteProjectRoot }
        let parent = try resolve(parentRelativePath, under: root)
        guard isDirectory(parent) else {
            throw FileSystemRepositoryError.projectIsNotDirectory(parent)
        }
        let sourcePath = source.resolvingSymlinksInPath().path
        let parentPath = parent.resolvingSymlinksInPath().path
        if isDirectory(source), parentPath == sourcePath || parentPath.hasPrefix(sourcePath + "/") {
            throw FileSystemRepositoryError.cannotMoveIntoDescendant
        }
        let destination = parent.appendingPathComponent(source.lastPathComponent)
        guard !isSymbolicLink(destination) else {
            throw FileSystemRepositoryError.pathEscapesProject
        }
        guard !fileManager.fileExists(atPath: destination.path) else {
            throw FileSystemRepositoryError.itemAlreadyExists(destination)
        }
        try fileManager.moveItem(at: source, to: destination)
        return makeNode(url: destination, projectRoot: root)
    }

    public func delete(_ relativePath: String, in project: ProjectDescriptor) throws {
        let root = try validateProjectRoot(project.rootURL)
        let target = try resolve(relativePath, under: root)
        guard target != root else { throw FileSystemRepositoryError.cannotDeleteProjectRoot }
        guard fileManager.fileExists(atPath: target.path) else {
            throw FileSystemRepositoryError.projectDoesNotExist(target)
        }
        try fileManager.removeItem(at: target)
    }

    public func search(
        in project: ProjectDescriptor,
        query: String,
        showHidden: Bool = false
    ) throws -> [SearchMatch] {
        let root = try validateProjectRoot(project.rootURL)
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return [] }

        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey, .isHiddenKey],
            options: []
        ) else { return [] }

        var matches: [SearchMatch] = []
        while let url = enumerator.nextObject() as? URL {
            try Task.checkCancellation()
            let result = try scanSearchEntry(
                url,
                root: root,
                needle: needle,
                showHidden: showHidden
            )
            if result.skipDescendants {
                enumerator.skipDescendants()
            }
            matches.append(contentsOf: result.matches)
        }
        return sortSearchMatches(matches)
    }

    /// Streams matching batches as files are scanned. Each non-empty batch contains
    /// the filename and content matches for one file, preserving the existing search
    /// semantics while allowing callers to render partial results immediately.
    public func searchStream(
        in project: ProjectDescriptor,
        query: String,
        showHidden: Bool = false
    ) -> AsyncThrowingStream<[SearchMatch], Error> {
        AsyncThrowingStream<[SearchMatch], Error> { continuation in
            let task = Task { [self] in
                do {
                    let root = try validateProjectRoot(project.rootURL)
                    let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !needle.isEmpty else {
                        continuation.finish()
                        return
                    }
                    guard let enumerator = fileManager.enumerator(
                        at: root,
                        includingPropertiesForKeys: [.isDirectoryKey, .isHiddenKey],
                        options: []
                    ) else {
                        continuation.finish()
                        return
                    }

                    while let url = enumerator.nextObject() as? URL {
                        try Task.checkCancellation()
                        let result = try scanSearchEntry(
                            url,
                            root: root,
                            needle: needle,
                            showHidden: showHidden
                        )
                        if result.skipDescendants {
                            enumerator.skipDescendants()
                        }
                        if !result.matches.isEmpty {
                            if case .terminated = continuation.yield(result.matches) {
                                return
                            }
                        }
                        // Give a waiting consumer and cancellation handlers a chance
                        // to run between files instead of buffering the whole search.
                        await Task.yield()
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish(throwing: CancellationError())
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }

    private struct SearchEntryResult {
        let matches: [SearchMatch]
        let skipDescendants: Bool
    }

    private func scanSearchEntry(
        _ url: URL,
        root: URL,
        needle: String,
        showHidden: Bool
    ) throws -> SearchEntryResult {
        // Symlink entries are never searchable. They are kept out of the
        // result before String(contentsOf:) can follow an alias to its target.
        if isSymbolicLink(url) || containsSymbolicLinkComponent(in: url, under: root) {
            return SearchEntryResult(matches: [], skipDescendants: false)
        }
        if Self.alwaysIgnoredDirectoryNames.contains(url.lastPathComponent) {
            return SearchEntryResult(matches: [], skipDescendants: isDirectory(url))
        }
        if !showHidden && isHidden(url) {
            return SearchEntryResult(matches: [], skipDescendants: isDirectory(url))
        }

        let relative = relativePath(of: url, under: root)
        var matches: [SearchMatch] = []
        let tag = ProjectSearchQuery.tagValue(needle)
        if tag == nil, url.lastPathComponent.localizedCaseInsensitiveContains(needle) {
            matches.append(SearchMatch(
                url: url,
                relativePath: relative,
                lineNumber: nil,
                column: nil,
                snippet: url.lastPathComponent,
                matchedInFileName: true
            ))
        }
        guard !isDirectory(url), Self.markdownExtensions.contains(url.pathExtension.lowercased()) else {
            return SearchEntryResult(matches: matches, skipDescendants: false)
        }
        guard let content = try? String(contentsOf: url, encoding: .utf8) else {
            return SearchEntryResult(matches: matches, skipDescendants: false)
        }
        if let tag {
            let tags = MarkdownDocumentParser.parse(content).tags
            guard !tag.isEmpty, let matched = tags.first(where: { $0.lowercased() == tag.lowercased() }) else {
                return SearchEntryResult(matches: [], skipDescendants: false)
            }
            return SearchEntryResult(matches: [SearchMatch(
                url: url, relativePath: relative, lineNumber: nil, column: nil,
                snippet: "tag: " + matched, matchedInFileName: false
            )], skipDescendants: false)
        }
        for (index, line) in content.components(separatedBy: .newlines).enumerated() {
            try Task.checkCancellation()
            guard let range = line.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) else {
                continue
            }
            let column = line.distance(from: line.startIndex, to: range.lowerBound) + 1
            matches.append(SearchMatch(
                url: url,
                relativePath: relative,
                lineNumber: index + 1,
                column: column,
                snippet: line.trimmingCharacters(in: .whitespaces),
                matchedInFileName: false
            ))
        }
        return SearchEntryResult(matches: matches, skipDescendants: false)
    }

    private func sortSearchMatches(_ matches: [SearchMatch]) -> [SearchMatch] {
        matches.sorted { left, right in
            if left.relativePath != right.relativePath {
                return left.relativePath.localizedStandardCompare(right.relativePath) == .orderedAscending
            }
            return (left.lineNumber ?? 0) < (right.lineNumber ?? 0)
        }
    }

    private func validateProjectRoot(_ url: URL) throws -> URL {
        let root = url.standardizedFileURL
        guard fileManager.fileExists(atPath: root.path) else {
            throw FileSystemRepositoryError.projectDoesNotExist(root)
        }
        guard !isSymbolicLink(root) else {
            throw FileSystemRepositoryError.pathEscapesProject
        }
        guard isDirectory(root) else {
            throw FileSystemRepositoryError.projectIsNotDirectory(root)
        }
        return root
    }

    private func projectRoot(_ project: ProjectDescriptor, directChildOf workspace: URL) throws -> URL {
        let root = try validateProjectRoot(project.rootURL)
        let workspacePath = workspace.standardizedFileURL.resolvingSymlinksInPath().path
        let rootPath = root.standardizedFileURL.resolvingSymlinksInPath().path
        guard root.deletingLastPathComponent().standardizedFileURL.resolvingSymlinksInPath().path == workspacePath,
              rootPath != workspacePath else {
            throw FileSystemRepositoryError.projectNotInWorkspace(root)
        }
        return root
    }

    // Symlink policy: browsing and search omit every symlink entry, while
    // destructive operations reject symlink components in their source,
    // destination, or parent paths. Keeping aliases out of these operations
    // preserves both internal and external targets, including dangling links.
    private func resolve(_ relativePath: String, under root: URL) throws -> URL {
        let root = root.standardizedFileURL
        guard !relativePath.isEmpty else { return root }
        guard !relativePath.hasPrefix("/"), !relativePath.contains("\0") else {
            throw FileSystemRepositoryError.pathEscapesProject
        }

        var current = root
        for component in relativePath.split(separator: "/", omittingEmptySubsequences: true) {
            let component = String(component)
            if component == "." { continue }
            if component == ".." {
                guard current.path != root.path else {
                    throw FileSystemRepositoryError.pathEscapesProject
                }
                current.deleteLastPathComponent()
                continue
            }
            let next = current.appendingPathComponent(component)
            guard !isSymbolicLink(next) else {
                throw FileSystemRepositoryError.pathEscapesProject
            }
            current = next
        }
        return current.standardizedFileURL
    }

    private func resolve(_ url: URL, under root: URL) throws -> URL {
        let root = root.standardizedFileURL
        let candidate = url
        let rootPath = root.path
        guard candidate.path == rootPath || candidate.path.hasPrefix(rootPath + "/") else {
            throw FileSystemRepositoryError.pathEscapesProject
        }
        let relative = candidate.path == rootPath
            ? ""
            : String(candidate.path.dropFirst(rootPath.count + 1))
        return try resolve(relative, under: root)
    }

    private func relativePath(of url: URL, under root: URL) -> String {
        let rootPath = root.standardizedFileURL.path
        let urlPath = url.standardizedFileURL.path
        guard urlPath != rootPath else { return "" }
        return String(urlPath.dropFirst(rootPath.count + 1))
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
            if isSymbolicLink(current) {
                return true
            }
        }
        return false
    }

    private func makeNode(url: URL, projectRoot: URL) -> FileNode {
        let hidden = isHidden(url)
        let kind: FileNodeKind
        if isDirectory(url) {
            kind = .folder
        } else if Self.markdownExtensions.contains(url.pathExtension.lowercased()) {
            kind = .markdown
        } else if Self.imageExtensions.contains(url.pathExtension.lowercased()) {
            kind = .image
        } else {
            kind = .file
        }
        return FileNode(
            name: url.lastPathComponent,
            relativePath: relativePath(of: url, under: projectRoot),
            url: url,
            kind: kind,
            isHidden: hidden
        )
    }

    private func validateName(_ name: String) throws {
        guard !name.isEmpty, name != ".", name != "..", !name.contains("/"), !name.contains("\\"), !name.contains("\0") else {
            throw FileSystemRepositoryError.invalidName(name)
        }
    }

    private func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }

    private func isSymbolicLink(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true
    }

    private func isHidden(_ url: URL) -> Bool {
        url.lastPathComponent.hasPrefix(".")
            || ((try? url.resourceValues(forKeys: [.isHiddenKey]).isHidden) == true)
    }

    private static let imageExtensions: Set<String> = [
        "png", "jpg", "jpeg", "gif", "webp", "heic", "tif", "tiff", "svg", "bmp", "ico"
    ]

    private static let markdownExtensions: Set<String> = ["md", "markdown"]

    private static let alwaysIgnoredDirectoryNames: Set<String> = [".git", ".build", ".worktrees"]
}
