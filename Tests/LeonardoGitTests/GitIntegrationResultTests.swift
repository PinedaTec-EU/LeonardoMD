import Foundation
import XCTest
@testable import LeonardoGit
import LeonardoSync

final class GitIntegrationResultTests: XCTestCase {
    func testBuildParseAndValidateUsesRealIntegrationCommitForBothObjectFormats() throws {
        for sha256 in [false, true] {
            let fixture = try makeFixture(sha256: sha256)
            let built = try GitIntegrationResult.buildCommit(receipt: fixture.receipt,
                                                              parentCommitID: fixture.receipt.commitID,
                                                              treeID: fixture.treeID,
                                                              identity: fixture.identity)

            XCTAssertEqual(built.commit.id, built.result.integrationCommitID)
            XCTAssertNotEqual(built.result.integrationCommitID, fixture.receipt.commitID)
            XCTAssertEqual(built.result.proposalCommitID, fixture.receipt.commitID)
            XCTAssertEqual(built.result.parentCommitID, fixture.receipt.commitID)
            XCTAssertEqual(built.result.sourceRevision, fixture.receipt.baseRevision)
            XCTAssertEqual(built.result.treeID, fixture.treeID)
            XCTAssertEqual(built.result.acceptedDigest, CorpusRevision.make(files: fixture.accepted.files))
            XCTAssertThrowsError(try GitIntegrationResult.buildCommit(
                receipt: fixture.receipt, parentCommitID: fixture.parentID,
                treeID: fixture.treeID, identity: fixture.identity))

            let parsed = try GitIntegrationResult.parse(commit: built.commit,
                                                        expectedCommitID: built.commit.id)
            XCTAssertEqual(parsed, built.result)
            XCTAssertEqual(try built.result.commitData(identity: fixture.identity), built.commit.data)

            let fetched = CorpusSnapshot(revision: built.result.integrationCommitID,
                                         files: fixture.accepted.files)
            try built.result.validate(accepted: fetched)

            let wrongRevision = CorpusSnapshot(revision: fixture.receipt.commitID,
                                               files: fixture.accepted.files)
            XCTAssertThrowsError(try built.result.validate(accepted: wrongRevision))

            var changedFiles = fixture.accepted.files
            changedFiles[0] = CorpusFile(path: changedFiles[0].path, content: Data("changed".utf8))
            let changed = CorpusSnapshot(revision: built.result.integrationCommitID, files: changedFiles)
            XCTAssertThrowsError(try built.result.validate(accepted: changed))

            let envelope = try GitIntegrationEnvelope(result: built.result, receipt: fixture.receipt)
            XCTAssertEqual(envelope.integrationRef.name, GitIntegrationRef.name(
                deviceID: fixture.deviceID, projectID: fixture.projectID,
                proposalCommitID: fixture.receipt.commitID))
            let encoded = try JSONEncoder().encode(envelope)
            XCTAssertEqual(try JSONDecoder().decode(GitIntegrationEnvelope.self, from: encoded), envelope)
        }
    }

    func testIntegrationRefDiscoveryKeepsExactProposalAndIntegrationObjectIDs() throws {
        let fixture = try makeFixture(sha256: false)
        let result = try GitIntegrationResult.buildCommit(receipt: fixture.receipt,
                                                           parentCommitID: fixture.receipt.commitID,
                                                           treeID: fixture.treeID,
                                                           identity: fixture.identity).result
        let reference = GitReference(name: result.integrationRef.name,
                                     objectID: result.integrationCommitID,
                                     symbolicTarget: nil)
        let ordinary = GitReference(name: "refs/heads/main",
                                    objectID: String(repeating: "d", count: 40),
                                    symbolicTarget: nil)
        let discovery = GitRemoteDiscovery(capabilities: fixture.capabilities,
                                            references: [ordinary, reference])
        let integrations = try GitRemoteReader(transport: fixture.transport)
            .integrationRefs(from: discovery, projectID: fixture.projectID)
        XCTAssertEqual(integrations, [result.integrationRef])
        XCTAssertEqual(integrations[0].proposalCommitID, fixture.receipt.commitID)

        let malformed = GitReference(name: result.integrationRef.name,
                                     objectID: String(repeating: "e", count: 64),
                                     symbolicTarget: nil)
        XCTAssertThrowsError(try GitIntegrationRef.parse(malformed))
    }

    func testCodableDecodingRequiresExplicitSourceRevisionForBothObjectFormats() throws {
        for sha256 in [false, true] {
            let fixture = try makeFixture(sha256: sha256)
            let built = try GitIntegrationResult.buildCommit(receipt: fixture.receipt,
                                                              parentCommitID: fixture.receipt.commitID,
                                                              treeID: fixture.treeID,
                                                              identity: fixture.identity)
            let encoded = try JSONEncoder().encode(built.result)
            var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
            object.removeValue(forKey: "sourceRevision")
            let missing = try JSONSerialization.data(withJSONObject: object)
            XCTAssertThrowsError(try JSONDecoder().decode(GitIntegrationResult.self, from: missing),
                                 "Missing sourceRevision must not fall back to baseRevision for SHA-\(sha256 ? 256 : 1)")
        }
    }

    func testEnvelopeRejectsReceiptWithDifferentScopeOrDraftBytes() throws {
        let fixture = try makeFixture(sha256: false)
        let built = try GitIntegrationResult.buildCommit(receipt: fixture.receipt,
                                                          parentCommitID: fixture.receipt.commitID,
                                                          treeID: fixture.treeID,
                                                          identity: fixture.identity)
        let otherScope = try CorpusScope(folder: "other")
        let otherAccepted = CorpusSnapshot(revision: fixture.receipt.commitID, files: [
            CorpusFile(path: "other/note.md", content: Data("other".utf8))
        ])
        let mismatched = try GitIntegrationReceipt(projectID: fixture.projectID,
                                                   deviceID: fixture.deviceID,
                                                   branch: fixture.receipt.branch,
                                                   commitID: fixture.receipt.commitID,
                                                   baseRevision: fixture.receipt.baseRevision,
                                                   scope: otherScope,
                                                   accepted: otherAccepted)
        XCTAssertThrowsError(try GitIntegrationEnvelope(result: built.result, receipt: mismatched))

        let draft = CorpusSnapshot(revision: fixture.receipt.commitID, files: [
            CorpusFile(path: "docs/note.md", content: Data("draft".utf8), isUnsavedBuffer: true)
        ])
        let draftReceipt = try GitIntegrationReceipt(projectID: fixture.projectID,
                                                      deviceID: fixture.deviceID,
                                                      branch: fixture.receipt.branch,
                                                      commitID: fixture.receipt.commitID,
                                                      baseRevision: fixture.receipt.baseRevision,
                                                      scope: fixture.receipt.scope,
                                                      accepted: draft)
        XCTAssertThrowsError(try GitIntegrationResult(receipt: draftReceipt,
                                                       integrationCommitID: fixture.parentID,
                                                       parentCommitID: fixture.parentID,
                                                       treeID: fixture.treeID))
    }

    private struct Fixture {
        let projectID: UUID
        let deviceID: UUID
        let receipt: GitIntegrationReceipt
        let accepted: CorpusSnapshot
        let parentID: String
        let treeID: String
        let identity: GitCommitIdentity
        let capabilities: GitV2Capabilities
        let transport: EmptyTransport
    }

    private func makeFixture(sha256: Bool) throws -> Fixture {
        let projectID = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
        let deviceID = UUID(uuidString: "22222222-2222-4222-8222-222222222222")!
        let scope = try CorpusScope(folder: "docs")
        let idLength = sha256 ? 64 : 40
        let proposalID = String(repeating: "a", count: idLength)
        let parentID = String(repeating: "b", count: idLength)
        let treeID = String(repeating: "c", count: idLength)
        let accepted = CorpusSnapshot(revision: proposalID, files: [
            CorpusFile(path: "docs/keep.md", content: Data("keep".utf8)),
            CorpusFile(path: "docs/note.md", content: Data("merged".utf8)),
        ])
        let branch = GitDeviceBranch.name(deviceID: deviceID, projectID: projectID)
        let receipt = try GitIntegrationReceipt(projectID: projectID, deviceID: deviceID,
                                                branch: branch, commitID: proposalID,
                                                baseRevision: proposalID, scope: scope,
                                                accepted: accepted)
        let identity = try GitCommitIdentity(name: "Desktop Fixture",
                                             email: "fixture@example.invalid", timestamp: 1_700_000_000)
        var advertisement = Data()
        for line in ["version 2", "ls-refs", "fetch=shallow filter",
                     "object-format=\(sha256 ? "sha256" : "sha1")"] {
            advertisement += try GitPacket.data(Data((line + "\n").utf8)).encoded()
        }
        advertisement += try GitPacket.flush.encoded()
        let capabilities = try GitV2Capabilities(advertisement: advertisement)
        return Fixture(projectID: projectID, deviceID: deviceID, receipt: receipt,
                       accepted: accepted, parentID: parentID, treeID: treeID,
                       identity: identity, capabilities: capabilities,
                       transport: EmptyTransport())
    }
}

private actor EmptyTransport: GitRemoteTransport {
    func advertisement() async throws -> Data { throw GitWireError.remoteFailure }
    func uploadPack(request: Data) async throws -> Data { throw GitWireError.remoteFailure }
}
