import Foundation

/// Resolves a rendered local link exclusively against documents already in the granted cache.
public struct CachedDocumentLink: Equatable, Sendable {
    public let file: CorpusFile
    public let anchor: String?

    public init?(url: URL, virtualRoot: URL, scope: CorpusScope, files: [CorpusFile]) {
        guard url.isFileURL, virtualRoot.isFileURL,
              url.host == nil || url.host == "" || url.host == "localhost",
              url.query == nil else { return nil }
        let root = virtualRoot.standardizedFileURL.pathComponents
        let target = url.standardizedFileURL.pathComponents
        guard target.count > root.count, Array(target.prefix(root.count)) == root else { return nil }
        let path = target.dropFirst(root.count).joined(separator: "/")
        guard (try? scope.validate(path)) != nil,
              ["md", "markdown", "txt"].contains((path as NSString).pathExtension.lowercased()),
              let file = files.first(where: { $0.path == path }),
              String(data: file.content, encoding: .utf8) != nil else { return nil }
        self.file = file
        anchor = url.fragment?.removingPercentEncoding
    }
}
