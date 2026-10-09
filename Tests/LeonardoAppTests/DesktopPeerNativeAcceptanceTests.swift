import XCTest
import LeonardoCore
import LeonardoSync
import LeonardoSyncTransport
import LeonardoDesktopSync
@testable import LeonardoApp

/// Exercises both native controller/editor compositions through real pinned HTTPS.
/// It does not launch another packaged process or claim physical VPN coverage.
@MainActor
final class DesktopPeerNativeAcceptanceTests: XCTestCase {
    func testNativeControllersReconcileOfflineCopiesAndRevokeOpenEditors() async throws {
        let fixture = try NativePeerAcceptanceFixture()
        defer { fixture.cleanup() }
        await fixture.owner.initialize()
        await fixture.owner.update(fixture.enabledSettings)
        let running = try XCTUnwrap(fixture.owner.running, fixture.owner.error ?? "Missing service")
        do {
            await fixture.peer.initialize()
            let enrolled = await fixture.peer.enroll(address: running.endpoint.absoluteString, name: "Synthetic MacBook")
            XCTAssertTrue(enrolled, fixture.peer.error ?? "Enrollment failed")
            let connection = try XCTUnwrap(fixture.peer.connections.first)
            await fixture.owner.refreshConsent()
            let request = try XCTUnwrap(fixture.owner.consent.requests.first)
            XCTAssertEqual(request.kind, .desktopPeer)
            XCTAssertEqual(connection.comparisonCode, request.comparisonCode)
            await fixture.owner.approve(request, projects: [fixture.shared.id])
            await fixture.peer.refresh(connection.id)
            XCTAssertEqual(fixture.peer.available[connection.id]?.map(\.id), [fixture.shared.id])
            await fixture.peer.importProject(connectionID: connection.id, projectID: fixture.shared.id)
            let copy = try XCTUnwrap(fixture.peer.copies.first)
            let opened = await fixture.peer.open(copy.id)
            let directory = try XCTUnwrap(opened)
            XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("code/private.md").path))
            XCTAssertEqual(try fixture.read(directory, "loose.md"), "individual document")
            await fixture.ownerEditor.openDocument(fixture.source.appendingPathComponent("docs/note.md"))
            let peerEditor = fixture.peerTabs.activeSession
            await peerEditor.openDocument(directory.appendingPathComponent("docs/note.md"))

            // Service loss retains the actual working directory and pending editor bytes.
            var disabled = fixture.enabledSettings
            disabled.enabled = false
            await fixture.owner.update(disabled)
            try fixture.write(directory, "docs/note.md", "offline saved")
            try fixture.write(directory, "docs/new.md", "offline addition")
            try FileManager.default.removeItem(at: directory.appendingPathComponent("docs/delete.md"))
            peerEditor.content = "offline peer draft"
            fixture.ownerEditor.content = "owner conflicting draft"
            await fixture.peer.compare(copy.id)
            XCTAssertNotNil(fixture.peer.error)
            XCTAssertEqual(peerEditor.content, "offline peer draft")
            XCTAssertEqual(try fixture.read(directory, "docs/new.md"), "offline addition")
            XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("docs/delete.md").path))
            XCTAssertEqual(fixture.peer.copies.first?.files.first(where: { $0.path == "docs/note.md" })?.content,
                           Data("offline peer draft".utf8))

            // Reconnect to the same persisted TLS identity, send and review on the owner.
            var resumed = fixture.enabledSettings
            resumed.port = try XCTUnwrap(UInt16(exactly: try XCTUnwrap(running.endpoint.port)))
            await fixture.owner.update(resumed)
            XCTAssertEqual(fixture.owner.running?.certificateFingerprint, running.certificateFingerprint)
            await fixture.peer.compare(copy.id)
            XCTAssertNil(fixture.peer.error)
            let comparison = try XCTUnwrap(fixture.peer.comparisons[copy.id])
            XCTAssertTrue(comparison.comparison.differences.contains(where: { $0.path == "docs/note.md" && $0.hasConflict }))
            await fixture.peer.send(copy.id)
            XCTAssertNil(fixture.peer.error)
            XCTAssertTrue(fixture.peer.submitted.contains(copy.id))
            await fixture.owner.refreshConsent()
            let incoming = try XCTUnwrap(fixture.owner.incoming.first)
            await fixture.owner.reviewProposal(incoming)
            let review = try XCTUnwrap(fixture.owner.reviewing)
            XCTAssertTrue(review.review.comparison.differences.contains(where: { $0.path == "docs/note.md" && $0.hasConflict }))
            XCTAssertEqual(try fixture.read(fixture.source, "docs/note.md"), "baseline")
            let applied = await fixture.owner.applyReview(review, decisions: [
                "docs/note.md": .content(Data("manual resolution".utf8)),
                "docs/new.md": .local,
                "docs/delete.md": .local
            ])
            XCTAssertTrue(applied, fixture.owner.error ?? "Reconciliation failed")
            XCTAssertEqual(fixture.ownerEditor.content, "manual resolution")
            XCTAssertFalse(fixture.ownerEditor.isDirty)
            XCTAssertEqual(try fixture.read(fixture.source, "docs/new.md"), "offline addition")
            XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.source.appendingPathComponent("docs/delete.md").path))
            XCTAssertEqual(try fixture.read(fixture.source, "code/private.md"), "unshared sentinel")

            // Receipt application must retain edits made after the immutable send.
            peerEditor.content = "later peer draft"
            try fixture.write(directory, "docs/later.md", "later addition")
            await fixture.peer.send(copy.id)
            XCTAssertNil(fixture.peer.error)
            XCTAssertEqual(peerEditor.content, "later peer draft")
            XCTAssertTrue(peerEditor.isDirty)
            XCTAssertEqual(fixture.peer.copies.first?.base.files.first(where: { $0.path == "docs/note.md" })?.content,
                           Data("manual resolution".utf8))
            await fixture.owner.refreshConsent()
            XCTAssertEqual(fixture.owner.incoming.count, 1)
            XCTAssertNotEqual(fixture.owner.incoming.first?.upload.proposalID, incoming.upload.proposalID)

            // The native tab revoker closes access before the library removes files.
            await fixture.owner.revoke(connection.remoteDeviceID)
            await fixture.peer.refresh(connection.id)
            XCTAssertTrue(fixture.peer.copies.isEmpty)
            XCTAssertTrue(fixture.peer.connections.first?.revoked == true)
            XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
            XCTAssertTrue(peerEditor.stopped)
            XCTAssertNil(peerEditor.documentURL)
            XCTAssertEqual(peerEditor.content, "")
            XCTAssertEqual(fixture.ownerEditor.content, "manual resolution")
            await fixture.owner.stop()
        } catch {
            await fixture.owner.stop()
            throw error
        }
    }
}

@MainActor
private final class NativePeerAcceptanceFixture {
    let root: URL
    let source: URL
    let shared: MobileSharedProject
    let owner: DesktopSyncController
    let peer: DesktopPeerController
    let ownerEditor: AppSession
    let peerTabs: DocumentTabs
    private let defaults: UserDefaults
    private let defaultsSuite: String
    private let oldSessions: @MainActor () -> [AppSession]
    var enabledSettings: MobileSyncPreferences {
        MobileSyncPreferences(enabled: true, host: "127.0.0.1", port: 0, projects: [shared])
    }

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defaultsSuite = "NativePeerAcceptance." + root.lastPathComponent
        defaults = try XCTUnwrap(UserDefaults(suiteName: defaultsSuite))
        source = root.appendingPathComponent("Source")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        shared = MobileSharedProject(rootURL: source, name: "Synthetic Studio", folders: ["docs"], documents: ["loose.md"])
        let ownerPreferences = root.appendingPathComponent("Owner/preferences.json")
        let peerPreferences = root.appendingPathComponent("Peer/preferences.json")
        ownerEditor = AppSession(preferencesURL: ownerPreferences)
        peerTabs = DocumentTabs(preferencesURL: peerPreferences)
        let credentials = NativePeerAcceptanceCredentials()
        let runtime = DesktopDirectRuntime(root: root.appendingPathComponent("Service"), credentials: credentials, now: { Date() })
        owner = DesktopSyncController(preferencesURL: ownerPreferences, configurations: ConfigurationStore(), runtime: runtime)
        let peerRoot = peerPreferences.deletingLastPathComponent().appendingPathComponent("DesktopPeers")
        let working = peerRoot.appendingPathComponent("Working")
        let copies = FileDesktopPeerCopyStore(root: peerRoot.appendingPathComponent("Copies"))
        let revoker = DesktopPeerEditorRevoker()
        let library = DesktopPeerLibrary(
            connections: FileDesktopPeerConnectionStore(root: peerRoot.appendingPathComponent("Connections")),
            copies: copies, workspace: DesktopPeerWorkspace(root: working, copies: copies),
            credentials: credentials, remote: DesktopPeerHTTPSRemote(), revoker: revoker,
            outbox: FileDesktopPeerOutboxStore(root: peerRoot.appendingPathComponent("Outbox")),
            receiptApplier: DesktopPeerReceiptApplier(workingRoot: working, copies: copies,
                intents: FileDesktopPeerReceiptIntentStore(root: peerRoot.appendingPathComponent("ReceiptIntents"))))
        peer = DesktopPeerController(preferencesURL: peerPreferences, library: library, revoker: revoker, defaults: defaults)
        oldSessions = NativeReconciliationLease.shared.sessions
        let editor = ownerEditor, tabs = peerTabs
        NativeReconciliationLease.shared.sessions = { [editor] + tabs.tabs.map(\.session) }
        owner.buffers = { _ in editor.documentURL == nil ? [] : [OpenDocumentBuffer(path: "docs/note.md", text: editor.content)] }
        peer.buffers = { _ in
            tabs.tabs.compactMap { tab in
                guard tab.session.documentURL != nil else { return nil }
                return OpenDocumentBuffer(path: "docs/note.md", text: tab.session.content)
            }
        }
        revoker.close = { ids in
            let directories = ids.map { working.appendingPathComponent($0.uuidString) }
            await NativeReconciliationLease.shared.waitUntilReleased(directories)
            await tabs.revokeWorkspaces(directories)
        }
        try write(source, "docs/note.md", "baseline")
        try write(source, "docs/delete.md", "delete baseline")
        try write(source, "loose.md", "individual document")
        try write(source, "code/private.md", "unshared sentinel")
    }

    func write(_ directory: URL, _ path: String, _ text: String) throws {
        let file = directory.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: file)
    }

    func read(_ directory: URL, _ path: String) throws -> String {
        try String(contentsOf: directory.appendingPathComponent(path), encoding: .utf8)
    }

    func cleanup() {
        ownerEditor.stop(); peerTabs.stop(); peer.stop()
        NativeReconciliationLease.shared.sessions = oldSessions
        defaults.removePersistentDomain(forName: defaultsSuite)
        try? FileManager.default.removeItem(at: root)
    }
}

private actor NativePeerAcceptanceCredentials: DeviceCredentialStore {
    private var values: [UUID: String] = [:]
    func credential(deviceID: UUID) -> String? { values[deviceID] }
    func save(_ credential: String, deviceID: UUID) { values[deviceID] = credential }
    func remove(deviceID: UUID) { values.removeValue(forKey: deviceID) }
}
