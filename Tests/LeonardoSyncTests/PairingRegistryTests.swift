import XCTest
@testable import LeonardoSync

final class PairingRegistryTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_000)
    private let credential = String(repeating: "a", count: 64)

    func testDefaultDisabledAndApprovalIsRequired() throws {
        var registry = PairingRegistry()
        XCTAssertThrowsError(try registry.createInvitation(now: now))
        registry.setEnabled(true)
        let request = try registry.requestPairing(deviceName: "Phone", credential: credential, serverFingerprint: Data(repeating: 1, count: 32), now: now)
        XCTAssertThrowsError(try registry.access(deviceID: request.id, credential: credential))
        XCTAssertThrowsError(try registry.approve(requestID: request.id, comparisonCode: "wrong", projects: [UUID()], now: now))
        let projectID = UUID()
        let device = try registry.approve(requestID: request.id, comparisonCode: request.comparisonCode, projects: [projectID], now: now)
        XCTAssertEqual(try registry.access(deviceID: device.id, credential: credential, projectID: projectID), .authorized)
        XCTAssertThrowsError(try registry.access(deviceID: device.id, credential: credential, projectID: UUID()))
        XCTAssertThrowsError(try registry.access(deviceID: device.id, credential: String(repeating: "b", count: 64)))
    }

    func testQRIsSingleUseAndReplacementInvalidatesOldQR() throws {
        var registry = PairingRegistry(); registry.setEnabled(true)
        let old = try registry.createInvitation(now: now)
        let current = try registry.createInvitation(now: now)
        XCTAssertThrowsError(try registry.requestPairing(deviceName: "Phone", credential: credential, invitation: old, serverFingerprint: Data(repeating: 1, count: 32), now: now))
        _ = try registry.requestPairing(deviceName: "Phone", credential: credential, invitation: current, serverFingerprint: Data(repeating: 1, count: 32), now: now)
        XCTAssertThrowsError(try registry.requestPairing(deviceName: "Other", credential: String(repeating: "b", count: 64), invitation: current, serverFingerprint: Data(repeating: 1, count: 32), now: now))
    }

    func testRevocationSurvivesPersistenceAndDisablePreservesDevices() throws {
        var registry = PairingRegistry(); registry.setEnabled(true)
        let request = try registry.requestPairing(deviceName: "Phone", credential: credential, serverFingerprint: Data(repeating: 1, count: 32), now: now)
        _ = try registry.approve(requestID: request.id, comparisonCode: request.comparisonCode, projects: [UUID()], now: now)
        try registry.revoke(deviceID: request.id)
        registry = try JSONDecoder().decode(PairingRegistry.self, from: JSONEncoder().encode(registry))
        XCTAssertEqual(try registry.access(deviceID: request.id, credential: credential), .revoked)
        registry.setEnabled(false)
        XCTAssertThrowsError(try registry.access(deviceID: request.id, credential: credential))
        XCTAssertEqual(registry.devices.count, 1)
        registry.setEnabled(true)
        XCTAssertEqual(try registry.access(deviceID: request.id, credential: credential), .revoked)
    }

    func testExpiredRequestCannotBeApprovedAndSecretsAreNotPersisted() throws {
        var registry = PairingRegistry(); registry.setEnabled(true)
        let invitation = try registry.createInvitation(now: now)
        let request = try registry.requestPairing(deviceName: "Phone", credential: credential, invitation: invitation, serverFingerprint: Data(repeating: 1, count: 32), now: now)
        XCTAssertThrowsError(try registry.approve(requestID: request.id, comparisonCode: request.comparisonCode, projects: [UUID()], now: now.addingTimeInterval(301)))
        let text = String(decoding: try JSONEncoder().encode(registry), as: UTF8.self)
        XCTAssertFalse(text.contains(credential))
        XCTAssertFalse(text.contains(invitation.secret))
        XCTAssertEqual(try PairingRegistry.makeCredential().count, 64)
    }
}

final class PairingRegistryStoreTests: XCTestCase {
    func testPersistenceRetainsRevocationAndRejectsSymlinkDestination() async throws {
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appendingPathComponent("devices.json")
        let store = PairingRegistryStore(url: url)
        let empty = try await store.load()
        XCTAssertFalse(empty.enabled)
        var registry = PairingRegistry(); registry.setEnabled(true)
        let credential = try PairingRegistry.makeCredential()
        let now = Date(timeIntervalSince1970: 1_000)
        let request = try registry.requestPairing(deviceName: "Phone", credential: credential, serverFingerprint: Data(repeating: 1, count: 32), now: now)
        _ = try registry.approve(requestID: request.id, comparisonCode: request.comparisonCode, projects: [UUID()], now: now)
        try registry.revoke(deviceID: request.id)
        try await store.save(registry)
        let reopened = try await PairingRegistryStore(url: url).load()
        XCTAssertEqual(try reopened.access(deviceID: request.id, credential: credential), .revoked)
        let content = try String(contentsOf: url, encoding: .utf8)
        XCTAssertFalse(content.contains(credential))
        let link = root.appendingPathComponent("link.json")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: url)
        do { _ = try await PairingRegistryStore(url: link).load(); XCTFail("Symlink must be rejected") }
        catch { XCTAssertEqual(error as? SyncError, .invalidPath) }
    }
}
