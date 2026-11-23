import Foundation

/// The current file grant used to project retained catalogues before they are exposed.
public struct RemoteDownloadAuthorization: Sendable {
    public let descriptor: SharedProjectDescriptor?
    private let scope: CorpusScope?
    private let selection: CorpusSelection?

    public init(descriptor: SharedProjectDescriptor) {
        self.descriptor = descriptor
        scope = descriptor.scope
        selection = descriptor.selection
    }

    /// Desktop grants already include their validated scope in the selected paths.
    public init(selection: CorpusSelection) {
        descriptor = nil
        scope = nil
        self.selection = selection
    }

    public func filter(_ catalogue: RemoteProjectCatalogue) -> RemoteProjectCatalogue {
        let files = catalogue.files.filter { allowsFile($0) }
        let directories = catalogue.directories.filter { allowsDirectory($0) }
        return RemoteProjectCatalogue(files: files, directories: directories)
    }

    public func allows(path: String) -> Bool {
        if let scope, (try? scope.validate(path)) == nil { return false }
        if let selection, (try? selection.validate(path)) == nil { return false }
        return true
    }

    private func allowsFile(_ entry: RemoteFileEntry) -> Bool {
        allows(path: entry.path)
    }

    private func allowsDirectory(_ path: String) -> Bool {
        if let scope, (try? scope.validate(path + "/scope.md")) == nil { return false }
        guard let selection else { return true }
        if selection.folders.contains("") { return true }
        let isRelatedFolder = selection.folders.contains {
            $0 == path || $0.hasPrefix(path + "/") || path.hasPrefix($0 + "/")
        }
        let containsSelectedDocument = selection.documents.contains { $0.hasPrefix(path + "/") }
        return isRelatedFolder || containsSelectedDocument
    }
}
