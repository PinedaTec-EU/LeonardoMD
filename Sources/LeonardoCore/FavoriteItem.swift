import Foundation

public struct FavoriteItem: Codable, Hashable, Sendable {
    public enum Kind: String, Codable, CaseIterable, Sendable {
        case document, project, workspace
    }

    public let kind: Kind
    public let url: URL
    public var palette: PaletteID?

    public init(kind: Kind, url: URL, palette: PaletteID? = nil) {
        self.kind = kind
        self.palette = kind == .document ? nil : palette
        // Keep identity stable when a folder appears/disappears or a caller adds a trailing slash.
        self.url = URL(fileURLWithPath: url.standardizedFileURL.path, isDirectory: false)
    }
    /// Metadata does not change favorite identity or membership.
    public func matches(_ other: FavoriteItem) -> Bool {
        kind == other.kind && url.standardizedFileURL.path == other.url.standardizedFileURL.path
    }
}

