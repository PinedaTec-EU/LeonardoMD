import Foundation

extension GlobalPreferences {
    /// Keep the first (most recent) representation without changing its directory hint.
    /// Match favorites by standardized path, independent of existence or trailing slash.
    static func uniqueRecentPaths(_ urls: [URL]) -> [URL] {
        var identities = Set<URL>()
        return urls.filter { url in
            identities.insert(FavoriteItem(kind: .project, url: url).url).inserted
        }
    }
}
