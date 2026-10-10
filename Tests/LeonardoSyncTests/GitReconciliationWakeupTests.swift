import XCTest
@testable import LeonardoSync

final class GitReconciliationWakeupTests: XCTestCase {
    func testSourceGrantCoversGitFolderOnlyThroughAnAuthorizedFolder() throws {
        let root = try CorpusScope(folder: "")
        let docs = try CorpusScope(folder: "docs")
        let nested = try CorpusScope(folder: "docs/nested")
        let code = try CorpusScope(folder: "code")
        let sibling = try CorpusScope(folder: "documentation")

        let selectedDocs = SharedProjectDescriptor(
            id: UUID(), name: "Docs", scope: root,
            selection: try CorpusSelection(folders: ["docs"], documents: []))
        XCTAssertTrue(selectedDocs.allowsGitScope(docs))
        XCTAssertTrue(selectedDocs.allowsGitScope(nested))
        XCTAssertFalse(selectedDocs.allowsGitScope(root))
        XCTAssertFalse(selectedDocs.allowsGitScope(code))
        XCTAssertFalse(selectedDocs.allowsGitScope(sibling))

        let selectedDocument = SharedProjectDescriptor(
            id: UUID(), name: "One file", scope: root,
            selection: try CorpusSelection(folders: [], documents: ["docs/read.md"]))
        XCTAssertFalse(selectedDocument.allowsGitScope(docs))
    }

    func testWakeupRequiresARealGitObjectID() throws {
        let scope = try CorpusScope(folder: "docs")
        XCTAssertThrowsError(try GitReconciliationWakeup(
            gitProjectID: UUID(), sourceProjectID: UUID(), gitDeviceID: UUID(),
            proposalCommitID: "not-a-commit", scope: scope))
        XCTAssertThrowsError(try GitReconciliationWakeup(
            gitProjectID: UUID(), sourceProjectID: UUID(), gitDeviceID: UUID(),
            proposalCommitID: String(repeating: "A", count: 40), scope: scope))
        XCTAssertNoThrow(try GitReconciliationWakeup(
            gitProjectID: UUID(), sourceProjectID: UUID(), gitDeviceID: UUID(),
            proposalCommitID: String(repeating: "a", count: 40), scope: scope))
    }

    func testAuthorizedReadOnlyDeviceCanPromptOnlyItsExactSourceGrant() async throws {
        var registry = PairingRegistry()
        registry.setEnabled(true)
        let credential = String(repeating: "a", count: 64)
        let fingerprint = Data(repeating: 1, count: 32)
        let now = Date(timeIntervalSince1970: 1_000)
        let request = try registry.requestPairing(deviceName: "Phone", credential: credential,
                                                  serverFingerprint: fingerprint, now: now)
        let source = SharedProjectDescriptor(id: UUID(), name: "Docs", scope: try CorpusScope(folder: "docs"))
        _ = try registry.approve(requestID: request.id, comparisonCode: request.comparisonCode,
                                 projects: [source.id], now: now)
        let sink = WakeupSink()
        let authority = try DirectSyncAuthority(
            registry: registry,
            projects: [SharedProjectSource(descriptor: source) { CorpusSnapshot(revision: "r", files: []) }],
            serverFingerprint: fingerprint,
            persist: { _ in },
            gitWakeup: { _, wakeup in await sink.receive(wakeup) })
        let wakeup = try GitReconciliationWakeup(
            gitProjectID: UUID(), sourceProjectID: source.id, gitDeviceID: UUID(),
            proposalCommitID: String(repeating: "b", count: 40), scope: source.scope)

        try await authority.notifyGitReconciliation(deviceID: request.id, credential: credential, wakeup: wakeup)
        let received = await sink.values()
        XCTAssertEqual(received, [wakeup])

        let wrongProject = try GitReconciliationWakeup(
            gitProjectID: wakeup.gitProjectID, sourceProjectID: UUID(), gitDeviceID: wakeup.gitDeviceID,
            proposalCommitID: wakeup.proposalCommitID, scope: wakeup.scope)
        do {
            try await authority.notifyGitReconciliation(deviceID: request.id, credential: credential, wakeup: wrongProject)
            XCTFail("An ungranted source project must not be notified")
        } catch {
            XCTAssertTrue(error is PairingError || error is SyncError)
        }
    }

    func testWakeupRejectsScopeCrossingEvenWhenProjectIsGranted() async throws {
        var registry = PairingRegistry()
        registry.setEnabled(true)
        let credential = String(repeating: "c", count: 64)
        let fingerprint = Data(repeating: 2, count: 32)
        let now = Date(timeIntervalSince1970: 1_000)
        let request = try registry.requestPairing(deviceName: "Phone", credential: credential,
                                                  serverFingerprint: fingerprint, now: now)
        let source = SharedProjectDescriptor(id: UUID(), name: "Docs", scope: try CorpusScope(folder: "docs"))
        _ = try registry.approve(requestID: request.id, comparisonCode: request.comparisonCode,
                                 projects: [source.id], now: now)
        let authority = try DirectSyncAuthority(
            registry: registry,
            projects: [SharedProjectSource(descriptor: source) { CorpusSnapshot(revision: "r", files: []) }],
            serverFingerprint: fingerprint,
            persist: { _ in })
        let wakeup = try GitReconciliationWakeup(
            gitProjectID: UUID(), sourceProjectID: source.id, gitDeviceID: UUID(),
            proposalCommitID: String(repeating: "d", count: 40), scope: try CorpusScope(folder: "other"))
        do {
            try await authority.notifyGitReconciliation(deviceID: request.id, credential: credential, wakeup: wakeup)
            XCTFail("A wakeup cannot cross the granted source scope")
        } catch {
            XCTAssertEqual(error as? SyncError, .outsideScope)
        }
    }
}

private actor WakeupSink {
    private var received: [GitReconciliationWakeup] = []

    func receive(_ wakeup: GitReconciliationWakeup) { received.append(wakeup) }
    func values() -> [GitReconciliationWakeup] { received }
}
