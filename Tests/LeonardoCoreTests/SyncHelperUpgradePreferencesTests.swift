import Foundation
import XCTest
import LeonardoCore

@MainActor
final class SyncHelperUpgradePreferencesTests: XCTestCase {
    func testIndependentStoreDisableCancelsAnOlderUpgradeCompletion() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("preferences.json")
        let upgrader = ConfigurationStore(), owner = ConfigurationStore()
        var initial = GlobalPreferences.default
        initial.mobileSync.helperEnabled = true
        initial.mobileSync.enabled = true
        initial.mobileSync.port = 45678
        try await upgrader.saveGlobalPreferences(initial, at: url)
        let token = UUID()
        let begun = try await upgrader.beginSyncHelperUpgrade(token, at: url)
        XCTAssertTrue(begun)
        try await owner.setSyncHelperEnabled(false, at: url)
        let restored = try await upgrader.finishSyncHelperUpgrade(token, at: url)
        XCTAssertFalse(restored)
        let persisted = try await owner.loadGlobalPreferences(at: url)
        XCTAssertFalse(persisted.mobileSync.helperEnabled)
        XCTAssertNil(persisted.mobileSync.helperUpgradeToken)
        XCTAssertTrue(persisted.mobileSync.enabled)
        XCTAssertEqual(persisted.mobileSync.port, 45678)
    }

    func testRestartedUpgradeCannotBeCompletedByTheObsoleteToken() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("preferences.json")
        let previous = ConfigurationStore(), restarted = ConfigurationStore()
        try await previous.setSyncHelperEnabled(true, at: url)
        let oldToken = UUID(), currentToken = UUID()
        _ = try await previous.beginSyncHelperUpgrade(oldToken, at: url)
        _ = try await restarted.beginSyncHelperUpgrade(currentToken, at: url)
        let staleCompletion = try await previous.finishSyncHelperUpgrade(oldToken, at: url)
        XCTAssertFalse(staleCompletion)
        let pending = try await restarted.loadGlobalPreferences(at: url)
        XCTAssertFalse(pending.mobileSync.helperEnabled)
        XCTAssertEqual(pending.mobileSync.helperUpgradeToken, currentToken)
        let currentCompletion = try await restarted.finishSyncHelperUpgrade(currentToken, at: url)
        XCTAssertTrue(currentCompletion)
        let completed = try await previous.loadGlobalPreferences(at: url)
        XCTAssertTrue(completed.mobileSync.helperEnabled)
        XCTAssertNil(completed.mobileSync.helperUpgradeToken)
    }

    func testLegacyPreferencesNeverInventAnUpgradeConsentToken() throws {
        for enabled in [true, false] {
            let json = "{\"helperEnabled\":\(enabled)}"
            let decoded = try JSONDecoder().decode(MobileSyncPreferences.self, from: Data(json.utf8))
            XCTAssertEqual(decoded.helperEnabled, enabled)
            XCTAssertNil(decoded.helperUpgradeToken)
        }
    }
}
