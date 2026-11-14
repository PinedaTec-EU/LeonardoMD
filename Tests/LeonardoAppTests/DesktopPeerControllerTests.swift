import XCTest
import LeonardoSync
@testable import LeonardoApp

@MainActor
final class DesktopPeerControllerTests: XCTestCase {
    func testIgnoreDecisionIsRejectedWhileCatalogueAcceptanceIsBusy() {
        XCTAssertFalse(DesktopPeerController.canIgnoreRemoteProject(isAdditional: false, busy: true,
                                                                     projectIsAvailable: true))
        XCTAssertTrue(DesktopPeerController.canIgnoreRemoteProject(isAdditional: false, busy: false,
                                                                    projectIsAvailable: true))
        XCTAssertFalse(DesktopPeerController.canIgnoreRemoteProject(isAdditional: true, busy: false,
                                                                      projectIsAvailable: true))
        XCTAssertFalse(DesktopPeerController.canIgnoreRemoteProject(isAdditional: false, busy: false,
                                                                      projectIsAvailable: false))
    }

    func testIntervalIsInstallationLocalAndRejectsUnsupportedValues() throws {
        let suite = UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let controller = DesktopPeerController(preferencesURL: root.appendingPathComponent("preferences.json"), defaults: defaults)
        defer { controller.stop() }
        XCTAssertEqual(controller.syncIntervalMinutes, 1)
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

    func testConfirmedDeviceRevocationInvalidatesAllItsDownloadsAndKeepsOtherConnection() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let suite = UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let controller = DesktopPeerController(preferencesURL: root.appendingPathComponent("preferences.json"),
                                               defaults: defaults)
        defer { controller.stop() }
        let selection = try CorpusSelection(folders: ["docs"], documents: [])
        let connectionID = UUID()
        let ownedProjectIDs = [UUID(), UUID()]
        let unrelatedConnectionID = UUID()
        let unrelatedProjectID = UUID()

        for (ownerID, projectID) in [(connectionID, ownedProjectIDs[0]),
                                     (connectionID, ownedProjectIDs[1]),
                                     (unrelatedConnectionID, unrelatedProjectID)] {
            let descriptor = SharedProjectDescriptor(id: projectID, name: "Cached \(projectID.uuidString)",
                                                     scope: try CorpusScope(folder: ""), selection: selection)
            let file = CorpusFile(path: "docs/note.md", content: Data(projectID.uuidString.utf8))
            let downloadID = DesktopPeerController.downloadID(connectionID: ownerID, projectID: projectID)
            try await controller.downloads.update(id: downloadID, descriptor: descriptor,
                catalogue: RemoteProjectCatalogue(files: [RemoteFileEntry(file: file)]))
            controller.downloads.fetch = { _, _ in file }
            _ = try await controller.downloads.open(id: downloadID, path: file.path)
        }

        let connection = try DesktopPeerConnection(id: connectionID, remoteDeviceID: UUID(),
            endpoint: URL(string: "https://example.test")!, fingerprint: Data(repeating: 7, count: 32),
            grants: Dictionary(uniqueKeysWithValues: ownedProjectIDs.map { ($0, selection) }))
        await controller.invalidateDeniedDownloads(for: connection, projectID: ownedProjectIDs[0], error: SyncError.revoked)

        for projectID in ownedProjectIDs {
            let downloadID = DesktopPeerController.downloadID(connectionID: connectionID, projectID: projectID)
            do {
                _ = try await controller.downloads.open(id: downloadID, path: "docs/note.md")
                XCTFail("Revoked connection cache \(projectID) must not be readable")
            } catch { XCTAssertEqual(error as? SyncError, .revoked) }
        }
        let unrelatedID = DesktopPeerController.downloadID(connectionID: unrelatedConnectionID,
                                                           projectID: unrelatedProjectID)
        let unrelated = try await controller.downloads.open(id: unrelatedID, path: "docs/note.md")
        XCTAssertEqual(unrelated.content, Data(unrelatedProjectID.uuidString.utf8))
    }
}
