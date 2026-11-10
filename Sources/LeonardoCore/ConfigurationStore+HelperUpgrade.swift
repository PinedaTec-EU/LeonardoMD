import Foundation

extension ConfigurationStore {
    /// Manual consent always cancels a pending automatic upgrade, even when the
    /// visible switch was already off on disk during the temporary stop.
    public func setSyncHelperEnabled(_ enabled: Bool, at url: URL) throws {
        try updateHelperPreferences(at: url) {
            $0.helperEnabled = enabled
            $0.helperUpgradeToken = nil
        }
    }

    public func beginSyncHelperUpgrade(_ token: UUID, at url: URL) throws -> Bool {
        try updateHelperPreferences(at: url) {
            guard $0.helperEnabled || $0.helperUpgradeToken != nil else { return false }
            $0.helperEnabled = false
            $0.helperUpgradeToken = token
            return true
        }
    }

    public func finishSyncHelperUpgrade(_ token: UUID, at url: URL) throws -> Bool {
        try updateHelperPreferences(at: url) {
            guard $0.helperUpgradeToken == token, !$0.helperEnabled else { return false }
            $0.helperUpgradeToken = nil
            $0.helperEnabled = true
            return true
        }
    }

    private func updateHelperPreferences<T>(at url: URL,
        _ update: (inout MobileSyncPreferences) throws -> T) throws -> T {
        try ProcessFileLock.transaction(for: url) {
            var preferences = try loadGlobalPreferences(at: url)
            let result = try update(&preferences.mobileSync)
            try saveGlobalPreferences(preferences, at: url)
            return result
        }
    }
}
