import XCTest
@testable import LeonardoSync

final class DirectSyncAuthorityTests: XCTestCase {
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
    func begin(deviceID: UUID, upload: DesktopPeerUpload, selection: CorpusSelection) async throws -> Int {
        _ = await gate.read(); return 0
    }
    func append(deviceID: UUID, upload: DesktopPeerUpload, offset: Int, bytes: Data, selection: CorpusSelection) async throws -> Int { throw SyncError.invalidSnapshot }
    func submit(deviceID: UUID, upload: DesktopPeerUpload, selection: CorpusSelection) async throws { throw SyncError.invalidSnapshot }
    func pending(deviceID: UUID, projectID: UUID, selection: CorpusSelection) async throws -> DesktopPeerUpload? { nil }
    func finish(deviceID: UUID, upload: DesktopPeerUpload, selection: CorpusSelection) async throws -> DesktopPeerProposal { throw SyncError.invalidSnapshot }
}
