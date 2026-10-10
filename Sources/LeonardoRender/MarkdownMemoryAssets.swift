import Foundation

/// Immutable corpus assets; lookup never touches disk or network.
public final class MarkdownMemoryAssets: Sendable, Equatable {
    private let files: [String: Data]
    public init(files: [String: Data]) { self.files = files }
    public static func == (lhs: MarkdownMemoryAssets, rhs: MarkdownMemoryAssets) -> Bool { lhs === rhs }

    func data(for url: URL) -> Data? {
        guard url.scheme == "leonardo-document", url.host == "local",
              url.user == nil, url.password == nil, url.port == nil else { return nil }
        let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        guard !path.isEmpty, path.utf8.count <= 4_096, !path.contains("\\"), !path.contains(":"),
              components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }),
              ["gif", "jpeg", "jpg", "png", "svg", "webp"].contains(url.pathExtension.lowercased()) else { return nil }
        return files[path]
    }
}
