#if os(macOS)
import Foundation
import XCTest
@testable import LeonardoApp
import LeonardoSync
import LeonardoDesktopSync

final class DesktopGitWakeupInboxTests: XCTestCase {
    func testInboxRoundTripIsBoundedAndPrivate() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("GitWakeups.json")
        let inbox = DesktopGitWakeupInbox(url: url)
        let entry = try makeEntry()

        try await inbox.save([entry])
        let loaded = try await inbox.load()
        XCTAssertEqual(loaded, [entry])
        let permissions = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(permissions?.intValue, 0o600)
    }

    func testFinalSymlinkCannotRedirectInboxWrite() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let outside = root.deletingLastPathComponent()
            .appendingPathComponent("wakeup-outside-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: outside) }
        let sentinel = Data("outside\n".utf8)
        try sentinel.write(to: outside, options: .atomic)
        let url = root.appendingPathComponent("GitWakeups.json")
        try FileManager.default.createSymbolicLink(at: url, withDestinationURL: outside)
        let inbox = DesktopGitWakeupInbox(url: url)
        let entry = try makeEntry()

        do {
            try await inbox.save([entry])
            XCTFail("A symlinked final inbox entry must be rejected")
        } catch let error as SyncError {
            XCTAssertEqual(error, .invalidPath)
        }
        XCTAssertEqual(try Data(contentsOf: outside), sentinel)
    }

    func testPersistenceCoalescesOutOfOrderSnapshotsAndKeepsNewestGeneration() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let inbox = DesktopGitWakeupInbox(url: root.appendingPathComponent("GitWakeups.json"))
        let persistence = DesktopGitWakeupPersistence(inbox: inbox)
        let old = try makeEntry()
        let newer = try makeEntry()

        async let high: Void = persistence.enqueue([newer], generation: 2)
        async let low: Void = persistence.enqueue([old], generation: 1)
        _ = try await high
        _ = try await low

        let loaded = try await inbox.load()
        XCTAssertEqual(loaded, [newer])
    }

    func testWakeupPolicyRequiresCurrentSourceGrantAndDirectProvenance() throws {
        var registry = PairingRegistry()
        registry.setEnabled(true)
        let sourceID = UUID()
        let now = Date(timeIntervalSince1970: 1_000)
        let credential = String(repeating: "a", count: 64)
        let request = try registry.requestPairing(
            deviceName: "Phone", credential: credential, serverFingerprint: Data(repeating: 1, count: 32), now: now)
        let device = try registry.approve(requestID: request.id, comparisonCode: request.comparisonCode,
                                           projects: [sourceID], now: now)
        let scope = try CorpusScope(folder: "docs")
        let descriptor = SharedProjectDescriptor(id: sourceID, name: "Docs", scope: scope)
        let wakeup = try GitReconciliationWakeup(
            gitProjectID: UUID(), sourceProjectID: sourceID, gitDeviceID: UUID(), directDeviceID: device.id,
            proposalCommitID: String(repeating: "b", count: 40), scope: scope)
        let event = DesktopGitReconciliationWakeup(deviceID: device.id, wakeup: wakeup)
        XCTAssertTrue(DesktopSyncController.acceptsGitWakeup(event, device: device, descriptor: descriptor))

        let wrongSource = try GitReconciliationWakeup(
            gitProjectID: wakeup.gitProjectID, sourceProjectID: UUID(), gitDeviceID: wakeup.gitDeviceID,
            directDeviceID: device.id, proposalCommitID: wakeup.proposalCommitID, scope: scope)
        XCTAssertFalse(DesktopSyncController.acceptsGitWakeup(
            DesktopGitReconciliationWakeup(deviceID: device.id, wakeup: wrongSource),
            device: device, descriptor: descriptor))

        let wrongDirectDevice = try GitReconciliationWakeup(
            gitProjectID: wakeup.gitProjectID, sourceProjectID: sourceID, gitDeviceID: wakeup.gitDeviceID,
            directDeviceID: UUID(), proposalCommitID: wakeup.proposalCommitID, scope: scope)
        XCTAssertFalse(DesktopSyncController.acceptsGitWakeup(
            DesktopGitReconciliationWakeup(deviceID: device.id, wakeup: wrongDirectDevice),
            device: device, descriptor: descriptor))
    }

    private func makeEntry() throws -> DesktopGitWakeupInbox.Entry {
        let scope = try CorpusScope(folder: "docs")
        let wakeup = try GitReconciliationWakeup(
            gitProjectID: UUID(), sourceProjectID: UUID(), gitDeviceID: UUID(),
            proposalCommitID: String(repeating: "a", count: 40), scope: scope)
        return DesktopGitWakeupInbox.Entry(deviceID: UUID(), wakeup: wakeup,
                                           receivedAt: Date(timeIntervalSince1970: 1_000))
    }

    private func makeRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("little-leonardo-wakeup-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true,
                                                 attributes: [.posixPermissions: 0o700])
        return root
    }
}
#endif
