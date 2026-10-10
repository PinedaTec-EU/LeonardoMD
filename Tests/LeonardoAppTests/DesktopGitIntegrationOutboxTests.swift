#if os(macOS)
import XCTest
@testable import LeonardoApp
@testable import LeonardoGit
import LeonardoSync

final class DesktopGitIntegrationOutboxTests: XCTestCase {
    func testOutboxIsDurableAndExactPerProposal() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let projectRoot = root.appendingPathComponent("Project", isDirectory: true)
        try FileManager.default.createDirectory(at: projectRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let fixture = try makeFixture()
        let built = try GitIntegrationResult.buildCommit(receipt: fixture.receipt,
                                                          parentCommitID: fixture.receipt.commitID,
                                                          treeID: fixture.treeID,
                                                          identity: fixture.identity)
        let envelope = try GitIntegrationEnvelope(result: built.result, receipt: fixture.receipt)
        let entry = try DesktopGitIntegrationOutboxEntry(envelope: envelope,
                                                          projectRoot: projectRoot,
                                                          remoteName: "origin")
        let store = DesktopGitIntegrationOutboxStore(root: root.appendingPathComponent("Outbox"))
        try await store.save(entry)
        try await store.save(entry)

        let loaded = try await store.load(projectID: fixture.projectID, deviceID: fixture.deviceID,
                                          proposalCommitID: fixture.receipt.commitID)
        XCTAssertEqual(loaded, entry)
        let all = try await store.all()
        XCTAssertEqual(all, [entry])

        let permissions = try FileManager.default.attributesOfItem(atPath: root
            .appendingPathComponent("Outbox")
            .appendingPathComponent(fixture.projectID.uuidString)
            .appendingPathComponent(fixture.deviceID.uuidString)
            .appendingPathComponent(fixture.receipt.commitID).appendingPathExtension("json").path)
        XCTAssertEqual((permissions[.posixPermissions] as? NSNumber)?.intValue, 0o600)

        let otherIdentity = try GitCommitIdentity(name: "Other Fixture",
                                                  email: "fixture@example.invalid", timestamp: 2)
        let otherBuilt = try GitIntegrationResult.buildCommit(receipt: fixture.receipt,
                                                               parentCommitID: fixture.receipt.commitID,
                                                               treeID: fixture.treeID,
                                                               identity: otherIdentity)
        let other = try DesktopGitIntegrationOutboxEntry(
            envelope: GitIntegrationEnvelope(result: otherBuilt.result, receipt: fixture.receipt),
            projectRoot: projectRoot, remoteName: "origin")
        do {
            try await store.save(other)
            XCTFail("A different integration commit replaced the pending exact proposal")
        } catch {
            XCTAssertEqual(error as? SyncError, .publicationPending)
        }

        try await store.remove(projectID: fixture.projectID, deviceID: fixture.deviceID,
                               proposalCommitID: fixture.receipt.commitID)
        let removed = try await store.load(projectID: fixture.projectID, deviceID: fixture.deviceID,
                                           proposalCommitID: fixture.receipt.commitID)
        XCTAssertNil(removed)
    }

    func testOutboxRequiresCanonicalIntegrationRefAndRemoteName() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let projectRoot = root.appendingPathComponent("Project", isDirectory: true)
        try FileManager.default.createDirectory(at: projectRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let fixture = try makeFixture()
        let built = try GitIntegrationResult.buildCommit(receipt: fixture.receipt,
                                                          parentCommitID: fixture.receipt.commitID,
                                                          treeID: fixture.treeID,
                                                          identity: fixture.identity)
        let envelope = try GitIntegrationEnvelope(result: built.result, receipt: fixture.receipt)
        XCTAssertThrowsError(try DesktopGitIntegrationOutboxEntry(envelope: envelope,
                                                                   projectRoot: projectRoot,
                                                                   remoteName: "-origin"))
        XCTAssertThrowsError(try DesktopGitIntegrationOutboxEntry(envelope: envelope,
                                                                   projectRoot: projectRoot,
                                                                   remoteName: "origin",
                                                                   localRef: "refs/heads/main"))
    }

    private struct Fixture {
        let projectID: UUID
        let deviceID: UUID
        let receipt: GitIntegrationReceipt
        let parentID: String
        let treeID: String
        let identity: GitCommitIdentity
    }

    private func makeFixture() throws -> Fixture {
        let projectID = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
        let deviceID = UUID(uuidString: "22222222-2222-4222-8222-222222222222")!
        let proposalID = String(repeating: "a", count: 40)
        let scope = try CorpusScope(folder: "docs")
        let accepted = CorpusSnapshot(revision: proposalID, files: [
            CorpusFile(path: "docs/note.md", content: Data("merged".utf8))
        ])
        let receipt = try GitIntegrationReceipt(
            projectID: projectID, deviceID: deviceID,
            branch: GitDeviceBranch.name(deviceID: deviceID, projectID: projectID),
            commitID: proposalID, baseRevision: proposalID,
            scope: scope, accepted: accepted)
        return Fixture(projectID: projectID, deviceID: deviceID, receipt: receipt,
                       parentID: String(repeating: "b", count: 40),
                       treeID: String(repeating: "c", count: 40),
                       identity: try GitCommitIdentity(name: "Fixture",
                                                       email: "fixture@example.invalid", timestamp: 1))
    }
}
#endif
