import XCTest
import LeonardoCore
@testable import LeonardoApp

@MainActor
final class InstancePolicyTests: XCTestCase {
    func testAdditionalRequiresBothOptInAndExplicitRequest() throws {
        let name = "eu.pinedatec.LeonardoMD.test.\(UUID().uuidString)"
        let owner = SingleInstance(name: name)
        defer { owner.stop() }
        XCTAssertEqual(try owner.claim(), .primary)
        let follower = SingleInstance(name: name)
        XCTAssertEqual(try follower.claim(), .secondary)
        XCTAssertEqual(try follower.claim(additionalRequested: true), .secondary)
        XCTAssertEqual(try follower.claim(allowsMultipleInstances: true), .secondary)
        XCTAssertEqual(try follower.claim(additionalRequested: true, allowsMultipleInstances: true), .additional)
        owner.stop()
        XCTAssertEqual(try follower.claim(), .primary)
        follower.stop()
    }

    func testPreferenceDefaultsOffAndCanBeChangedAcrossControllers() {
        let name = "LeonardoInstancePreferencesTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let first = InstancePreferences(defaults: defaults)
        let second = InstancePreferences(defaults: defaults)
        XCTAssertFalse(first.allowsMultipleInstances)
        first.allowsMultipleInstances = true
        XCTAssertTrue(second.allowsMultipleInstances)
        second.allowsMultipleInstances = false
        XCTAssertFalse(first.allowsMultipleInstances)
    }

    func testGroupingRequiresMultipleInstancesAndRetainsTheUsersChoice() {
        let name = "InstanceGroupingTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let first = InstancePreferences(defaults: defaults)
        let second = InstancePreferences(defaults: defaults)
        XCTAssertFalse(first.groupsInstances)
        first.groupsInstances = true
        XCTAssertFalse(first.groupingEnabled)
        first.allowsMultipleInstances = true
        XCTAssertTrue(second.groupingEnabled)
        second.allowsMultipleInstances = false
        XCTAssertFalse(first.groupingEnabled)
        XCTAssertTrue(first.groupsInstances)
        second.allowsMultipleInstances = true
        XCTAssertTrue(first.groupingEnabled)
        first.groupsInstances = false
        XCTAssertFalse(second.groupingEnabled)
    }

    func testGroupingElectsOneRepresentativeAndRecoversWhenItExits() {
        let older = UpdateProcessIdentity(pid: 100, launchDate: Date(timeIntervalSinceReferenceDate: 1))
        let newer = UpdateProcessIdentity(pid: 200, launchDate: Date(timeIntervalSinceReferenceDate: 2))
        let peers = [newer, older]
        XCTAssertEqual(InstancePresentation.activationPolicy(grouped: true, current: older, peers: peers), .regular)
        XCTAssertEqual(InstancePresentation.activationPolicy(grouped: true, current: newer, peers: peers), .accessory)
        XCTAssertEqual(InstancePresentation.activationPolicy(grouped: true, current: newer, peers: [newer]), .regular)
        XCTAssertEqual(InstancePresentation.activationPolicy(grouped: false, current: newer, peers: peers), .regular)
        XCTAssertEqual(InstancePresentation.activationPolicy(grouped: true, current: newer, peers: []), .regular)
        let tie = UpdateProcessIdentity(pid: 50, launchDate: older.launchDate)
        XCTAssertEqual(InstancePresentation.representative(in: [older, tie]), tie)
    }

    func testAccessoryApplicationMenuKeepsRealActionsWithoutMutatingTheMenuBar() {
        let original = NSMenu()
        let file = NSMenuItem(title: "File", action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: "File")
        let action = NSMenuItem(title: "New window", action: NSSelectorFromString("newEmptyWindow"), keyEquivalent: "n")
        let target = NSObject()
        action.target = target
        submenu.addItem(action)
        file.submenu = submenu
        original.addItem(file)
        let popup = InstanceApplicationMenu.makeMenu(from: original, title: "Application menu")
        XCTAssertEqual(original.items.count, 1)
        XCTAssertEqual(popup.items.count, 2)
        XCTAssertEqual(popup.items.first?.title, "Application menu")
        let copiedAction = popup.items[1].submenu?.items.first
        XCTAssertEqual(copiedAction?.action, action.action)
        XCTAssertTrue(copiedAction?.target === target)
        XCTAssertEqual(copiedAction?.keyEquivalent, "n")
        XCTAssertFalse(popup.items[1] === original.items[0])
    }

    func testUnavailableSuiteUsesStandardApplicationPreferences() {
        let defaults = UserDefaults.standard
        let key = InstancePreferences.preferenceKey
        let original = defaults.object(forKey: key)
        defer {
            if let original { defaults.set(original, forKey: key) }
            else { defaults.removeObject(forKey: key) }
            defaults.synchronize()
        }
        defaults.set(false, forKey: key)
        let preferences = InstancePreferences(defaults: nil)
        XCTAssertFalse(preferences.allowsMultipleInstances)
        preferences.allowsMultipleInstances = true
        XCTAssertTrue(defaults.bool(forKey: key))
        defaults.set(false, forKey: key)
        XCTAssertFalse(preferences.allowsMultipleInstances)
    }

    func testProductionPreferenceInitializerDoesNotRequireAnAvailableSuite() {
        let preferences = InstancePreferences()
        _ = preferences.allowsMultipleInstances
    }

    func testAdditionalDoesNotStartSharedServicesOrClearUpdateState() async throws {
        let previous = InstanceRuntime.isAdditional
        InstanceRuntime.isAdditional = true
        let suite = "InstanceServiceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer {
            InstanceRuntime.isAdditional = previous
            defaults.removePersistentDomain(forName: suite)
        }
        defaults.set("42", forKey: PendingUpdateDecisionStore.preferenceKey)
        let decision = PendingUpdateDecisionStore(defaults: defaults, installedBuild: "43")
        XCTAssertEqual(decision.targetBuild, "42")
        let updates = ApplicationUpdates(defaults: defaults)
        updates.start()
        XCTAssertFalse(updates.isStarted)
        XCTAssertFalse(updates.canChangeChannel)
        let original = updates.channel
        updates.selectChannel(original == .stable ? .beta : .stable)
        XCTAssertEqual(updates.channel, original)
        let peers = DesktopPeerController(defaults: defaults)
        await peers.initialize()
        let enrolled = await peers.enroll(address: "invalid", name: "test")
        XCTAssertFalse(enrolled)
        XCTAssertTrue(peers.connections.isEmpty)
    }

    func testOverlappingPathsRejectOtherOwnersAndRecoverAfterExit() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let registry = root.appendingPathComponent("Registry")
        let first = InstancePathOwnership(directory: registry)
        let second = InstancePathOwnership(directory: registry)
        let document = root.appendingPathComponent("Project/document.md")
        try first.claim(document)
        XCTAssertThrowsError(try second.claim(document)) { XCTAssertTrue($0 is InstancePathOwnership.InUse) }
        XCTAssertThrowsError(try second.claim(document.deletingLastPathComponent()))
        try second.claim(root.appendingPathComponent("Project-neighbor"))
        // A crash closes descriptors; abandoned metadata alone must not claim a path.
        let abandoned = registry.appendingPathComponent("abandoned.claim")
        try Data(root.appendingPathComponent("Unused").path.utf8).write(to: abandoned)
        try second.claim(root.appendingPathComponent("Unused"))
    }

    func testCaseAliasesReserveTheSameExistingAndFuturePaths() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let sensitive = try root.resourceValues(forKeys: [.volumeSupportsCaseSensitiveNamesKey]).volumeSupportsCaseSensitiveNames
        guard sensitive == false else { throw XCTSkip("Requires a case-insensitive volume") }
        let file = root.appendingPathComponent("Document.md")
        try Data("draft".utf8).write(to: file)
        let first = InstancePathOwnership(directory: root.appendingPathComponent("Registry"))
        let second = InstancePathOwnership(directory: root.appendingPathComponent("Registry"))
        try first.claim(file)
        XCTAssertThrowsError(try second.claim(root.appendingPathComponent("DOCUMENT.MD")))
        try first.claim(root.appendingPathComponent("Future.md"))
        XCTAssertThrowsError(try second.claim(root.appendingPathComponent("FUTURE.MD")))
        XCTAssertEqual(ProcessFileLock.key(for: file), ProcessFileLock.key(for: root.appendingPathComponent("DOCUMENT.MD")))
    }

    func testSymlinkAliasesAndDirectoryDescendantsShareOwnership() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let real = root.appendingPathComponent("Real")
        try FileManager.default.createDirectory(at: real, withIntermediateDirectories: true)
        let alias = root.appendingPathComponent("Alias")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: real)
        let first = InstancePathOwnership(directory: root.appendingPathComponent("Registry"))
        let second = InstancePathOwnership(directory: root.appendingPathComponent("Registry"))
        try first.claim(real)
        try first.claim(real.appendingPathComponent("child.md"))
        XCTAssertThrowsError(try second.claim(alias.appendingPathComponent("child.md")))
    }
}
