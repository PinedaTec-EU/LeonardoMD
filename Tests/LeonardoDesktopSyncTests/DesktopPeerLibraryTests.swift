#if os(macOS)
import XCTest
import LeonardoSync
import LeonardoSyncTransport
@testable import LeonardoDesktopSync

final class DesktopPeerLibraryTests: XCTestCase {
    func testRealPinnedHTTPSEnrollmentImportAndRevocation() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let descriptor = SharedProjectDescriptor(id: UUID(), name: "Actual TLS notes", scope: try CorpusScope(folder: ""),
            selection: try CorpusSelection(folders: ["docs"], documents: []))
        let files = [CorpusFile(path: "docs/note.md", content: Data("real TLS corpus".utf8))]
        let source = SharedProjectSource(descriptor: descriptor) {
            CorpusSnapshot(revision: CorpusRevision.make(files: files), files: files)
        }
        let runtime = DesktopDirectRuntime(root: root.appendingPathComponent("Server"), credentials: PeerMemoryCredentials(), now: { Date() })
        let running = try await runtime.start(host: "127.0.0.1", port: 0, projects: [source])
        do {
            let copies = FileDesktopPeerCopyStore(root: root.appendingPathComponent("Copies"))
            let workspace = DesktopPeerWorkspace(root: root.appendingPathComponent("Working"), copies: copies)
            let revoker = PeerRevokerFixture()
            let library = DesktopPeerLibrary(connections: FileDesktopPeerConnectionStore(root: root.appendingPathComponent("Connections")),
                copies: copies, workspace: workspace, credentials: PeerMemoryCredentials(), remote: DesktopPeerHTTPSRemote(), revoker: revoker)
            let connection = try await library.enroll(endpoint: running.endpoint, fingerprint: nil, invitation: nil, name: "MacBook QA")
            let registry = try await runtime.consentState()
            let request = try XCTUnwrap(registry.requests.first)
            XCTAssertEqual(request.kind, .desktopPeer)
            XCTAssertEqual(connection.comparisonCode, request.comparisonCode)
            XCTAssertEqual(connection.remoteDeviceID, request.id)
            try await runtime.approve(requestID: request.id, code: request.comparisonCode, projectIDs: [descriptor.id])
            let approved = try await runtime.consentState()
            XCTAssertEqual(approved.devices.first?.kind, .desktopPeer)
            let copy = try await library.importProject(connectionID: connection.id, projectID: descriptor.id)
            let directory = try await library.open(copyID: copy.id)
            XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent("docs/note.md")), Data("real TLS corpus".utf8))
            try await runtime.revoke(deviceID: request.id)
            let status = try await library.refresh(connectionID: connection.id)
            XCTAssertEqual(status.access, .revoked)
            XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
            let closed = await revoker.closedIDs
            XCTAssertTrue(closed.contains(copy.id))
            do { _ = try await library.open(copyID: copy.id); XCTFail("Revoked TLS copy reopened") } catch {}
            try await runtime.stop()
        } catch { try? await runtime.stop(); throw error }
    }

    func testApprovedImportOpensOfflineAndCapturesNativeEditsForManualComparison() async throws {
        let fixture = try PeerLibraryFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let connection = try await fixture.library.enroll(endpoint: fixture.endpoint, fingerprint: nil, invitation: nil, name: "MacBook")
        let pending = try await fixture.library.refresh(connectionID: connection.id)
        XCTAssertEqual(pending.access, .pending)
        await fixture.remote.setAccess(.authorized)
        let copy = try await fixture.library.importProject(connectionID: connection.id, projectID: fixture.remote.project.id)
        let directory = try await fixture.library.open(copyID: copy.id)
        XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent("docs/note.md")), Data("remote".utf8))
        try Data("offline edit".utf8).write(to: directory.appendingPathComponent("docs/note.md"))
        await fixture.remote.setReachable(false)
        let offline = try await fixture.library.open(copyID: copy.id)
        XCTAssertEqual(try Data(contentsOf: offline.appendingPathComponent("docs/note.md")), Data("offline edit".utf8))
        do { _ = try await fixture.library.compare(copyID: copy.id, buffers: []); XCTFail("Offline remote comparison succeeded") } catch {}
        let captured = try await fixture.copies.load(id: copy.id)
        XCTAssertEqual(captured?.base, copy.base)
        XCTAssertEqual(captured?.files.first?.content, Data("offline edit".utf8))
        await fixture.remote.setReachable(true)
        let comparison = try await fixture.library.compare(copyID: copy.id, buffers: [OpenDocumentBuffer(path: "docs/note.md", text: "active draft")])
        XCTAssertEqual(comparison.comparison.differences.map(\.path), ["docs/note.md"])
        XCTAssertEqual(comparison.copy.files.first?.content, Data("active draft".utf8))
        XCTAssertEqual(comparison.remote.files.first?.content, Data("remote".utf8))
        let secret = try await fixture.credentials.credential(deviceID: connection.id)
        XCTAssertNotNil(secret)
        let wrongAccount = try await fixture.credentials.credential(deviceID: connection.remoteDeviceID)
        XCTAssertNil(wrongAccount)
        let metadata = try String(contentsOf: fixture.connectionRoot.appendingPathComponent(connection.id.uuidString).appendingPathExtension("json"), encoding: .utf8)
        XCTAssertFalse(metadata.contains(try XCTUnwrap(secret)))
        let repeated = try await fixture.library.importProject(connectionID: connection.id, projectID: fixture.remote.project.id)
        XCTAssertEqual(repeated.id, copy.id)
        let transfers = await fixture.remote.snapshotCount
        XCTAssertEqual(transfers, 2) // Import and explicit comparison; reopening/import retry does not redownload.
    }

    func testRevocationIsDurableBeforeFailedPurgeAndRetriesWithoutNetworkOrCredential() async throws {
        let fixture = try PeerLibraryFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let connection = try await fixture.library.enroll(endpoint: fixture.endpoint, fingerprint: nil, invitation: nil, name: "MacBook")
        await fixture.remote.setAccess(.authorized)
        let copy = try await fixture.library.importProject(connectionID: connection.id, projectID: fixture.remote.project.id)
        let directory = try await fixture.library.open(copyID: copy.id)
        await fixture.workspace.setFailRemoval(true)
        await fixture.remote.setAccess(.revoked)
        do { _ = try await fixture.library.refresh(connectionID: connection.id); XCTFail("Failed purge confirmed") } catch {}
        let denied = try await fixture.connections.load(id: connection.id)
        XCTAssertEqual(denied?.revoked, true)
        XCTAssertEqual(denied?.copies[copy.remoteProjectID], copy.id)
        let hidden = try await fixture.library.copies()
        XCTAssertTrue(hidden.isEmpty)
        do { _ = try await fixture.library.open(copyID: copy.id); XCTFail("Revoked copy reopened") }
        catch { XCTAssertEqual(error as? SyncError, .revoked) }
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.path))
        await fixture.workspace.setFailRemoval(false)
        await fixture.remote.setReachable(false)
        let retried = try await fixture.library.refresh(connectionID: connection.id)
        XCTAssertEqual(retried.access, .revoked)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
        let removed = try await fixture.copies.load(id: copy.id)
        XCTAssertNil(removed)
        let credential = try await fixture.credentials.credential(deviceID: connection.id)
        XCTAssertNil(credential)
        let completed = try await fixture.connections.load(id: connection.id)
        XCTAssertTrue(try XCTUnwrap(completed).copies.isEmpty)
        XCTAssertTrue(try XCTUnwrap(completed).revoked)
    }

    func testServerDeviceIDReuseCannotReplaceAnotherConnectionsCredentialAccount() async throws {
        let fixture = try PeerLibraryFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let first = try await fixture.library.enroll(endpoint: fixture.endpoint, fingerprint: nil, invitation: nil, name: "One")
        let second = try await fixture.library.enroll(endpoint: fixture.endpoint, fingerprint: nil, invitation: nil, name: "Two")
        XCTAssertEqual(first.remoteDeviceID, second.remoteDeviceID)
        XCTAssertNotEqual(first.id, second.id)
        let firstSecret = try await fixture.credentials.credential(deviceID: first.id)
        let secondSecret = try await fixture.credentials.credential(deviceID: second.id)
        XCTAssertNotNil(firstSecret); XCTAssertNotNil(secondSecret)
        XCTAssertNotEqual(firstSecret, secondSecret)
        let connections = try await fixture.library.connections()
        XCTAssertEqual(connections.count, 2)
    }
}

private struct PeerLibraryFixture {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let endpoint = URL(string: "https://127.0.0.1:40882")!
    let connectionRoot: URL
    let connections: FileDesktopPeerConnectionStore
    let copies: FileDesktopPeerCopyStore
    let workspace: PeerWorkspaceProxy
    let credentials = PeerMemoryCredentials()
    let remote: PeerRemoteFixture
    let library: DesktopPeerLibrary
    init() throws {
        connectionRoot = root.appendingPathComponent("Connections")
        connections = FileDesktopPeerConnectionStore(root: connectionRoot)
        copies = FileDesktopPeerCopyStore(root: root.appendingPathComponent("Copies"))
        workspace = PeerWorkspaceProxy(DesktopPeerWorkspace(root: root.appendingPathComponent("Working"), copies: copies))
        remote = try PeerRemoteFixture()
        library = DesktopPeerLibrary(connections: connections, copies: copies, workspace: workspace,
            credentials: credentials, remote: remote, revoker: PeerRevokerFixture(), now: { Date(timeIntervalSince1970: 1_000) })
    }
}

private actor PeerRevokerFixture: DesktopPeerAccessRevoker {
    private(set) var closedIDs: Set<UUID> = []
    func closeCopies(_ ids: [UUID]) { closedIDs.formUnion(ids) }
}

private actor PeerMemoryCredentials: DeviceCredentialStore {
    private var values: [UUID: String] = [:]
    func credential(deviceID: UUID) -> String? { values[deviceID] }
    func save(_ credential: String, deviceID: UUID) { values[deviceID] = credential }
    func remove(deviceID: UUID) { values[deviceID] = nil }
}

private actor PeerWorkspaceProxy: DesktopPeerWorkspaceAccess {
    let workspace: DesktopPeerWorkspace
    var failRemoval = false
    init(_ workspace: DesktopPeerWorkspace) { self.workspace = workspace }
    func setFailRemoval(_ value: Bool) { failRemoval = value }
    func install(_ copy: DesktopPeerCopy) async throws -> URL { try await workspace.install(copy) }
    func open(id: UUID) async throws -> URL { try await workspace.open(id: id) }
    func capture(id: UUID, buffers: [OpenDocumentBuffer]) async throws -> DesktopPeerCopy { try await workspace.capture(id: id, buffers: buffers) }
    func remove(id: UUID) async throws {
        if failRemoval { throw SyncError.invalidPath }
        try await workspace.remove(id: id)
    }
}

private actor PeerRemoteFixture: DesktopPeerRemote {
    let deviceID = UUID()
    let project: SharedProjectDescriptor
    private var access = DeviceAccess.pending
    private var reachable = true
    private var credentials: Set<String> = []
    private(set) var snapshotCount = 0
    init() throws {
        project = SharedProjectDescriptor(id: UUID(), name: "Shared notes", scope: try CorpusScope(folder: ""),
            selection: try CorpusSelection(folders: ["docs"], documents: []))
    }
    func setAccess(_ value: DeviceAccess) { access = value }
    func setReachable(_ value: Bool) { reachable = value }
    func probe(endpoint: URL) async throws -> Data { try checkReachable(); return Data(repeating: 1, count: 32) }
    func begin(endpoint: URL, fingerprint: Data, invitation: PairingInvitation?, name: String, credential: String, now: Date) async throws -> PairingChallenge {
        try checkReachable(); credentials.insert(credential)
        return PairingChallenge(id: deviceID, comparisonCode: "12345678", expiresAt: now.addingTimeInterval(300))
    }
    func status(_ connection: DesktopPeerConnection, credential: String) async throws -> DirectDeviceStatus {
        try checkReachable()
        guard credentials.contains(credential) else { throw PairingError.invalidCredential }
        return DirectDeviceStatus(access: access, projects: access == .authorized ? [project] : [])
    }
    func snapshot(_ descriptor: SharedProjectDescriptor, connection: DesktopPeerConnection, credential: String) async throws -> CorpusSnapshot {
        try checkReachable()
        guard access == .authorized, credentials.contains(credential), descriptor.id == project.id else { throw SyncError.revoked }
        snapshotCount += 1
        let files = [CorpusFile(path: "docs/note.md", content: Data("remote".utf8))]
        return CorpusSnapshot(revision: CorpusRevision.make(files: files), files: files)
    }
    private func checkReachable() throws { if !reachable { throw URLError(.notConnectedToInternet) } }
}
#endif
