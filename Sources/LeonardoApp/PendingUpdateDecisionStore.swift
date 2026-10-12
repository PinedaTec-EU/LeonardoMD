import Foundation

/// A durable channel-change guard, independent of Sparkle's check preferences.
/// Sparkle may resume an installer after a process exits without fetching a feed.
@MainActor
final class PendingUpdateDecisionStore {
    static let preferenceKey = "pendingUpdateTargetBuild"
    private let defaults: UserDefaults
    var targetBuild: String? { defaults.string(forKey: Self.preferenceKey) }

    var hasPendingDecision: Bool { targetBuild != nil }

    init(defaults: UserDefaults, installedBuild: String?) {
        self.defaults = defaults
        if let targetBuild, let target = Int(targetBuild),
           let installedBuild, let installed = Int(installedBuild), target > 0, installed > 0, target <= installed {
            clear() // The actual installed bundle has completed or superseded this update.
        }
    }

    func retain(targetBuild: String) {
        defaults.set(targetBuild, forKey: Self.preferenceKey)
    }

    func clear() {
        defaults.removeObject(forKey: Self.preferenceKey)
    }
}
