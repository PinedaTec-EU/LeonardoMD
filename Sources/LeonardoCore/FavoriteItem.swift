import Foundation

public struct FavoriteItem: Codable, Hashable, Sendable {
    public enum Kind: String, Codable, CaseIterable, Sendable {
        case document, project, workspace
    }

    public let kind: Kind
    public let url: URL

    public init(kind: Kind, url: URL) {
        self.kind = kind
        self.url = url.standardizedFileURL
    }
}
