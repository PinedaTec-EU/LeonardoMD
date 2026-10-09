import XCTest
@testable import LeonardoGit
import LeonardoSync

final class GitDesktopIntegrationTests: XCTestCase {
    func testPublishedBranchDiscoveryAndExactProposalUseOnlySelectedBlobs() async throws {
        for sha256 in [false, true] {
            let fixture = try makeFixture(sha256: sha256)
            let transport = ProposalTransport(fixture: fixture)
            let reader = GitRemoteReader(transport: transport)
            let discovery = try await reader.discover()
            let branches = try reader.publishedBranches(from: discovery, projectID: fixture.projectID)
            XCTAssertEqual(branches.count, 1)
            let branch = try XCTUnwrap(branches.first)
            XCTAssertEqual(branch.deviceID, fixture.deviceID)
            XCTAssertEqual(branch.projectID, fixture.projectID)
            XCTAssertEqual(branch.commitID, fixture.commitID)

            let proposal = try await reader.publishedProposal(branch, discovery: discovery)
            XCTAssertEqual(proposal.commitID, fixture.commitID)
            XCTAssertEqual(proposal.baseRevision, fixture.baseRevision)
            XCTAssertEqual(proposal.scope, fixture.scope)
            XCTAssertFalse(proposal.repository.objects.contains { $0.kind == .blob })
            XCTAssertEqual(proposal.snapshot.files.map(\.path), ["docs/keep.md", "docs/note.md"])
            XCTAssertEqual(proposal.snapshot.files.first(where: { $0.path == "docs/note.md" })?.content,
                           Data("remote edit".utf8))

            let requests = await transport.requests
            XCTAssertEqual(requests.count, 3)
            let metadataRequest = String(decoding: requests[1], as: UTF8.self)
            XCTAssertTrue(metadataRequest.contains("want \(fixture.commitID)\n"))
            XCTAssertTrue(metadataRequest.contains("filter blob:none\n"))
            XCTAssertFalse(metadataRequest.contains("want \(fixture.remoteBlobID)\n"))
            let selectedRequest = String(decoding: requests[2], as: UTF8.self)
            XCTAssertTrue(selectedRequest.contains("want \(fixture.remoteBlobID)\n"))
            XCTAssertTrue(selectedRequest.contains("want \(fixture.unchangedBlobID)\n"))
        }
    }

    func testManualReviewProducesReceiptBoundToCommitAndRejectsStaleInputs() async throws {
        for sha256 in [false, true] {
            let fixture = try makeFixture(sha256: sha256)
            let transport = ProposalTransport(fixture: fixture)
            let reader = GitRemoteReader(transport: transport)
            let discovery = try await reader.discover()
            let discovered = try reader.publishedBranches(from: discovery)
            let branch = try XCTUnwrap(discovered.first)
            let proposal = try await reader.publishedProposal(branch, discovery: discovery)

            let local = CorpusSnapshot(revision: fixture.baseRevision, files: [
                CorpusFile(path: "docs/keep.md", content: Data("keep".utf8)),
                CorpusFile(path: "docs/note.md", content: Data("desktop edit".utf8))
            ])
            let review = try GitIntegrationReview(proposal: proposal, base: fixture.baseSnapshot, local: local)
            XCTAssertEqual(review.differences.map(\.path), ["docs/note.md"])
            let receipt = try review.resolve(["docs/note.md": .remote], currentLocal: local,
                                             currentRemote: proposal.snapshot)
            XCTAssertEqual(receipt.projectID, fixture.projectID)
            XCTAssertEqual(receipt.deviceID, fixture.deviceID)
            XCTAssertEqual(receipt.branch, fixture.branch)
            XCTAssertEqual(receipt.commitID, fixture.commitID)
            XCTAssertEqual(receipt.baseRevision, fixture.baseRevision)
            XCTAssertEqual(receipt.scope, fixture.scope)
            XCTAssertEqual(receipt.accepted.revision, fixture.commitID)
            XCTAssertEqual(receipt.accepted.files.first(where: { $0.path == "docs/note.md" })?.content,
                           Data("remote edit".utf8))

            var stale = local
            stale = CorpusSnapshot(revision: stale.revision, files: [
                CorpusFile(path: "docs/keep.md", content: Data("keep".utf8)),
                CorpusFile(path: "docs/note.md", content: Data("changed after review".utf8))
            ])
            XCTAssertThrowsError(try review.resolve(["docs/note.md": .remote], currentLocal: stale,
                                                    currentRemote: proposal.snapshot)) { error in
                XCTAssertEqual(error as? ReconciliationError, .staleComparison)
            }

            // A later branch tip has no authority over this receipt.
            let advancedID = String(repeating: sha256 ? "b" : "a", count: sha256 ? 64 : 40)
            let advanced = try GitPublishedBranch(name: fixture.branch, commitID: advancedID)
            XCTAssertEqual(advanced.name, receipt.branch)
            XCTAssertEqual(receipt.commitID, fixture.commitID)
            XCTAssertNotEqual(receipt.commitID, advanced.commitID)
        }
    }

    func testReceiptStoreIsImmutableAndKeyedByExactCommit() async throws {
        let fixture = try makeFixture(sha256: false)
        let transport = ProposalTransport(fixture: fixture)
        let reader = GitRemoteReader(transport: transport)
        let discovery = try await reader.discover()
        let discovered = try reader.publishedBranches(from: discovery)
        let branch = try XCTUnwrap(discovered.first)
        let proposal = try await reader.publishedProposal(branch, discovery: discovery)
        let review = try GitIntegrationReview(proposal: proposal, base: fixture.baseSnapshot, local: fixture.baseSnapshot)
        let decisions = Dictionary(uniqueKeysWithValues: review.differences.map { ($0.path, ReconciliationChoice.remote) })
        let receipt = try review.resolve(decisions, currentLocal: fixture.baseSnapshot, currentRemote: proposal.snapshot)

        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = GitIntegrationReceiptStore(root: root)
        try await store.save(receipt)
        try await store.save(receipt)
        let loaded = try await store.load(projectID: fixture.projectID, deviceID: fixture.deviceID,
                                          commitID: fixture.commitID)
        XCTAssertEqual(loaded, receipt)
        let path = root.appendingPathComponent(fixture.projectID.uuidString)
            .appendingPathComponent(fixture.deviceID.uuidString)
            .appendingPathComponent(fixture.commitID).appendingPathExtension("json")
        XCTAssertEqual((try FileManager.default.attributesOfItem(atPath: path.path)[.posixPermissions] as? NSNumber)?.intValue,
                       0o600)

        let changed = try GitIntegrationReceipt(projectID: receipt.projectID, deviceID: receipt.deviceID,
                                                branch: receipt.branch, commitID: receipt.commitID,
                                                baseRevision: receipt.baseRevision, scope: receipt.scope,
                                                accepted: CorpusSnapshot(revision: receipt.commitID, files: []))
        do {
            try await store.save(changed)
            XCTFail("An exact receipt was replaced")
        } catch {
            XCTAssertEqual(error as? SyncError, .publicationPending)
        }
    }

    func testPublicationMetadataRoundTripsAndHashTamperingIsRejectedForBothFormats() throws {
        for sha256 in [false, true] {
            let fixture = try makeFixture(sha256: sha256)
            let publication = try GitPublicationMetadata.parse(commit: fixture.built.commit,
                                                               expectedCommitID: fixture.commitID)
            XCTAssertEqual(publication.projectID, fixture.projectID)
            XCTAssertEqual(publication.deviceID, fixture.deviceID)
            XCTAssertEqual(publication.baseRevision, fixture.baseRevision)
            XCTAssertEqual(publication.scope, fixture.scope)

            var tamperedData = fixture.built.commit.data
            tamperedData.append(0x20)
            let tampered = GitObject(id: fixture.commitID, kind: .commit, data: tamperedData)
            XCTAssertThrowsError(try GitPublicationMetadata.parse(commit: tampered))

            let commitText = try XCTUnwrap(String(data: fixture.built.commit.data, encoding: .utf8))
            let replacement = String(repeating: "c", count: sha256 ? 64 : 40)
            let wrongText = commitText.replacingOccurrences(of: "parent \(fixture.baseRevision)\n",
                                                            with: "parent \(replacement)\n")
            let wrongParent = Data(wrongText.utf8)
            let wrong = GitObject.create(kind: .commit, data: wrongParent, sha256: sha256)
            XCTAssertThrowsError(try GitPublicationMetadata.parse(commit: wrong))
        }
    }

    #if os(macOS)
    func testPublishedProposalAgainstLocalGitCLIFixtureForBothObjectFormats() async throws {
        for sha256 in [false, true] {
            let fixture = try makeFixture(sha256: sha256)
            let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: root) }
            _ = try runGit(["init", "--bare", "--quiet", "--object-format=\(sha256 ? "sha256" : "sha1")", root.path])
            let allObjects = fixture.metadataObjects + fixture.selectedBlobs
            _ = try runGit(["-C", root.path, "index-pack", "--stdin"],
                           input: try GitPackWriter.encode(objects: allObjects, sha256: sha256))
            _ = try runGit(["-C", root.path, "update-ref", fixture.branch, fixture.commitID])
            _ = try runGit(["-C", root.path, "config", "uploadpack.allowFilter", "true"])
            _ = try runGit(["-C", root.path, "config", "uploadpack.allowReachableSHA1InWant", "true"])

            let reader = GitRemoteReader(transport: CLIGitUploadTransport(root: root.path))
            let discovery = try await reader.discover()
            let discovered = try reader.publishedBranches(from: discovery)
            let branch = try XCTUnwrap(discovered.first)
            let proposal = try await reader.publishedProposal(branch, discovery: discovery)
            XCTAssertEqual(proposal.commitID, fixture.commitID)
            XCTAssertEqual(proposal.snapshot.files.first(where: { $0.path == "docs/note.md" })?.content,
                           Data("remote edit".utf8))
            XCTAssertFalse(proposal.repository.objects.contains { $0.kind == .blob })
        }
    }
    #endif

    struct Fixture: Sendable {
        let projectID: UUID
        let deviceID: UUID
        let scope: CorpusScope
        let branch: String
        let baseRevision: String
        let commitID: String
        let treeID: String
        let remoteBlobID: String
        let unchangedBlobID: String
        let baseSnapshot: CorpusSnapshot
        let built: GitBuiltCommit
        let metadataObjects: [GitObject]
        let selectedBlobs: [GitObject]
    }

    private func makeFixture(sha256: Bool) throws -> Fixture {
        let projectID = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
        let deviceID = UUID(uuidString: "22222222-2222-4222-8222-222222222222")!
        let scope = try CorpusScope(folder: "docs")
        let oldBlob = GitObject.create(kind: .blob, data: Data("old".utf8), sha256: sha256)
        let unchangedBlob = GitObject.create(kind: .blob, data: Data("keep".utf8), sha256: sha256)
        let docs = try GitTree.create(entries: [
            GitTreeEntry(name: "keep.md", objectID: unchangedBlob.id, kind: .file, executable: false),
            GitTreeEntry(name: "note.md", objectID: oldBlob.id, kind: .file, executable: false)
        ], sha256: sha256)
        let outside = GitObject.create(kind: .blob, data: Data("outside".utf8), sha256: sha256)
        let root = try GitTree.create(entries: [
            GitTreeEntry(name: "docs", objectID: docs.id, kind: .folder, executable: false),
            GitTreeEntry(name: "outside.bin", objectID: outside.id, kind: .file, executable: false)
        ], sha256: sha256)
        let baseCommitText = "tree \(root.id)\nauthor Fixture <fixture@example.invalid> 1 +0000\n"
            + "committer Fixture <fixture@example.invalid> 1 +0000\n\nbase\n"
        let baseCommit = GitObject.create(kind: .commit, data: Data(baseCommitText.utf8), sha256: sha256)
        let baseline = try GitBaseline(commitID: baseCommit.id, objects: [baseCommit, root, docs])
        let baseSnapshot = CorpusSnapshot(revision: baseCommit.id, files: [
            CorpusFile(path: "docs/keep.md", content: unchangedBlob.data),
            CorpusFile(path: "docs/note.md", content: oldBlob.data)
        ])
        var project = try OfflineProject(id: projectID, name: "Fixture", mode: .git, scope: scope,
                                         snapshot: baseSnapshot)
        try project.write(path: "docs/note.md", content: Data("remote edit".utf8))
        let metadata = try GitPublicationMetadata(projectID: projectID, deviceID: deviceID,
                                                  baseRevision: baseCommit.id, scope: scope)
        let identity = try GitCommitIdentity(name: "Mobile Fixture", email: "fixture@example.invalid", timestamp: 2)
        let built = try GitCommitBuilder.build(project: project, baseline: baseline, identity: identity,
                                               publication: metadata)
        let branch = GitDeviceBranch.name(deviceID: deviceID, projectID: projectID)
        let changedBlob = try XCTUnwrap(built.objects.first(where: {
            $0.kind == .blob && $0.data == Data("remote edit".utf8)
        }))
        let metadataObjects = (baseline.objects + built.objects).filter { $0.kind != .blob }
        return Fixture(projectID: projectID, deviceID: deviceID, scope: scope, branch: branch,
                       baseRevision: baseCommit.id, commitID: built.commit.id, treeID: root.id,
                       remoteBlobID: changedBlob.id, unchangedBlobID: unchangedBlob.id,
                       baseSnapshot: baseSnapshot, built: built, metadataObjects: metadataObjects,
                       selectedBlobs: [changedBlob, unchangedBlob])
    }
}

#if os(macOS)
private actor CLIGitUploadTransport: GitRemoteTransport {
    let root: String
    init(root: String) { self.root = root }

    func advertisement() async throws -> Data {
        try runGit(["upload-pack", "--stateless-rpc", "--advertise-refs", root])
    }

    func uploadPack(request: Data) async throws -> Data {
        try runGit(["upload-pack", "--stateless-rpc", root], input: request)
    }
}

private func runGit(_ arguments: [String], input: Data? = nil) throws -> Data {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
    process.arguments = arguments
    process.environment = ProcessInfo.processInfo.environment.merging([
        "GIT_PROTOCOL": "version=2",
        "GIT_CONFIG_NOSYSTEM": "1",
        "GIT_CONFIG_GLOBAL": "/dev/null"
    ]) { _, new in new }
    let output = Pipe()
    let stdin = Pipe()
    process.standardOutput = output
    process.standardError = FileHandle.nullDevice
    process.standardInput = input == nil ? FileHandle.nullDevice : stdin
    try process.run()
    if let input {
        try stdin.fileHandleForWriting.write(contentsOf: input)
        try stdin.fileHandleForWriting.close()
    }
    let result = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else { throw GitWireError.remoteFailure }
    return result
}
#endif

private actor ProposalTransport: GitRemoteTransport {
    let fixture: GitDesktopIntegrationTests.Fixture
    private(set) var requests: [Data] = []

    init(fixture: GitDesktopIntegrationTests.Fixture) { self.fixture = fixture }

    func advertisement() async throws -> Data {
        var output = Data()
        let format = fixture.commitID.count == 64 ? "sha256" : "sha1"
        for line in ["version 2", "ls-refs", "fetch=shallow filter", "object-format=\(format)"] {
            output += try GitPacket.data(Data((line + "\n").utf8)).encoded()
        }
        output += try GitPacket.flush.encoded()
        return output
    }

    func uploadPack(request: Data) async throws -> Data {
        requests.append(request)
        let text = String(decoding: request, as: UTF8.self)
        if text.contains("command=ls-refs\n") {
            return try GitPacket.data(Data("\(fixture.commitID) \(fixture.branch)\n".utf8)).encoded()
                + GitPacket.flush.encoded()
        }
        if text.contains("want \(fixture.commitID)\n") {
            return try fetchResponse(objects: fixture.metadataObjects, shallow: fixture.commitID,
                                     sha256: fixture.commitID.count == 64)
        }
        if text.contains("want \(fixture.remoteBlobID)\n") {
            return try fetchResponse(objects: fixture.selectedBlobs, shallow: nil,
                                     sha256: fixture.commitID.count == 64)
        }
        throw GitWireError.invalidFetchResponse
    }

    private func fetchResponse(objects: [GitObject], shallow: String?, sha256: Bool) throws -> Data {
        var output = Data()
        if let shallow {
            output += try GitPacket.data(Data("shallow-info\n".utf8)).encoded()
            output += try GitPacket.data(Data("shallow \(shallow)\n".utf8)).encoded()
            output += try GitPacket.delimiter.encoded()
        }
        output += try GitPacket.data(Data("packfile\n".utf8)).encoded()
        output += try GitPacket.data(Data([1]) + GitPackWriter.encode(objects: objects, sha256: sha256)).encoded()
        output += try GitPacket.flush.encoded()
        return output
    }
}
