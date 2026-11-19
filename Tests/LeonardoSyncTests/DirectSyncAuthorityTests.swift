import XCTest
@testable import LeonardoSync

final class DirectSyncAuthorityTests: XCTestCase {
    func testGrantComparisonTracksScopeAndSelectionButIgnoresProjectName() throws {
        let id = UUID()
        let scope = try CorpusScope(folder: "")
        let selection = try CorpusSelection(folders: [], documents: ["docs/one.md"])
        let original = SharedProjectDescriptor(id: id, name: "Notes", scope: scope, selection: selection)
        let renamed = SharedProjectDescriptor(id: id, name: "Renamed notes", scope: scope, selection: selection)
        let changedScope = SharedProjectDescriptor(id: id, name: "Notes",
            scope: try CorpusScope(folder: "archive"), selection: selection)
        let changedSelection = SharedProjectDescriptor(id: id, name: "Notes", scope: scope,
            selection: try CorpusSelection(folders: [], documents: ["docs/two.md"]))

        XCTAssertTrue(original.representsSameGrant(as: renamed))
        XCTAssertFalse(original.representsSameGrant(as: changedScope))
        XCTAssertFalse(original.representsSameGrant(as: changedSelection))
        XCTAssertFalse(original.representsSameGrant(as: SharedProjectDescriptor(
            id: UUID(), name: "Notes", scope: scope, selection: selection)))
    }

    func testSnapshotCannotBroadenSelectedDocumentsDespiteProjectApproval() async throws {
        var registry = PairingRegistry(); registry.setEnabled(true)
        let credential = String(repeating: "a", count: 64)
        let now = Date(timeIntervalSince1970: 1_000)
        let request = try registry.requestPairing(deviceName: "Desktop", credential: credential, serverFingerprint: Data(repeating: 1, count: 32), now: now)
        let project = SharedProjectDescriptor(id: UUID(), name: "Selected", scope: try CorpusScope(folder: ""),
            selection: try CorpusSelection(folders: [], documents: ["docs/one.md"]))
        _ = try registry.approve(requestID: request.id, comparisonCode: request.comparisonCode, projects: [project.id], now: now)
        let authority = try DirectSyncAuthority(registry: registry,
            projects: [SharedProjectSource(descriptor: project) {
                CorpusSnapshot(revision: "r", files: [CorpusFile(path: "docs/private.md", content: Data("private".utf8))])
            }], serverFingerprint: Data(repeating: 1, count: 32), persist: { _ in })
        let status = try await authority.status(deviceID: request.id, credential: credential, now: now)
        XCTAssertEqual(status.projects.first?.selection, project.selection)
        do {
            _ = try await authority.snapshot(deviceID: request.id, credential: credential, projectID: project.id)
            XCTFail("Approval must not broaden the file selection")
        } catch { XCTAssertEqual(error as? SyncError, .outsideScope) }
    }

    func testOldPeerKeepsMarkdownAccessWhileNewPeerCanReadLeonardoFormats() async throws {
        var registry = PairingRegistry(); registry.setEnabled(true)
        let credential = String(repeating: "a", count: 64)
        let now = Date(timeIntervalSince1970: 1_000)
        let fingerprint = Data(repeating: 1, count: 32)
        let request = try registry.requestPairing(deviceName: "Little Leonardo", credential: credential,
            serverFingerprint: fingerprint, now: now)
        let markdown = CorpusFile(path: "docs/readme.md", content: Data("# Read me".utf8))
        let form = CorpusFile(path: "docs/form.mdlf", content: Data("---\n{}\n---\n# Form".utf8))
        let files = [markdown, form]
        let descriptor = SharedProjectDescriptor(id: UUID(), name: "Mixed documents",
            scope: try CorpusScope(folder: ""),
            selection: try CorpusSelection(folders: [], documents: files.map(\.path)))
        _ = try registry.approve(requestID: request.id, comparisonCode: request.comparisonCode,
                                 projects: [descriptor.id], now: now)
        let authority = try DirectSyncAuthority(registry: registry,
            projects: [SharedProjectSource(descriptor: descriptor) {
                CorpusSnapshot(revision: CorpusRevision.make(files: files), files: files)
            }], serverFingerprint: fingerprint, persist: { _ in })

        let legacyStatus = try await authority.status(deviceID: request.id, credential: credential, now: now)
        XCTAssertEqual(legacyStatus.projects.first?.selection?.documents, [markdown.path])
        let currentStatus = try await authority.status(deviceID: request.id, credential: credential, now: now,
                                                       supportsLeonardoFormats: true)
        XCTAssertEqual(currentStatus.projects.first?.selection, descriptor.selection)

        let legacyCatalogue = try await authority.catalogue(deviceID: request.id, credential: credential,
                                                             projectID: descriptor.id)
        XCTAssertEqual(legacyCatalogue.files.map(\.path), [markdown.path])
        let currentCatalogue = try await authority.catalogue(deviceID: request.id, credential: credential,
            projectID: descriptor.id, supportsLeonardoFormats: true)
        XCTAssertEqual(Set(currentCatalogue.files.map(\.path)), Set(files.map(\.path)))

        let legacySnapshot = try await authority.snapshot(deviceID: request.id, credential: credential,
                                                          projectID: descriptor.id)
        XCTAssertEqual(legacySnapshot.files.map(\.path), [markdown.path])
        let currentSnapshot = try await authority.snapshot(deviceID: request.id, credential: credential,
            projectID: descriptor.id, supportsLeonardoFormats: true)
        XCTAssertEqual(Set(currentSnapshot.files.map(\.path)), Set(files.map(\.path)))

        do {
            _ = try await authority.file(deviceID: request.id, credential: credential, projectID: descriptor.id,
                request: RemoteFileRequest(path: form.path, revision: RemoteFileEntry(file: form).revision))
            XCTFail("Legacy clients must not receive formats they cannot decode")
        } catch { XCTAssertEqual(error as? SyncError, .excludedFile) }
        let currentFile = try await authority.file(deviceID: request.id, credential: credential,
            projectID: descriptor.id,
            request: RemoteFileRequest(path: form.path, revision: RemoteFileEntry(file: form).revision),
            supportsLeonardoFormats: true)
        XCTAssertEqual(currentFile, form)
    }

    func testLegacyPeerUploadUsesItsNarrowedExplicitSelection() async throws {
        var registry = PairingRegistry(); registry.setEnabled(true)
        let credential = String(repeating: "a", count: 64), now = Date()
        let fingerprint = Data(repeating: 1, count: 32)
        let request = try registry.requestPairing(deviceName: "Older Mac", credential: credential,
            serverFingerprint: fingerprint, now: now, kind: .desktopPeer)
        let grant = try CorpusSelection(folders: [], documents: ["docs/note.md", "docs/request.mdlf"])
        let project = SharedProjectDescriptor(id: UUID(), name: "Mixed", scope: try CorpusScope(folder: ""), selection: grant)
        _ = try registry.approve(requestID: request.id, comparisonCode: request.comparisonCode,
            projects: [project.id], now: now)
        let legacySelection = try CorpusSelection(folders: [], documents: ["docs/note.md"])
        let legacyView = DesktopPeerUploadView(grantSelection: grant, selection: legacySelection,
                                               supportsLeonardoFormats: false)
        let empty = CorpusSnapshot(revision: "base", files: [])
        let proposal = try DesktopPeerProposal(projectID: project.id, selection: legacySelection,
            base: empty, proposed: empty)
        let upload = try DesktopPeerUpload(proposalID: proposal.id, projectID: project.id,
            byteCount: 1, sha256: String(repeating: "a", count: 64))
        let uploads = FixedProposalUploadStore(proposal: proposal, upload: upload, expectedView: legacyView)
        let authority = try DirectSyncAuthority(registry: registry,
            projects: [SharedProjectSource(descriptor: project) { empty }], serverFingerprint: fingerprint,
            persist: { _ in }, uploads: uploads)

        let result = try await authority.beginUpload(deviceID: request.id, credential: credential, upload: upload)

        XCTAssertEqual(result.proposalID, proposal.id)
    }

    func testRevocationDuringUploadCannotReturnAcknowledgement() async throws {
        var registry = PairingRegistry(); registry.setEnabled(true)
        let credential = String(repeating: "a", count: 64), now = Date()
        let fingerprint = Data(repeating: 1, count: 32)
        let request = try registry.requestPairing(deviceName: "MacBook", credential: credential, serverFingerprint: fingerprint, now: now, kind: .desktopPeer)
        let project = SharedProjectDescriptor(id: UUID(), name: "Docs", scope: try CorpusScope(folder: "docs"))
        _ = try registry.approve(requestID: request.id, comparisonCode: request.comparisonCode, projects: [project.id], now: now)
        let gate = SnapshotGate()
        let authority = try DirectSyncAuthority(registry: registry,
            projects: [SharedProjectSource(descriptor: project) { CorpusSnapshot(revision: "r", files: []) }],
            serverFingerprint: fingerprint, persist: { _ in }, uploads: StalledUploadStore(gate: gate))
        let upload = try DesktopPeerUpload(proposalID: UUID(), projectID: project.id, byteCount: 1, sha256: String(repeating: "a", count: 64))
        let transfer = Task { try await authority.beginUpload(deviceID: request.id, credential: credential, upload: upload) }
        await gate.waitForRead()
        try await authority.revoke(deviceID: request.id)
        await gate.finish()
        do { _ = try await transfer.value; XCTFail("Returned successful upload acknowledgement after revocation") }
        catch { XCTAssertEqual(error as? SyncError, .revoked) }
    }

    func testReceiptReadRechecksRevocationAndRejectsReadOnlyClients() async throws {
        var registry = PairingRegistry(); registry.setEnabled(true)
        let credential = String(repeating: "a", count: 64), now = Date()
        let fingerprint = Data(repeating: 1, count: 32)
        let project = SharedProjectDescriptor(id: UUID(), name: "Docs", scope: try CorpusScope(folder: "docs"))
        let peer = try registry.requestPairing(deviceName: "Mac", credential: credential, serverFingerprint: fingerprint, now: now, kind: .desktopPeer)
        let phoneCredential = String(repeating: "b", count: 64)
        let phone = try registry.requestPairing(deviceName: "Phone", credential: phoneCredential, serverFingerprint: fingerprint, now: now)
        for request in [peer, phone] {
            _ = try registry.approve(requestID: request.id, comparisonCode: request.comparisonCode, projects: [project.id], now: now)
        }
        let receipt = try DesktopPeerProposalReceipt(proposalID: UUID(), projectID: project.id,
            accepted: CorpusSnapshot(revision: "accepted", files: []))
        let selection = try CorpusSelection(folders: ["docs"], documents: [])
        let empty = CorpusSnapshot(revision: "base", files: [])
        let proposal = try DesktopPeerProposal(id: receipt.proposalID, projectID: project.id,
            selection: selection, base: empty, proposed: empty)
        let upload = try DesktopPeerUpload(proposalID: proposal.id, projectID: project.id,
            byteCount: 1, sha256: String(repeating: "a", count: 64))
        let gate = SnapshotGate()
        let authority = try DirectSyncAuthority(registry: registry,
            projects: [SharedProjectSource(descriptor: project) { CorpusSnapshot(revision: "r", files: []) }],
            serverFingerprint: fingerprint, persist: { _ in },
            uploads: FixedProposalUploadStore(proposal: proposal, upload: upload),
            receipts: StalledReceiptStore(gate: gate, receipt: receipt))
        do {
            _ = try await authority.proposalReceipt(deviceID: phone.id, credential: phoneCredential, projectID: project.id, proposalID: receipt.proposalID)
            XCTFail("Read-only client accessed reconciliation receipts")
        } catch { XCTAssertEqual(error as? SyncError, .readOnly) }
        let fetch = Task { try await authority.proposalReceipt(deviceID: peer.id, credential: credential,
            projectID: project.id, proposalID: receipt.proposalID) }
        await gate.waitForRead()
        try await authority.revoke(deviceID: peer.id)
        await gate.finish()
        do { _ = try await fetch.value; XCTFail("Receipt exposed after revocation") }
        catch { XCTAssertEqual(error as? SyncError, .revoked) }
    }

    func testOwnerApplicationBlocksConsentChangesAndServiceReadsUntilItFinishes() async throws {
        var registry = PairingRegistry(); registry.setEnabled(true)
        let credential = String(repeating: "a", count: 64), now = Date()
        let fingerprint = Data(repeating: 1, count: 32)
        let request = try registry.requestPairing(deviceName: "Mac", credential: credential, serverFingerprint: fingerprint, now: now, kind: .desktopPeer)
        let project = SharedProjectDescriptor(id: UUID(), name: "Docs", scope: try CorpusScope(folder: "docs"))
        _ = try registry.approve(requestID: request.id, comparisonCode: request.comparisonCode, projects: [project.id], now: now)
        let selection = try CorpusSelection(folders: ["docs"], documents: [])
        let snapshot = CorpusSnapshot(revision: "accepted", files: [])
        let proposal = try DesktopPeerProposal(projectID: project.id, selection: selection, base: snapshot, proposed: snapshot)
        let upload = try DesktopPeerUpload(proposalID: proposal.id, projectID: project.id, byteCount: 1, sha256: String(repeating: "a", count: 64))
        let root = URL(fileURLWithPath: "/tmp/owner-application-fixture")
        let authority = try DirectSyncAuthority(registry: registry,
            projects: [SharedProjectSource(descriptor: project, rootURL: root) { snapshot }],
            serverFingerprint: fingerprint, persist: { _ in }, uploads: FixedProposalUploadStore(proposal: proposal, upload: upload))
        let gate = SnapshotGate()
        let operation = Task { try await authority.withOwnerApplication(deviceID: request.id, upload: upload) { received, sourceRoot in
            XCTAssertEqual(received, proposal)
            XCTAssertEqual(sourceRoot, root)
            _ = await gate.read()
            return try DesktopPeerProposalReceipt(proposalID: received.id, projectID: received.projectID, accepted: snapshot)
        } }
        await gate.waitForRead()
        do { try await authority.revoke(deviceID: request.id); XCTFail("Revocation interleaved with application") }
        catch { XCTAssertEqual(error as? DirectAuthorityError, .busy) }
        do { try await authority.setEnabled(false); XCTFail("Disable interleaved with application") }
        catch { XCTAssertEqual(error as? DirectAuthorityError, .busy) }
        do { _ = try await authority.snapshot(deviceID: request.id, credential: credential, projectID: project.id); XCTFail("Read interleaved with application") }
        catch { XCTAssertEqual(error as? DirectAuthorityError, .busy) }
        await gate.finish()
        let receipt = try await operation.value
        XCTAssertEqual(receipt.proposalID, proposal.id)
        try await authority.revoke(deviceID: request.id)
    }

    func testReadStartedBeforeOwnerApplicationCannotFinishWithAnOlderCapture() async throws {
        var registry = PairingRegistry(); registry.setEnabled(true)
        let credential = String(repeating: "a", count: 64), now = Date()
        let fingerprint = Data(repeating: 1, count: 32)
        let peer = try registry.requestPairing(deviceName: "Mac", credential: credential, serverFingerprint: fingerprint, now: now, kind: .desktopPeer)
        let project = SharedProjectDescriptor(id: UUID(), name: "Docs", scope: try CorpusScope(folder: "docs"))
        _ = try registry.approve(requestID: peer.id, comparisonCode: peer.comparisonCode, projects: [project.id], now: now)
        let selection = try CorpusSelection(folders: ["docs"], documents: [])
        let snapshot = CorpusSnapshot(revision: "accepted", files: [])
        let proposal = try DesktopPeerProposal(projectID: project.id, selection: selection, base: snapshot, proposed: snapshot)
        let upload = try DesktopPeerUpload(proposalID: proposal.id, projectID: project.id, byteCount: 1, sha256: String(repeating: "a", count: 64))
        let gate = SnapshotGate()
        let authority = try DirectSyncAuthority(registry: registry,
            projects: [SharedProjectSource(descriptor: project, rootURL: URL(fileURLWithPath: "/tmp/epoch-fixture")) { await gate.read() }],
            serverFingerprint: fingerprint, persist: { _ in }, uploads: FixedProposalUploadStore(proposal: proposal, upload: upload))
        let read = Task { try await authority.snapshot(deviceID: peer.id, credential: credential, projectID: project.id) }
        await gate.waitForRead()
        _ = try await authority.withOwnerApplication(deviceID: peer.id, upload: upload) { proposal, _ in
            try DesktopPeerProposalReceipt(proposalID: proposal.id, projectID: proposal.projectID, accepted: snapshot)
        }
        await gate.finish()
        do { _ = try await read.value; XCTFail("Read spanning application escaped the service epoch") }
        catch { XCTAssertEqual(error as? DirectAuthorityError, .busy) }
    }

    func testComparisonCodeBindsCertificateCredentialAndRequest() throws {
        let id = UUID()
        let credential = String(repeating: "a", count: 64)
        let code = try PairingComparisonCode.make(serverFingerprint: Data(repeating: 1, count: 32), credential: credential, requestID: id)
        XCTAssertEqual(code.count, 8)
        XCTAssertNotEqual(code, try PairingComparisonCode.make(serverFingerprint: Data(repeating: 2, count: 32), credential: credential, requestID: id))
        XCTAssertNotEqual(code, try PairingComparisonCode.make(serverFingerprint: Data(repeating: 1, count: 32), credential: String(repeating: "b", count: 64), requestID: id))
        XCTAssertNotEqual(code, try PairingComparisonCode.make(serverFingerprint: Data(repeating: 1, count: 32), credential: credential, requestID: UUID()))
    }

    func testFailedPersistenceDoesNotPublishApproval() async throws {
        var registry = PairingRegistry(); registry.setEnabled(true)
        let credential = String(repeating: "a", count: 64)
        let now = Date(timeIntervalSince1970: 1_000)
        let request = try registry.requestPairing(deviceName: "Phone", credential: credential, serverFingerprint: Data(repeating: 1, count: 32), now: now)
        let project = SharedProjectDescriptor(id: UUID(), name: "Docs", scope: try CorpusScope(folder: "docs"))
        let authority = try DirectSyncAuthority(registry: registry,
            projects: [SharedProjectSource(descriptor: project) { CorpusSnapshot(revision: "r", files: []) }],
            serverFingerprint: Data(repeating: 1, count: 32), persist: { _ in throw SyncError.invalidPath })
        do {
            try await authority.approve(requestID: request.id, code: request.comparisonCode, projectIDs: [project.id], now: now)
            XCTFail("Persistence must complete before approval becomes visible")
        } catch { XCTAssertEqual(error as? SyncError, .invalidPath) }
        let state = try await authority.status(deviceID: request.id, credential: credential, now: now)
        XCTAssertEqual(state.access, .pending)
        XCTAssertTrue(state.projects.isEmpty)
    }

    func testRevocationDuringSnapshotReadCannotReturnDocuments() async throws {
        var registry = PairingRegistry(); registry.setEnabled(true)
        let credential = String(repeating: "a", count: 64)
        let now = Date(timeIntervalSince1970: 1_000)
        let request = try registry.requestPairing(deviceName: "Phone", credential: credential, serverFingerprint: Data(repeating: 1, count: 32), now: now)
        let project = SharedProjectDescriptor(id: UUID(), name: "Docs", scope: try CorpusScope(folder: "docs"))
        _ = try registry.approve(requestID: request.id, comparisonCode: request.comparisonCode, projects: [project.id], now: now)
        let gate = SnapshotGate()
        let authority = try DirectSyncAuthority(registry: registry,
            projects: [SharedProjectSource(descriptor: project) { await gate.read() }],
            serverFingerprint: Data(repeating: 1, count: 32), persist: { _ in })
        let fetch = Task { try await authority.snapshot(deviceID: request.id, credential: credential, projectID: project.id) }
        await gate.waitForRead()
        try await authority.revoke(deviceID: request.id)
        await gate.finish()
        do { _ = try await fetch.value; XCTFail("Revoked device must not receive documents") }
        catch { XCTAssertEqual(error as? SyncError, .revoked) }
    }
}

private actor SnapshotGate {
    private var readContinuation: CheckedContinuation<CorpusSnapshot, Never>?
    private var waitContinuation: CheckedContinuation<Void, Never>?
    func read() async -> CorpusSnapshot {
        await withCheckedContinuation { continuation in
            readContinuation = continuation
            waitContinuation?.resume()
            waitContinuation = nil
        }
    }
    func waitForRead() async {
        if readContinuation != nil { return }
        await withCheckedContinuation { waitContinuation = $0 }
    }
    func finish() {
        readContinuation?.resume(returning: CorpusSnapshot(revision: "r", files: []))
        readContinuation = nil
    }
}

private struct StalledUploadStore: DesktopPeerUploadStore {
    let gate: SnapshotGate
    func begin(deviceID: UUID, upload: DesktopPeerUpload, view: DesktopPeerUploadView) async throws -> Int {
        _ = await gate.read(); return 0
    }
    func append(deviceID: UUID, upload: DesktopPeerUpload, offset: Int, bytes: Data, view: DesktopPeerUploadView) async throws -> Int { throw SyncError.invalidSnapshot }
    func submit(deviceID: UUID, upload: DesktopPeerUpload, view: DesktopPeerUploadView) async throws { throw SyncError.invalidSnapshot }
    func pending(deviceID: UUID, projectID: UUID, grantSelection: CorpusSelection) async throws -> DesktopPeerPendingUpload? { nil }
    func finish(deviceID: UUID, upload: DesktopPeerUpload, view: DesktopPeerUploadView) async throws -> DesktopPeerProposal { throw SyncError.invalidSnapshot }
    func view(deviceID: UUID, projectID: UUID, proposalID: UUID, grantSelection: CorpusSelection) async throws -> DesktopPeerUploadView? { nil }
    func acknowledge(deviceID: UUID, projectID: UUID, proposalID: UUID, view: DesktopPeerUploadView) async throws { throw SyncError.invalidSnapshot }
}

private struct StalledReceiptStore: DesktopPeerReceiptStore {
    let gate: SnapshotGate
    let receipt: DesktopPeerProposalReceipt
    func save(deviceID: UUID, selection: CorpusSelection, receipt: DesktopPeerProposalReceipt) async throws { throw SyncError.invalidSnapshot }
    func load(deviceID: UUID, projectID: UUID, proposalID: UUID, selection: CorpusSelection) async throws -> DesktopPeerProposalReceipt? {
        _ = await gate.read()
        return receipt
    }
}

private struct FixedProposalUploadStore: DesktopPeerUploadStore {
    let proposal: DesktopPeerProposal
    let upload: DesktopPeerUpload
    var expectedView: DesktopPeerUploadView? = nil
    private var uploadView: DesktopPeerUploadView {
        DesktopPeerUploadView(grantSelection: proposal.selection, selection: proposal.selection,
                              supportsLeonardoFormats: true)
    }
    func begin(deviceID: UUID, upload: DesktopPeerUpload, view: DesktopPeerUploadView) async throws -> Int {
        if let expectedView, expectedView != view { throw SyncError.outsideScope }
        return 0
    }
    func append(deviceID: UUID, upload: DesktopPeerUpload, offset: Int, bytes: Data, view: DesktopPeerUploadView) async throws -> Int { 0 }
    func submit(deviceID: UUID, upload: DesktopPeerUpload, view: DesktopPeerUploadView) async throws {}
    func pending(deviceID: UUID, projectID: UUID, grantSelection: CorpusSelection) async throws -> DesktopPeerPendingUpload? {
        DesktopPeerPendingUpload(upload: upload, view: uploadView)
    }
    func finish(deviceID: UUID, upload: DesktopPeerUpload, view: DesktopPeerUploadView) async throws -> DesktopPeerProposal { proposal }
    func view(deviceID: UUID, projectID: UUID, proposalID: UUID, grantSelection: CorpusSelection) async throws -> DesktopPeerUploadView? { uploadView }
    func acknowledge(deviceID: UUID, projectID: UUID, proposalID: UUID, view: DesktopPeerUploadView) async throws {}
}
