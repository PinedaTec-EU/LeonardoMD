import XCTest
@testable import LeonardoSync

final class DirectSyncAuthorityTests: XCTestCase {
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
