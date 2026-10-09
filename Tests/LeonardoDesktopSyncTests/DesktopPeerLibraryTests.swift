#if os(macOS)
import XCTest
import LeonardoSync
import LeonardoSyncTransport
@testable import LeonardoDesktopSync

final class DesktopPeerLibraryTests: XCTestCase {
    func testRealPinnedHTTPSLibraryConsumesReceiptPreservesLaterEditsAndAllowsNextProposal() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let sourceRoot = root.appendingPathComponent("Source")
        let sourceFile = sourceRoot.appendingPathComponent("docs/note.md")
        try FileManager.default.createDirectory(at: sourceFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("source baseline".utf8).write(to: sourceFile)
        let selection = try CorpusSelection(folders: ["docs"], documents: [])
        let descriptor = SharedProjectDescriptor(id: UUID(), name: "Receipt source", scope: try CorpusScope(folder: ""), selection: selection)
        let reader = ProjectCorpusReader()
        let source = SharedProjectSource(descriptor: descriptor, rootURL: sourceRoot) {
            try await reader.snapshot(root: sourceRoot, selection: selection)
        }
        let runtime = DesktopDirectRuntime(root: root.appendingPathComponent("Server"), credentials: PeerMemoryCredentials(), now: { Date() })
        let running = try await runtime.start(host: "127.0.0.1", port: 0, projects: [source])
        do {
            let connectionStore = FileDesktopPeerConnectionStore(root: root.appendingPathComponent("Connections"))
            let copies = FileDesktopPeerCopyStore(root: root.appendingPathComponent("Copies"))
            let workingRoot = root.appendingPathComponent("Working")
            let workspace = DesktopPeerWorkspace(root: workingRoot, copies: copies)
            let outbox = FileDesktopPeerOutboxStore(root: root.appendingPathComponent("Outbox"))
            let intents = FileDesktopPeerReceiptIntentStore(root: root.appendingPathComponent("ReceiptIntents"))
            let applier = DesktopPeerReceiptApplier(workingRoot: workingRoot, copies: copies, intents: intents)
            let credentials = PeerMemoryCredentials()
            let revoker = PeerRevokerFixture()
            let library = DesktopPeerLibrary(connections: connectionStore, copies: copies, workspace: workspace,
                credentials: credentials, remote: DesktopPeerHTTPSRemote(), revoker: revoker,
                outbox: outbox, receiptApplier: applier)
            let connection = try await library.enroll(endpoint: running.endpoint, fingerprint: nil, invitation: nil, name: "MacBook receipts")
            let registry = try await runtime.consentState()
            let request = try XCTUnwrap(registry.requests.first)
            try await runtime.approve(requestID: request.id, code: request.comparisonCode, projectIDs: [descriptor.id])
            let copy = try await library.importProject(connectionID: connection.id, projectID: descriptor.id)
            let directory = try await library.open(copyID: copy.id)
            XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent("docs/note.md")), Data("source baseline".utf8))

            let sent = try await library.send(copyID: copy.id,
                buffers: [OpenDocumentBuffer(path: "docs/note.md", text: "proposal draft")])
            let firstID = try XCTUnwrap(sent)
            let pendingValue = try await library.pendingProposal(copyID: copy.id)
            let pending = try XCTUnwrap(pendingValue)
            XCTAssertEqual(pending.proposal.id, firstID)
            let incomingValues = try await runtime.incomingProposals()
            let incoming = try XCTUnwrap(incomingValues.first)
            let review = try await runtime.reviewIncomingProposal(deviceID: incoming.deviceID, upload: incoming.upload)
            let ownerDisk = try await reader.snapshot(root: sourceRoot, selection: selection)
            let acceptedResult = try await runtime.applyIncomingProposal(deviceID: incoming.deviceID, upload: incoming.upload,
                review: review, decisions: ["docs/note.md": .local], projectRoot: sourceRoot,
                currentSource: review.source, currentDisk: ownerDisk)
            let receipt = acceptedResult.receipt
            XCTAssertEqual(receipt.accepted.files.first?.content, Data("proposal draft".utf8))
            XCTAssertEqual(try Data(contentsOf: sourceFile), Data("proposal draft".utf8))

            // These bytes are created after the immutable proposal was sent. The open
            // buffer must survive receipt application while the saved disk bytes remain.
            try Data("later saved".utf8).write(to: directory.appendingPathComponent("docs/note.md"))
            try Data("later addition".utf8).write(to: directory.appendingPathComponent("docs/later.md"))
            let downloadedValue = try await library.pendingReceipt(copyID: copy.id)
            let downloaded = try XCTUnwrap(downloadedValue)
            XCTAssertEqual(downloaded, receipt)
            let applied = try await library.acknowledge(copyID: copy.id, receipt: downloaded,
                buffers: [OpenDocumentBuffer(path: "docs/note.md", text: "later draft")])
            XCTAssertTrue(applied.appliedNow)
            XCTAssertEqual(applied.retainedBufferPaths, ["docs/note.md"])
            XCTAssertEqual(applied.appliedSnapshot.files.first { $0.path == "docs/note.md" }?.content, Data("later saved".utf8))
            XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent("docs/note.md")), Data("later saved".utf8))
            XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent("docs/later.md")), Data("later addition".utf8))
            let acknowledgedValue = try await copies.load(id: copy.id)
            let acknowledged = try XCTUnwrap(acknowledgedValue)
            XCTAssertEqual(acknowledged.base, receipt.accepted)
            XCTAssertEqual(acknowledged.files.first { $0.path == "docs/note.md" }?.content, Data("later draft".utf8))
            XCTAssertTrue(acknowledged.files.first { $0.path == "docs/note.md" }?.isUnsavedBuffer == true)
            XCTAssertFalse(acknowledged.files.first { $0.path == "docs/later.md" }?.isUnsavedBuffer == true)
            let clearedIncoming = try await runtime.incomingProposals()
            XCTAssertTrue(clearedIncoming.isEmpty)
            XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("Outbox").appendingPathComponent(copy.id.uuidString).appendingPathExtension("json").path))

            // Reopen the client from its durable stores and submit another proposal in
            // the same device/project slot after the first ACK has closed it.
            let reopenedWorkspace = DesktopPeerWorkspace(root: workingRoot, copies: copies)
            let reopenedApplier = DesktopPeerReceiptApplier(workingRoot: workingRoot, copies: copies,
                intents: FileDesktopPeerReceiptIntentStore(root: root.appendingPathComponent("ReceiptIntents")))
            let reopenedRevoker = PeerRevokerFixture()
            let reopened = DesktopPeerLibrary(connections: connectionStore, copies: copies, workspace: reopenedWorkspace,
                credentials: credentials, remote: DesktopPeerHTTPSRemote(), revoker: reopenedRevoker,
                outbox: outbox, receiptApplier: reopenedApplier)
            let reopenedDirectory = try await reopened.open(copyID: copy.id)
            XCTAssertEqual(reopenedDirectory, directory)
            let secondSent = try await reopened.send(copyID: copy.id,
                buffers: [OpenDocumentBuffer(path: "docs/note.md", text: "second draft")])
            let secondID = try XCTUnwrap(secondSent)
            XCTAssertNotEqual(secondID, firstID)
            let secondIncoming = try await runtime.incomingProposals()
            XCTAssertEqual(secondIncoming.map(\.upload.proposalID), [secondID])

            try await runtime.revoke(deviceID: connection.remoteDeviceID)
            let revoked = try await reopened.refresh(connectionID: connection.id)
            XCTAssertEqual(revoked.access, .revoked)
            XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
            let clearedOutbox = try await outbox.load(copyID: copy.id)
            XCTAssertNil(clearedOutbox)
            let closedIDs = await reopenedRevoker.closedIDs
            XCTAssertTrue(closedIDs.contains(copy.id))
            try await runtime.stop()
        } catch {
            try? await runtime.stop()
            throw error
        }
    }

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
                copies: copies, workspace: workspace, credentials: PeerMemoryCredentials(), remote: DesktopPeerHTTPSRemote(), revoker: revoker,
                outbox: FileDesktopPeerOutboxStore(root: root.appendingPathComponent("Outbox")))
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
            try Data("sent over TLS".utf8).write(to: directory.appendingPathComponent("docs/note.md"))
            let sentID = try await library.send(copyID: copy.id, buffers: [])
            let intent = try await library.pendingProposal(copyID: copy.id)
            XCTAssertEqual(sentID, intent?.proposal.id)
            let inbox = try await runtime.incomingProposals()
            XCTAssertEqual(inbox.first?.upload.proposalID, sentID)
            let received = try await runtime.incomingProposal(deviceID: request.id, upload: XCTUnwrap(inbox.first?.upload))
            XCTAssertEqual(received, intent?.proposal)
            try Data("later native edit".utf8).write(to: directory.appendingPathComponent("docs/note.md"))
            let retried = try await library.send(copyID: copy.id, buffers: [])
            XCTAssertEqual(retried, sentID)
            let later = try await copies.load(id: copy.id)
            XCTAssertEqual(later?.files.first?.content, Data("later native edit".utf8))
            XCTAssertEqual(later?.base, copy.base)
            try await runtime.revoke(deviceID: request.id)
            let status = try await library.refresh(connectionID: connection.id)
            XCTAssertEqual(status.access, .revoked)
            XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
            XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("Outbox").appendingPathComponent(copy.id.uuidString).appendingPathExtension("json").path))
            let closed = await revoker.closedIDs
            XCTAssertTrue(closed.contains(copy.id))
            do { _ = try await library.open(copyID: copy.id); XCTFail("Revoked TLS copy reopened") } catch {}
            try await runtime.stop()
        } catch { try? await runtime.stop(); throw error }
    }

    func testFailedSendPersistsCaptureAndReopenedRetryPreservesLaterEditsUntilReceipt() async throws {
        let fixture = try PeerLibraryFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let connection = try await fixture.library.enroll(endpoint: fixture.endpoint, fingerprint: nil, invitation: nil, name: "MacBook")
        await fixture.remote.setAccess(.authorized)
        let copy = try await fixture.library.importProject(connectionID: connection.id, projectID: fixture.remote.project.id)
        let directory = try await fixture.library.open(copyID: copy.id)
        let clean = try await fixture.library.send(copyID: copy.id, buffers: [])
        XCTAssertNil(clean)
        let noIntent = try await fixture.outbox.load(copyID: copy.id)
        XCTAssertNil(noIntent)
        try Data("first capture".utf8).write(to: directory.appendingPathComponent("docs/note.md"))
        await fixture.remote.setReachable(false)
        do { _ = try await fixture.library.send(copyID: copy.id, buffers: []); XCTFail("Offline send succeeded") }
        catch { XCTAssertEqual((error as? URLError)?.code, .notConnectedToInternet) }
        let loadedIntent = try await fixture.library.pendingProposal(copyID: copy.id)
        let intent = try XCTUnwrap(loadedIntent)
        XCTAssertEqual(intent.proposal.proposed.files.first?.content, Data("first capture".utf8))
        try Data("later disk edit".utf8).write(to: directory.appendingPathComponent("docs/note.md"))
        try Data("later addition".utf8).write(to: directory.appendingPathComponent("docs/new.md"))
        await fixture.remote.setReachable(true)
        let reopened = DesktopPeerLibrary(connections: fixture.connections, copies: fixture.copies, workspace: fixture.workspace,
            credentials: fixture.credentials, remote: fixture.remote, revoker: PeerRevokerFixture(), outbox: fixture.outbox)
        let retry = try await reopened.send(copyID: copy.id, buffers: [OpenDocumentBuffer(path: "docs/note.md", text: "active later draft")])
        XCTAssertEqual(retry, intent.proposal.id)
        let publications = await fixture.remote.publications
        XCTAssertEqual(publications, [intent.proposal])
        let loadedCopy = try await fixture.copies.load(id: copy.id)
        let current = try XCTUnwrap(loadedCopy)
        XCTAssertEqual(current.base, copy.base)
        XCTAssertEqual(current.files.first { $0.path == "docs/note.md" }?.content, Data("active later draft".utf8))
        XCTAssertEqual(current.files.first { $0.path == "docs/new.md" }?.content, Data("later addition".utf8))
        let retained = try await reopened.pendingProposal(copyID: copy.id)
        XCTAssertEqual(retained, intent)
        await fixture.remote.setAccess(.revoked)
        do { _ = try await reopened.send(copyID: copy.id, buffers: []); XCTFail("Revoked copy sent") } catch {}
        let cleared = try await fixture.outbox.load(copyID: copy.id)
        XCTAssertNil(cleared)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
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
    let outbox: FileDesktopPeerOutboxStore
    let library: DesktopPeerLibrary
    init() throws {
        connectionRoot = root.appendingPathComponent("Connections")
        connections = FileDesktopPeerConnectionStore(root: connectionRoot)
        copies = FileDesktopPeerCopyStore(root: root.appendingPathComponent("Copies"))
        workspace = PeerWorkspaceProxy(DesktopPeerWorkspace(root: root.appendingPathComponent("Working"), copies: copies))
        remote = try PeerRemoteFixture()
        outbox = FileDesktopPeerOutboxStore(root: root.appendingPathComponent("Outbox"))
        library = DesktopPeerLibrary(connections: connections, copies: copies, workspace: workspace,
            credentials: credentials, remote: remote, revoker: PeerRevokerFixture(), outbox: outbox, now: { Date(timeIntervalSince1970: 1_000) })
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
    func captureDisk(id: UUID) async throws -> CorpusSnapshot { try await workspace.captureDisk(id: id) }
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
    private(set) var publications: [DesktopPeerProposal] = []
    private var receipts: [UUID: DesktopPeerProposalReceipt] = [:]
    func publish(_ proposal: DesktopPeerProposal, connection: DesktopPeerConnection, credential: String) async throws {
        try checkReachable()
        guard access == .authorized, credentials.contains(credential), proposal.projectID == project.id else { throw SyncError.revoked }
        publications.append(proposal)
    }
    func receipt(_ proposal: DesktopPeerProposal, connection: DesktopPeerConnection, credential: String) async throws -> DesktopPeerProposalReceipt? {
        try checkReachable()
        guard access == .authorized, credentials.contains(credential), proposal.projectID == project.id else { throw SyncError.revoked }
        return receipts[proposal.id]
    }
    func acknowledge(_ proposal: DesktopPeerProposal, receipt: DesktopPeerProposalReceipt,
                     connection: DesktopPeerConnection, credential: String) async throws {
        try checkReachable()
        guard access == .authorized, credentials.contains(credential), proposal.projectID == project.id,
              receipts[proposal.id] == receipt else { throw SyncError.revoked }
    }
    private func checkReachable() throws { if !reachable { throw URLError(.notConnectedToInternet) } }
}
#endif
