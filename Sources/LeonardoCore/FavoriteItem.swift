import Foundation

public struct FavoriteItem: Codable, Hashable, Sendable {
    public enum Kind: String, Codable, CaseIterable, Sendable {
        case document, project, workspace
    }

    public let kind: Kind
    public let url: URL

    public init(kind: Kind, url: URL) {
        self.kind = kind
        // Keep identity stable when a folder appears/disappears or a caller adds a trailing slash.
        self.url = URL(fileURLWithPath: url.standardizedFileURL.path, isDirectory: false)
    }
}
