import XCTest
@testable import LeonardoApp

@MainActor
final class DesktopPeerControllerTests: XCTestCase {
    func testIntervalIsInstallationLocalAndRejectsUnsupportedValues() throws {
        let suite = UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let controller = DesktopPeerController(preferencesURL: root.appendingPathComponent("preferences.json"), defaults: defaults)
        defer { controller.stop() }
        XCTAssertEqual(controller.syncIntervalMinutes, 0)
        controller.updateInterval(5)
        XCTAssertEqual(controller.syncIntervalMinutes, 5)
        controller.updateInterval(-1)
        XCTAssertEqual(controller.syncIntervalMinutes, 5)
        let reopened = DesktopPeerController(preferencesURL: root.appendingPathComponent("preferences.json"), defaults: defaults)
        defer { reopened.stop() }
        XCTAssertEqual(reopened.syncIntervalMinutes, 5)
        controller.updateInterval(0)
        XCTAssertEqual(defaults.integer(forKey: "desktopPeerSyncMinutes"), 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
    }

    func testEmptyInitializationCreatesNoCacheOrNetworkIdentity() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let controller = DesktopPeerController(preferencesURL: root.appendingPathComponent("preferences.json"))
        await controller.initialize()
        XCTAssertNil(controller.error)
        XCTAssertTrue(controller.connections.isEmpty)
        XCTAssertTrue(controller.copies.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
        XCTAssertFalse(controller.busy)
        // Invalid addresses fail before networking or secure-storage operations.
        let connected = await controller.enroll(address: "https://example.com/path", name: "Test Mac")
        XCTAssertFalse(connected)
        XCTAssertNotNil(controller.error)
        XCTAssertTrue(controller.connections.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
    }
}
