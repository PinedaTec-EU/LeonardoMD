import XCTest
import LeonardoSync
@testable import LeonardoApp

@MainActor
final class DesktopPeerReviewStoreTests: XCTestCase {
    func testIgnoredGrantChangeReopensReviewAfterStoreReload() throws {
        let suite = "DesktopPeerReviewStoreTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let connectionID = UUID()
        let projectID = UUID()
        let scope = try CorpusScope(folder: "")
        let selection = try CorpusSelection(folders: [], documents: ["docs/one.md"])
        let original = SharedProjectDescriptor(id: projectID, name: "Notes", scope: scope, selection: selection)
        let renamed = SharedProjectDescriptor(id: projectID, name: "Renamed notes", scope: scope, selection: selection)
        let changedGrant = SharedProjectDescriptor(id: projectID, name: "Renamed notes", scope: scope,
            selection: try CorpusSelection(folders: [], documents: ["docs/two.md"]))
        let initial = DesktopPeerReviewStore(defaults: defaults)
        initial.ignoreProject(connectionID: connectionID, descriptor: original)

        let reloaded = DesktopPeerReviewStore(defaults: defaults)
        XCTAssertTrue(reloaded.ignoredProject(connectionID: connectionID, projectID: projectID))
        reloaded.reconcileProjects([renamed], connectionID: connectionID)
        XCTAssertTrue(reloaded.ignoredProject(connectionID: connectionID, projectID: projectID),
                      "A label change does not change access")

        reloaded.reconcileProjects([changedGrant], connectionID: connectionID)
        XCTAssertFalse(reloaded.ignoredProject(connectionID: connectionID, projectID: projectID),
                       "A changed host selection must return the project to review")
    }

    func testLegacyIgnoreStateIsPreservedAndGetsAGrantBaseline() throws {
        let suite = "DesktopPeerReviewStoreLegacyTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let connectionID = UUID()
        let projectID = UUID()
        let descriptor = SharedProjectDescriptor(id: projectID, name: "Notes", scope: try CorpusScope(folder: ""))
        let legacy = LegacyState(connections: [connectionID: LegacyConnectionState(ignoredProjects: [projectID])])
        defaults.set(try JSONEncoder().encode(legacy), forKey: "desktopPeerReviewState")

        let store = DesktopPeerReviewStore(defaults: defaults)
        XCTAssertTrue(store.ignoredProject(connectionID: connectionID, projectID: projectID))
        store.reconcileProjects([descriptor], connectionID: connectionID)
        XCTAssertTrue(store.ignoredProject(connectionID: connectionID, projectID: projectID),
                      "Loading an older ignore choice must not accept it again")
        store.reconcileProjects([SharedProjectDescriptor(id: projectID, name: "Notes",
            scope: try CorpusScope(folder: "archive"))], connectionID: connectionID)
        XCTAssertFalse(store.ignoredProject(connectionID: connectionID, projectID: projectID),
                       "The migrated baseline must allow a later grant change to reopen review")
    }
}

private struct LegacyState: Encodable {
    var migratedExistingProjects = true
    var connections: [UUID: LegacyConnectionState]
}

private struct LegacyConnectionState: Encodable {
    var hostName: String?
    var acceptedProjects: Set<UUID> = []
    var ignoredProjects: Set<UUID>
    var newFilePaths: [UUID: Set<String>] = [:]
}
