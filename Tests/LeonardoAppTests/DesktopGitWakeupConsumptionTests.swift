import XCTest
import LeonardoCore
import LeonardoSync
import LeonardoSyncTransport
import LeonardoDesktopSync
@testable import LeonardoApp

@MainActor
final class DesktopGitWakeupConsumptionTests: XCTestCase {
    func testDismissKeepsWakeupVisibleWhenDurableRemovalFails() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("Source", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        let preferences = root.appendingPathComponent("Owner/preferences.json")
        let runtime = DesktopDirectRuntime(root: root.appendingPathComponent("Service"),
                                           credentials: WakeupConsumptionCredentials(), now: { Date() })
        let controller = DesktopSyncController(preferencesURL: preferences,
                                                configurations: ConfigurationStore(), runtime: runtime)
        let project = MobileSharedProject(rootURL: source, name: "Docs", folders: ["docs"])
        await controller.initialize()
        await controller.update(MobileSyncPreferences(enabled: true, host: "127.0.0.1", port: 0,
                                                       projects: [project]))
        let running = try XCTUnwrap(controller.running, controller.error ?? "Service missing")
        do {
            let credential = try PairingRegistry.makeCredential()
            let client = try DirectEnrollmentClient(endpoint: running.endpoint,
                                                     certificateFingerprint: running.certificateFingerprint)
            let enrollment = try await client.begin(deviceName: "Wakeup test peer", credential: credential, now: Date())
            await controller.refreshConsent()
            let request = try XCTUnwrap(controller.consent.requests.first)
            await controller.approve(request, projects: [project.id])

            let wakeup = try GitReconciliationWakeup(
                gitProjectID: UUID(), sourceProjectID: project.id, gitDeviceID: UUID(),
                directDeviceID: enrollment.deviceID, proposalCommitID: String(repeating: "a", count: 40),
                scope: try CorpusScope(folder: "docs"))
            try await client.notifyGitReconciliation(wakeup, deviceID: enrollment.deviceID, credential: credential)
            let notice = try XCTUnwrap(controller.gitWakeups.first)
            let inboxURL = root.appendingPathComponent("Owner/GitWakeups.json")
            let sentinel = root.appendingPathComponent("inbox-sentinel")
            try Data("untouched".utf8).write(to: sentinel, options: .atomic)
            try FileManager.default.removeItem(at: inboxURL)
            try FileManager.default.createSymbolicLink(at: inboxURL, withDestinationURL: sentinel)

            await controller.dismissGitWakeup(notice)

            XCTAssertEqual(controller.gitWakeups, [notice])
            XCTAssertEqual(try Data(contentsOf: sentinel), Data("untouched".utf8))

            // Runtime shutdown must not skip the independent inbox flush if
            // disabling the service fails to persist its registry.
            try FileManager.default.removeItem(at: inboxURL)
            let registryURL = root.appendingPathComponent("Service/devices.json")
            try FileManager.default.removeItem(at: registryURL)
            try FileManager.default.createSymbolicLink(at: registryURL, withDestinationURL: sentinel)
            await controller.stop()
            XCTAssertNotNil(controller.error)
            let restored = try await DesktopGitWakeupInbox(url: inboxURL).load()
            XCTAssertEqual(restored.map(\.wakeup), [wakeup])
            XCTAssertEqual(try Data(contentsOf: sentinel), Data("untouched".utf8))
        } catch {
            await controller.stop()
            throw error
        }
    }
}

private actor WakeupConsumptionCredentials: DeviceCredentialStore {
    private var values: [UUID: String] = [:]

    func credential(deviceID: UUID) -> String? { values[deviceID] }
    func save(_ credential: String, deviceID: UUID) { values[deviceID] = credential }
    func remove(deviceID: UUID) { values.removeValue(forKey: deviceID) }
}
