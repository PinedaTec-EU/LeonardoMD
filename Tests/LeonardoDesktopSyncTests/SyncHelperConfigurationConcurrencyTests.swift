import XCTest
import LeonardoCore
@testable import LeonardoDesktopSync

final class SyncHelperConfigurationConcurrencyTests: XCTestCase {
    func testOverlappingHealthCommandsWaitAndReadLatestConsent() async throws {
        let preferences = SuspendedHelperPreferences()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let host = SyncHelperHost(preferencesURL: root.appendingPathComponent("preferences.json"), configurations: preferences)
        let first = Task { try await host.perform(.status) }
        await preferences.waitForRead()
        let secondFinished = expectation(description: "Queued status does not fail busy")
        secondFinished.isInverted = true
        let second = Task {
            defer { secondFinished.fulfill() }
            return try await host.perform(.status)
        }
        await fulfillment(of: [secondFinished], timeout: 0.1)
        await preferences.resumeDisabled()
        let firstStatus = try JSONDecoder().decode(SyncHelperStatus.self, from: await first.value)
        let secondStatus = try JSONDecoder().decode(SyncHelperStatus.self, from: await second.value)
        XCTAssertTrue(firstStatus.enabled)
        XCTAssertFalse(secondStatus.enabled, "Queued commands must re-read denial, not reuse the previous reload")
        let count = await preferences.readCount
        XCTAssertEqual(count, 2)
    }
}

private actor SuspendedHelperPreferences: SyncHelperPreferencesAccess {
    private(set) var readCount = 0
    private var held: CheckedContinuation<Void, Never>?
    private var observer: CheckedContinuation<Void, Never>?
    private var disabled = false
    func loadGlobalPreferences(at fileURL: URL) async throws -> GlobalPreferences {
        readCount += 1
        var settings = GlobalPreferences()
        settings.mobileSync.helperEnabled = !disabled
        if readCount == 1 {
            await withCheckedContinuation { continuation in
                held = continuation; observer?.resume(); observer = nil
            }
        }
        return settings
    }
    func waitForRead() async {
        if held == nil { await withCheckedContinuation { observer = $0 } }
    }
    func resumeDisabled() { disabled = true; held?.resume(); held = nil }
}
