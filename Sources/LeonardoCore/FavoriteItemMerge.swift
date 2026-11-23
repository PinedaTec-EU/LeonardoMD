import Foundation

extension FavoriteItem {
    /// Merge membership by identity and appearance only when this writer changed it.
    static func merging(current: [FavoriteItem], updated: [FavoriteItem], baseline: [FavoriteItem]) -> [FavoriteItem] {
        let removed = baseline.filter { old in !updated.contains { $0.matches(old) } }
        var merged = current.filter { item in !removed.contains { $0.matches(item) } }
        for item in updated {
            let previous = baseline.first { $0.matches(item) }
            if previous == nil {
                if !merged.contains(where: { $0.matches(item) }) { merged.append(item) }
            } else if previous?.palette != item.palette,
                      let index = merged.firstIndex(where: { $0.matches(item) }) {
                // A stale metadata write must not resurrect a removed favorite.
                merged[index].palette = item.palette
            }
        }
        return merged
    }
}
