import Foundation
import XCTest
import LeonardoCore
import LeonardoSync
import LeonardoSyncTransport
import LeonardoDesktopSync
@testable import LeonardoApp

@MainActor
final class SavedItemRecoveryPersistenceTests: XCTestCase {
    func testRelocationRejectsHomeChangesWhenTheSharedPathCannotBePersisted() async throws {
        let fixture = try RecoveryPersistenceFixture()
        defer { fixture.cleanup() }
        let runtime = RecoveryPersistenceRuntime()
        let controller = fixture.controller(runtime: runtime)
        await controller.update(fixture.initialSettings)
        XCTAssertNil(controller.error)

        let oldPermissions = try FileManager.default.attributesOfItem(atPath: fixture.root.path)[.posixPermissions]
        defer { try? FileManager.default.setAttributes([.posixPermissions: oldPermissions as Any], ofItemAtPath: fixture.root.path) }
        try FileManager.default.setAttributes([.posixPermissions: NSNumber(value: 0o500)], ofItemAtPath: fixture.root.path)

        let outcome = await controller.relocateSharedProject(fixture.project, to: fixture.destination)

        XCTAssertEqual(outcome, .notPersisted)
        XCTAssertEqual(controller.settings.projects, [fixture.project])
        let saved = try await ConfigurationStore().loadGlobalPreferences(at: fixture.preferences)
        XCTAssertEqual(saved.mobileSync.projects, [fixture.project])
        XCTAssertNotNil(controller.error)
    }

    func testRelocationKeepsDurablePathWhenRuntimeRestartIsUnavailable() async throws {
        let fixture = try RecoveryPersistenceFixture()
        defer { fixture.cleanup() }
        let runtime = RecoveryPersistenceRuntime()
        let controller = fixture.controller(runtime: runtime)
        await controller.update(fixture.initialSettings)
        XCTAssertNil(controller.error)
        await runtime.failNextStart()

        let outcome = await controller.relocateSharedProject(fixture.project, to: fixture.destination)

        XCTAssertEqual(outcome, .persistedButUnavailable)
        let expected = MobileSharedProject(id: fixture.project.id, rootURL: fixture.destination,
                                           name: fixture.project.name, folders: fixture.project.folders,
                                           documents: fixture.project.documents)
        XCTAssertEqual(controller.settings.projects, [expected])
        let saved = try await ConfigurationStore().loadGlobalPreferences(at: fixture.preferences)
        XCTAssertEqual(saved.mobileSync.projects, [expected])
        XCTAssertNotNil(controller.error)
    }
}

private final class RecoveryPersistenceFixture {
    let root: URL
    let preferences: URL
    let projectRoot: URL
    let destination: URL
    let project: MobileSharedProject
    let initialSettings: MobileSyncPreferences

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        preferences = root.appendingPathComponent("preferences.json")
        projectRoot = root.appendingPathComponent("OldProject", isDirectory: true)
        destination = root.appendingPathComponent("NewProject", isDirectory: true)
        project = MobileSharedProject(rootURL: projectRoot, name: "OldProject")
        initialSettings = MobileSyncPreferences(enabled: true, host: "127.0.0.1", port: 40882,
                                                 projects: [project])
        try FileManager.default.createDirectory(at: projectRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
    }

    @MainActor
    func controller(runtime: RecoveryPersistenceRuntime) -> DesktopSyncController {
        DesktopSyncController(preferencesURL: preferences, configurations: ConfigurationStore(),
                               runtime: runtime, usesHelper: false)
    }

    func cleanup() {
        try? FileManager.default.setAttributes([.posixPermissions: NSNumber(value: 0o700)], ofItemAtPath: root.path)
        try? FileManager.default.removeItem(at: root)
    }
}

private enum RecoveryPersistenceError: Error {
    case unavailable
}

private actor RecoveryPersistenceRuntime: DesktopSyncRuntimeAccess {
    private var failNextStartRequest = false
    private var failNextStopRequest = false
    private var failNextConsentRequest = false

    func failNextStart() { failNextStartRequest = true }

    func start(host: String, port: UInt16, projects: [SharedProjectSource],
               allowPrivateOverlay: Bool) async throws -> RunningDirectService {
        guard !failNextStartRequest else {
            failNextStartRequest = false
            throw RecoveryPersistenceError.unavailable
        }
        return RunningDirectService(endpoint: URL(string: "https://127.0.0.1:40882")!,
                                    certificateFingerprint: Data(repeating: 7, count: 32))
    }

    func stop() async throws {
        guard !failNextStopRequest else {
            failNextStopRequest = false
            throw RecoveryPersistenceError.unavailable
        }
    }

    func consentState() async throws -> PairingRegistry {
        guard !failNextConsentRequest else {
            failNextConsentRequest = false
            throw RecoveryPersistenceError.unavailable
        }
        return PairingRegistry()
    }

    func incomingProposals() async throws -> [DesktopPeerIncomingProposal] { [] }

    func reviewIncomingProposal(deviceID: UUID, upload: DesktopPeerUpload) async throws -> DesktopPeerProposalReview {
        throw RecoveryPersistenceError.unavailable
    }

    func applyIncomingProposal(deviceID: UUID, upload: DesktopPeerUpload, review: DesktopPeerProposalReview,
                               decisions: [String: ReconciliationChoice], projectRoot: URL,
                               currentSource: CorpusSnapshot, currentDisk: CorpusSnapshot) async throws -> DesktopPeerAcceptanceResult {
        throw RecoveryPersistenceError.unavailable
    }

    func createInvitation() async throws -> PairingInvitation { throw RecoveryPersistenceError.unavailable }
    func approve(requestID: UUID, code: String, projectIDs: Set<UUID>) async throws { throw RecoveryPersistenceError.unavailable }
    func reject(requestID: UUID) async throws { throw RecoveryPersistenceError.unavailable }
    func revoke(deviceID: UUID) async throws { throw RecoveryPersistenceError.unavailable }
    func createRubricRequest(deviceID: UUID, requestID: UUID, requesterName: String,
                             labelHint: String?) async throws -> LeonardoSync.RubricRequest {
        throw RecoveryPersistenceError.unavailable
    }
    func cancelRubricRequest(requestID: UUID) async throws -> LeonardoSync.RubricRequest {
        throw RecoveryPersistenceError.unavailable
    }
    func rubricResponse(requestID: UUID) async throws -> LeonardoSync.RubricResponse? {
        throw RecoveryPersistenceError.unavailable
    }
    func rubricStatus(requestID: UUID) async throws -> RubricExchangeStatus { throw RecoveryPersistenceError.unavailable }
}
