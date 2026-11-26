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
        let otherInstance = InstancePathOwnership()
        XCTAssertThrowsError(try otherInstance.claim(fixture.destination))
    }

    func testRelocationPersistsSyncAndHomeChangesInOneGlobalSnapshot() async throws {
        let fixture = try RecoveryPersistenceFixture()
        defer { fixture.cleanup() }
        let runtime = RecoveryPersistenceRuntime()
        let controller = fixture.controller(runtime: runtime)
        await controller.update(fixture.initialSettings)
        XCTAssertNil(controller.error)

        let store = ConfigurationStore()
        let baseline = try await store.loadGlobalPreferences(at: fixture.preferences)
        var requested = baseline
        requested.favorites = [FavoriteItem(kind: .project, url: fixture.destination)]
        requested.recentProjectPaths = [fixture.destination]

        let result = await controller.relocateSharedProjectResult(
            fixture.project, to: fixture.destination,
            updatingGlobalPreferences: requested, baseline: baseline
        )

        XCTAssertEqual(result.outcome, .persisted)
        XCTAssertEqual(result.persistedGlobalPreferences?.favorites,
                       [FavoriteItem(kind: .project, url: fixture.destination)])
        XCTAssertEqual(result.persistedGlobalPreferences?.recentProjectPaths, [fixture.destination])
        XCTAssertEqual(result.persistedGlobalPreferences?.mobileSync.projects.first?.rootURL,
                       fixture.destination)
        let saved = try await store.loadGlobalPreferences(at: fixture.preferences)
        XCTAssertEqual(saved.favorites, requested.favorites)
        XCTAssertEqual(saved.recentProjectPaths, requested.recentProjectPaths)
        XCTAssertEqual(saved.mobileSync.projects.first?.rootURL, fixture.destination)
    }

    func testRelocationRejectsACompetingDurableProjectMove() async throws {
        let fixture = try RecoveryPersistenceFixture()
        defer { fixture.cleanup() }
        let runtime = RecoveryPersistenceRuntime()
        let controller = fixture.controller(runtime: runtime)
        await controller.update(fixture.initialSettings)
        let store = ConfigurationStore()
        let baseline = try await store.loadGlobalPreferences(at: fixture.preferences)
        var competing = baseline
        competing.mobileSync.projects = [MobileSharedProject(
            id: fixture.project.id,
            rootURL: fixture.root.appendingPathComponent("CompetingProject", isDirectory: true),
            name: fixture.project.name,
            folders: fixture.project.folders,
            documents: fixture.project.documents
        )]
        _ = try await store.mergeGlobalPreferences(
            updated: competing, baseline: baseline, at: fixture.preferences
        )

        let outcome = await controller.relocateSharedProject(fixture.project, to: fixture.destination)

        XCTAssertEqual(outcome, .notPersisted)
        let saved = try await store.loadGlobalPreferences(at: fixture.preferences)
        XCTAssertEqual(saved.mobileSync.projects.first?.rootURL, competing.mobileSync.projects.first?.rootURL)
        XCTAssertEqual(controller.settings.projects, [fixture.project])
        let otherInstance = InstancePathOwnership()
        XCTAssertNoThrow(try otherInstance.claim(fixture.destination))
        XCTAssertThrowsError(try otherInstance.claim(fixture.projectRoot))
    }

    func testSharedRecoveryPreservesHomeChangeMadeWhileConfirmationIsOpen() async throws {
        let fixture = try SavedItemRecoveryFixture(kind: .project, shared: true)
        defer { fixture.cleanup() }
        try await fixture.savePreferences()

        let previous = InstanceRuntime.isAdditional
        InstanceRuntime.isAdditional = false
        defer { InstanceRuntime.isAdditional = previous }
        let session = AppSession(preferencesURL: fixture.preferences)
        defer { session.stop() }
        var authorizationCount = 0
        session.authorizeSavedItemPath = { _, _ in authorizationCount += 1 }
        let independent = FavoriteItem(kind: .project,
                                       url: fixture.root.appendingPathComponent("IndependentProject"))
        session.confirmSavedProjectRelocation = { _ in
            session.globalPreferences.favorites.append(independent)
            return true
        }
        let controller = DesktopSyncController(preferencesURL: fixture.preferences,
                                                configurations: ConfigurationStore(), usesHelper: false)

        await session.repairSavedItem(fixture.item, at: fixture.destination, sharing: controller)

        XCTAssertEqual(authorizationCount, 2, "Recovery must re-authorize after consent.")
        XCTAssertNil(session.errorMessage)
        let saved = try await ConfigurationStore().loadGlobalPreferences(at: fixture.preferences)
        XCTAssertTrue(saved.favorites.contains(where: { $0.matches(independent) }))
        XCTAssertTrue(saved.favorites.contains(where: {
            $0.matches(FavoriteItem(kind: .project, url: fixture.destination))
        }))
        XCTAssertEqual(saved.recentProjectPaths, [fixture.destination])
        XCTAssertEqual(saved.mobileSync.projects.first?.rootURL, fixture.destination)
    }

    func testSharedRecoveryCancelsWhenTheSavedItemChangesAfterConfirmation() async throws {
        let fixture = try SavedItemRecoveryFixture(kind: .project, shared: true)
        defer { fixture.cleanup() }
        try await fixture.savePreferences()

        let previous = InstanceRuntime.isAdditional
        InstanceRuntime.isAdditional = false
        defer { InstanceRuntime.isAdditional = previous }
        let session = AppSession(preferencesURL: fixture.preferences)
        defer { session.stop() }
        var authorizationCount = 0
        session.authorizeSavedItemPath = { _, _ in authorizationCount += 1 }
        session.confirmSavedProjectRelocation = { _ in
            session.globalPreferences.favorites.removeAll()
            session.globalPreferences.recentProjectPaths.removeAll()
            return true
        }
        let controller = DesktopSyncController(preferencesURL: fixture.preferences,
                                                configurations: ConfigurationStore(), usesHelper: false)

        await session.repairSavedItem(fixture.item, at: fixture.destination, sharing: controller)

        XCTAssertEqual(authorizationCount, 2)
        XCTAssertNil(session.errorMessage)
        let saved = try await ConfigurationStore().loadGlobalPreferences(at: fixture.preferences)
        XCTAssertEqual(saved.favorites, [fixture.item])
        XCTAssertEqual(saved.recentProjectPaths, [fixture.source])
        XCTAssertEqual(saved.mobileSync.projects.first?.rootURL, fixture.source)
    }

    func testSharedRecoveryCancelsWhenTheSessionStopsAfterConfirmation() async throws {
        let fixture = try SavedItemRecoveryFixture(kind: .project, shared: true)
        defer { fixture.cleanup() }
        try await fixture.savePreferences()

        let previous = InstanceRuntime.isAdditional
        InstanceRuntime.isAdditional = false
        defer { InstanceRuntime.isAdditional = previous }
        let session = AppSession(preferencesURL: fixture.preferences)
        defer { session.stop() }
        var authorizationCount = 0
        session.authorizeSavedItemPath = { _, _ in authorizationCount += 1 }
        session.confirmSavedProjectRelocation = { _ in
            session.stop()
            return true
        }
        let controller = DesktopSyncController(preferencesURL: fixture.preferences,
                                                configurations: ConfigurationStore(), usesHelper: false)

        await session.repairSavedItem(fixture.item, at: fixture.destination, sharing: controller)

        XCTAssertEqual(authorizationCount, 1)
        let saved = try await ConfigurationStore().loadGlobalPreferences(at: fixture.preferences)
        XCTAssertEqual(saved.favorites, [fixture.item])
        XCTAssertEqual(saved.recentProjectPaths, [fixture.source])
        XCTAssertEqual(saved.mobileSync.projects.first?.rootURL, fixture.source)
    }

    func testSharedRecoveryPreservesHomeChangeDuringRuntimeAwait() async throws {
        let fixture = try SavedItemRecoveryFixture(kind: .project, shared: true)
        defer { fixture.cleanup() }
        try await fixture.savePreferences()

        let previous = InstanceRuntime.isAdditional
        InstanceRuntime.isAdditional = false
        defer { InstanceRuntime.isAdditional = previous }
        let gate = RecoveryPersistenceGate()
        let runtime = RecoveryPersistenceRuntime(startGate: gate)
        let controller = DesktopSyncController(preferencesURL: fixture.preferences,
                                                configurations: ConfigurationStore(), runtime: runtime,
                                                usesHelper: false)
        await controller.update(MobileSyncPreferences(
            enabled: true, host: "127.0.0.1", port: 40882,
            projects: [fixture.sharedProject!]
        ))
        await gate.arm()

        let session = AppSession(preferencesURL: fixture.preferences)
        defer { session.stop() }
        session.authorizeSavedItemPath = { _, _ in }
        session.confirmSavedProjectRelocation = { _ in true }
        let independent = FavoriteItem(kind: .project,
                                       url: fixture.root.appendingPathComponent("RuntimeProject"))
        let repair = Task {
            await session.repairSavedItem(fixture.item, at: fixture.destination, sharing: controller)
        }
        await gate.waitUntilEntered()
        session.globalPreferences.favorites.append(independent)
        await gate.release()
        await repair.value

        XCTAssertNil(session.errorMessage)
        XCTAssertTrue(session.globalPreferences.favorites.contains(where: { $0.matches(independent) }))
        XCTAssertTrue(session.globalPreferences.favorites.contains(where: {
            $0.matches(FavoriteItem(kind: .project, url: fixture.destination))
        }))
        XCTAssertEqual(session.globalPreferences.recentProjectPaths, [fixture.destination])
        XCTAssertEqual(session.globalBaseline.mobileSync.projects.first?.rootURL, fixture.destination)
    }

    func testAdditionalInstanceRepairsUnsharedProjectUsingPersistedSharingAuthority() async throws {
        let fixture = try SavedItemRecoveryFixture(kind: .project)
        defer { fixture.cleanup() }
        try await fixture.savePreferences()

        let previous = InstanceRuntime.isAdditional
        InstanceRuntime.isAdditional = true
        defer { InstanceRuntime.isAdditional = previous }
        let session = AppSession(preferencesURL: fixture.preferences)
        defer { session.stop() }
        session.authorizeSavedItemPath = { _, _ in }
        let controller = DesktopSyncController(preferencesURL: fixture.preferences,
                                                configurations: ConfigurationStore(), usesHelper: false)

        await session.repairSavedItem(fixture.item, at: fixture.destination, sharing: controller)
        await session.settingsTask?.value

        XCTAssertNil(session.errorMessage)
        let saved = try await ConfigurationStore().loadGlobalPreferences(at: fixture.preferences)
        XCTAssertEqual(saved.favorites, [FavoriteItem(kind: .project, url: fixture.destination)])
        XCTAssertEqual(saved.recentProjectPaths, [fixture.destination])
        XCTAssertTrue(saved.mobileSync.projects.isEmpty)
    }

    func testAdditionalInstanceRefusesSharedProjectRepairWithoutMutatingIdentity() async throws {
        let fixture = try SavedItemRecoveryFixture(kind: .project, shared: true)
        defer { fixture.cleanup() }
        try await fixture.savePreferences()

        let previous = InstanceRuntime.isAdditional
        InstanceRuntime.isAdditional = true
        defer { InstanceRuntime.isAdditional = previous }
        let session = AppSession(preferencesURL: fixture.preferences)
        defer { session.stop() }
        session.authorizeSavedItemPath = { _, _ in }
        let controller = DesktopSyncController(preferencesURL: fixture.preferences,
                                                configurations: ConfigurationStore(), usesHelper: false)

        await session.repairSavedItem(fixture.item, at: fixture.destination, sharing: controller)
        await session.settingsTask?.value

        XCTAssertEqual(session.errorMessage,
                       L10n.text("Open the primary LeonardoMD instance to relocate a shared project."))
        let saved = try await ConfigurationStore().loadGlobalPreferences(at: fixture.preferences)
        XCTAssertEqual(saved.favorites, [fixture.item])
        XCTAssertEqual(saved.recentProjectPaths, [fixture.source])
        XCTAssertEqual(saved.mobileSync.projects, [fixture.sharedProject!])
        XCTAssertEqual(saved.mobileSync.projects.first?.id, fixture.sharedProject?.id)
        XCTAssertEqual(saved.mobileSync.projects.first?.rootURL, fixture.source)
    }

    func testReplacementRejectsSymlinkProjectBeforePersistingHomeChanges() async throws {
        let fixture = try SavedItemRecoveryFixture(kind: .project)
        defer { fixture.cleanup() }
        try FileManager.default.removeItem(at: fixture.destination)
        try FileManager.default.createDirectory(at: fixture.realDestination, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: fixture.destination, withDestinationURL: fixture.realDestination)
        try await fixture.savePreferences()

        let previous = InstanceRuntime.isAdditional
        InstanceRuntime.isAdditional = true
        defer { InstanceRuntime.isAdditional = previous }
        let session = AppSession(preferencesURL: fixture.preferences)
        defer { session.stop() }
        session.authorizeSavedItemPath = { _, _ in }

        await session.repairSavedItem(fixture.item, at: fixture.destination)
        await session.settingsTask?.value

        XCTAssertEqual(session.errorMessage, L10n.text("The selected project cannot be opened."))
        let saved = try await ConfigurationStore().loadGlobalPreferences(at: fixture.preferences)
        XCTAssertEqual(saved.favorites, [fixture.item])
        XCTAssertEqual(saved.recentProjectPaths, [fixture.source])
    }

    func testReplacementRejectsCorruptPackageBeforePersistingHomeChanges() async throws {
        let fixture = try SavedItemRecoveryFixture(kind: .document)
        defer { fixture.cleanup() }
        try Data("not a Leonardo archive".utf8).write(to: fixture.destination)
        try await fixture.savePreferences()

        let previous = InstanceRuntime.isAdditional
        InstanceRuntime.isAdditional = true
        defer { InstanceRuntime.isAdditional = previous }
        let session = AppSession(preferencesURL: fixture.preferences)
        defer { session.stop() }
        session.authorizeSavedItemPath = { _, _ in }

        await session.repairSavedItem(fixture.item, at: fixture.destination)
        await session.settingsTask?.value

        XCTAssertEqual(session.errorMessage, L10n.text("The selected Leonardo package cannot be opened."))
        let saved = try await ConfigurationStore().loadGlobalPreferences(at: fixture.preferences)
        XCTAssertEqual(saved.favorites, [fixture.item])
    }

    func testRejectedDocumentRecoveryDoesNotReserveTheReplacementPath() async throws {
        let fixture = try SavedItemRecoveryFixture(kind: .document)
        defer { fixture.cleanup() }
        try Data("not a Leonardo archive".utf8).write(to: fixture.destination)
        try await fixture.savePreferences()

        let previous = InstanceRuntime.isAdditional
        InstanceRuntime.isAdditional = true
        defer { InstanceRuntime.isAdditional = previous }
        let session = AppSession(preferencesURL: fixture.preferences)
        defer { session.stop() }

        await session.repairSavedItem(fixture.item, at: fixture.destination)

        let otherInstance = InstancePathOwnership()
        XCTAssertNoThrow(try otherInstance.claim(fixture.destination))
    }

    func testRecoveryRestoresHomeSnapshotWhenPersistenceFails() async throws {
        let fixture = try SavedItemRecoveryFixture(kind: .project)
        defer { fixture.cleanup() }
        try await fixture.savePreferences()

        let oldPermissions = try FileManager.default.attributesOfItem(atPath: fixture.root.path)[.posixPermissions]
        defer { try? FileManager.default.setAttributes([.posixPermissions: oldPermissions as Any], ofItemAtPath: fixture.root.path) }
        try FileManager.default.setAttributes([.posixPermissions: NSNumber(value: 0o500)], ofItemAtPath: fixture.root.path)

        let previous = InstanceRuntime.isAdditional
        InstanceRuntime.isAdditional = true
        defer { InstanceRuntime.isAdditional = previous }
        let session = AppSession(preferencesURL: fixture.preferences)
        defer { session.stop() }
        session.authorizeSavedItemPath = { _, _ in }

        await session.repairSavedItem(fixture.item, at: fixture.destination,
                                      sharing: DesktopSyncController(preferencesURL: fixture.preferences,
                                                                     configurations: ConfigurationStore(), usesHelper: false))
        await session.settingsTask?.value

        let saved = try await ConfigurationStore().loadGlobalPreferences(at: fixture.preferences)
        XCTAssertEqual(saved.favorites, [fixture.item])
        XCTAssertEqual(saved.recentProjectPaths, [fixture.source])
        XCTAssertEqual(session.globalPreferences.favorites, [fixture.item])
        XCTAssertEqual(session.globalPreferences.recentProjectPaths, [fixture.source])
    }

    func testFailedRecoveryDoesNotRollbackAConcurrentHomeMutation() async throws {
        let fixture = try SavedItemRecoveryFixture(kind: .project)
        defer { fixture.cleanup() }
        try await fixture.savePreferences()

        let previous = InstanceRuntime.isAdditional
        InstanceRuntime.isAdditional = true
        defer { InstanceRuntime.isAdditional = previous }
        let session = AppSession(preferencesURL: fixture.preferences)
        defer { session.stop() }
        session.authorizeSavedItemPath = { _, _ in }
        let gate = RecoveryPersistenceGate()
        await gate.arm()
        session.beforeSavedItemPersistence = {
            await gate.waitIfArmed()
        }
        let independent = FavoriteItem(kind: .project,
                                       url: fixture.root.appendingPathComponent("ConcurrentProject"))
        let controller = DesktopSyncController(preferencesURL: fixture.preferences,
                                                configurations: ConfigurationStore(), usesHelper: false)
        let repair = Task {
            await session.repairSavedItem(fixture.item, at: fixture.destination, sharing: controller)
        }
        await gate.waitUntilEntered()
        session.globalPreferences.favorites.append(independent)
        try FileManager.default.removeItem(at: fixture.preferences)
        try FileManager.default.createDirectory(at: fixture.preferences, withIntermediateDirectories: true)
        await gate.release()
        await repair.value

        XCTAssertTrue(session.globalPreferences.favorites.contains(where: { $0.matches(independent) }))
        XCTAssertTrue(session.globalPreferences.favorites.contains(where: {
            $0.matches(fixture.item)
        }))
        XCTAssertFalse(session.globalPreferences.favorites.contains(where: {
            $0.matches(FavoriteItem(kind: .project, url: fixture.destination))
        }))
        XCTAssertNotNil(session.errorMessage)
    }

    func testHomeRecoveryRejectsACompetingSourceRemovalAtCommit() async throws {
        let fixture = try SavedItemRecoveryFixture(kind: .project)
        defer { fixture.cleanup() }
        try await fixture.savePreferences()

        let previous = InstanceRuntime.isAdditional
        InstanceRuntime.isAdditional = true
        defer { InstanceRuntime.isAdditional = previous }
        let session = AppSession(preferencesURL: fixture.preferences)
        defer { session.stop() }
        session.authorizeSavedItemPath = { _, _ in }
        let store = ConfigurationStore()
        session.beforeSavedItemPersistence = {
            guard var current = try? await store.loadGlobalPreferences(at: fixture.preferences) else { return }
            current.favorites.removeAll { $0.matches(fixture.item) }
            current.recentProjectPaths.removeAll { $0 == fixture.source }
            try? await store.saveGlobalPreferences(current, at: fixture.preferences)
        }
        let controller = DesktopSyncController(preferencesURL: fixture.preferences,
                                                configurations: ConfigurationStore(), usesHelper: false)

        await session.repairSavedItem(fixture.item, at: fixture.destination, sharing: controller)

        let saved = try await store.loadGlobalPreferences(at: fixture.preferences)
        XCTAssertTrue(saved.favorites.isEmpty)
        XCTAssertTrue(saved.recentProjectPaths.isEmpty)
        XCTAssertTrue(session.globalPreferences.favorites.contains(where: { $0.matches(fixture.item) }))
        XCTAssertNotNil(session.errorMessage)
    }

    func testHomeProjectRecoveryRejectsAConcurrentDurableShare() async throws {
        let fixture = try SavedItemRecoveryFixture(kind: .project)
        defer { fixture.cleanup() }
        try await fixture.savePreferences()

        let previous = InstanceRuntime.isAdditional
        InstanceRuntime.isAdditional = true
        defer { InstanceRuntime.isAdditional = previous }
        let session = AppSession(preferencesURL: fixture.preferences)
        defer { session.stop() }
        session.authorizeSavedItemPath = { _, _ in }
        let store = ConfigurationStore()
        let sharedProject = MobileSharedProject(rootURL: fixture.source, name: "OldProject")
        session.beforeSavedItemPersistence = {
            guard var current = try? await store.loadGlobalPreferences(at: fixture.preferences) else { return }
            current.mobileSync.projects = [sharedProject]
            try? await store.saveGlobalPreferences(current, at: fixture.preferences)
        }
        let controller = DesktopSyncController(preferencesURL: fixture.preferences,
                                                configurations: ConfigurationStore(), usesHelper: false)

        await session.repairSavedItem(fixture.item, at: fixture.destination, sharing: controller)

        let saved = try await store.loadGlobalPreferences(at: fixture.preferences)
        XCTAssertEqual(saved.favorites, [fixture.item])
        XCTAssertEqual(saved.recentProjectPaths, [fixture.source])
        XCTAssertEqual(saved.mobileSync.projects, [sharedProject])
        XCTAssertNotNil(session.errorMessage)
    }

    func testSavedItemRecoveryErrorUsesSelectedLanguageWhenReported() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let preferences = root.appendingPathComponent("preferences.json")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let session = AppSession(preferencesURL: preferences)
        defer { session.stop() }
        let previous = LanguageSettings.shared.language
        defer { LanguageSettings.shared.language = previous }

        LanguageSettings.shared.language = .spanish
        session.report(SavedItemRecoveryError(message: "The selected project cannot be opened."))

        XCTAssertEqual(session.errorMessage, "No se puede abrir el proyecto seleccionado.")
    }

    func testReportPreservesDetailsForNonLocalizedErrors() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let preferences = root.appendingPathComponent("preferences.json")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let session = AppSession(preferencesURL: preferences)
        defer { session.stop() }

        let missing = root.appendingPathComponent("MissingProject")
        session.report(FileSystemRepositoryError.projectDoesNotExist(missing))

        XCTAssertEqual(session.errorMessage, String(describing: FileSystemRepositoryError.projectDoesNotExist(missing)))
    }
}

@MainActor
private final class SavedItemRecoveryFixture {
    let root: URL
    let preferences: URL
    let source: URL
    let destination: URL
    let realDestination: URL
    let item: FavoriteItem
    let sharedProject: MobileSharedProject?

    init(kind: FavoriteItem.Kind, shared: Bool = false) throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        preferences = root.appendingPathComponent("preferences.json")
        source = root.appendingPathComponent(kind == .project ? "OldProject" : "old.mdlf")
        destination = root.appendingPathComponent(kind == .project ? "NewProject" : "new.mdlz")
        realDestination = root.appendingPathComponent("RealProject", isDirectory: true)
        item = FavoriteItem(kind: kind, url: source)
        sharedProject = shared ? MobileSharedProject(id: UUID(), rootURL: source, name: "OldProject") : nil
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        if kind == .project {
            try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        }
    }

    func savePreferences() async throws {
        let preferences = GlobalPreferences(
            favorites: [item],
            recentProjectPaths: item.kind == .project ? [source] : [],
            mobileSync: MobileSyncPreferences(projects: sharedProject.map { [$0] } ?? [])
        )
        try await ConfigurationStore().saveGlobalPreferences(preferences, at: self.preferences)
    }

    func cleanup() {
        try? FileManager.default.setAttributes([.posixPermissions: NSNumber(value: 0o700)],
                                                ofItemAtPath: root.path)
        try? FileManager.default.removeItem(at: root)
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

private actor RecoveryPersistenceGate {
    private var armed = false
    private var entered = false
    private var released = false
    private var entryWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseWaiters: [CheckedContinuation<Void, Never>] = []

    func arm() {
        armed = true
        entered = false
        released = false
    }

    func waitIfArmed() async {
        guard armed else { return }
        entered = true
        entryWaiters.forEach { $0.resume() }
        entryWaiters.removeAll()
        if !released {
            await withCheckedContinuation { releaseWaiters.append($0) }
        }
        armed = false
    }

    func waitUntilEntered() async {
        guard !entered else { return }
        await withCheckedContinuation { entryWaiters.append($0) }
    }

    func release() {
        released = true
        releaseWaiters.forEach { $0.resume() }
        releaseWaiters.removeAll()
    }
}

private actor RecoveryPersistenceRuntime: DesktopSyncRuntimeAccess {
    private let startGate: RecoveryPersistenceGate?
    private var failNextStartRequest = false
    private var failNextStopRequest = false
    private var failNextConsentRequest = false

    init(startGate: RecoveryPersistenceGate? = nil) {
        self.startGate = startGate
    }

    func failNextStart() { failNextStartRequest = true }

    func start(host: String, port: UInt16, projects: [SharedProjectSource],
               allowPrivateOverlay: Bool) async throws -> RunningDirectService {
        await startGate?.waitIfArmed()
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
