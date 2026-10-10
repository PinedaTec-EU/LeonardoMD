import XCTest
@testable import LeonardoGit
import LeonardoSync

final class GitIntegrationConsumerTests: XCTestCase {
    func testIntegratedBaselineConsumesExplicitNormalBranchAdvanceAfterFreezeRegression() async throws {
        let projectID = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
        let deviceID = UUID(uuidString: "22222222-2222-4222-8222-222222222222")!
        let scope = try CorpusScope(folder: "docs")
        let identity = try GitCommitIdentity(name: "Fixture", email: "fixture@example.invalid", timestamp: 10)

        let sourceBlob = GitObject.create(kind: .blob, data: Data("source".utf8))
        let sourceDocs = try GitTree.create(entries: [
            GitTreeEntry(name: "note.md", objectID: sourceBlob.id, kind: .file, executable: false)
        ], sha256: false)
        let sourceTree = try GitTree.create(entries: [
            GitTreeEntry(name: "docs", objectID: sourceDocs.id, kind: .folder, executable: false),
            GitTreeEntry(name: "outside.md", objectID: sourceBlob.id, kind: .file, executable: false)
        ], sha256: false)
        let sourceRevision = makeCommit(treeID: sourceTree.id, parentID: nil, message: "desktop source")

        let proposalID = String(repeating: "b", count: 40)
        let accepted = CorpusSnapshot(revision: proposalID, files: [
            CorpusFile(path: "docs/note.md", content: Data("desktop resolution".utf8))
        ])
        let receipt = try GitIntegrationReceipt(
            projectID: projectID,
            deviceID: deviceID,
            branch: GitDeviceBranch.name(deviceID: deviceID, projectID: projectID),
            commitID: proposalID,
            baseRevision: sourceRevision.id,
            scope: scope,
            accepted: accepted)
        let acceptedBlob = GitObject.create(kind: .blob, data: Data("desktop resolution".utf8))
        let integrationDocs = try GitTree.create(entries: [
            GitTreeEntry(name: "note.md", objectID: acceptedBlob.id, kind: .file, executable: false)
        ], sha256: false)
        let integrationTree = try GitTree.create(entries: [
            GitTreeEntry(name: "docs", objectID: integrationDocs.id, kind: .folder, executable: false),
            GitTreeEntry(name: "outside.md", objectID: sourceBlob.id, kind: .file, executable: false)
        ], sha256: false)
        let integration = try GitIntegrationResult.buildCommit(
            receipt: receipt,
            parentCommitID: proposalID,
            treeID: integrationTree.id,
            identity: identity,
            sourceRevision: sourceRevision.id)

        let laterBlob = acceptedBlob
        let laterOutsideBlob = GitObject.create(kind: .blob, data: Data("later outside".utf8))
        let laterDocs = try GitTree.create(entries: [
            GitTreeEntry(name: "note.md", objectID: laterBlob.id, kind: .file, executable: false)
        ], sha256: false)
        let laterTree = try GitTree.create(entries: [
            GitTreeEntry(name: "docs", objectID: laterDocs.id, kind: .folder, executable: false),
            GitTreeEntry(name: "outside.md", objectID: laterOutsideBlob.id, kind: .file, executable: false)
        ], sha256: false)
        let laterSource = makeCommit(treeID: laterTree.id, parentID: sourceRevision.id,
                                     message: "desktop later")
        let integrationRef = integration.result.integrationRef
        let transport = IntegrationConsumerTransport(
            integrationRef: integrationRef,
            integrationCommit: integration.commit,
            integrationTrees: [integrationTree, integrationDocs],
            sourceBranch: "refs/heads/main",
            sourceCommit: laterSource,
            sourceTrees: [laterTree, laterDocs, sourceTree, sourceDocs, sourceRevision],
            selectedBlob: laterBlob)
        let reader = GitRemoteReader(transport: transport)
        let project = try OfflineProject(id: projectID, name: "Fixture", mode: .git,
                                         scope: scope, snapshot: acceptedSnapshot(integration: integration, accepted: accepted))
        let connection = try GitProjectConnection(projectID: projectID,
                                                  endpoint: URL(string: "https://example.invalid/repo.git")!,
                                                  branch: "refs/heads/main", scope: scope)

        let outcome = try await GitIntegrationConsumer(reader: reader, deviceID: deviceID)
            .consume(project, connection: connection)
        guard case let .consumed(updated, baseline) = outcome else {
            return XCTFail("An explicit normal branch advance was left permanently frozen: \(String(describing: outcome))")
        }
        XCTAssertEqual(updated.base.revision, laterSource.id)
        XCTAssertEqual(updated.files.first?.content, Data("desktop resolution".utf8))
        XCTAssertEqual(baseline.commitID, laterSource.id)

        let requests = await transport.requests
        XCTAssertTrue(requests.contains { request in
            let text = String(decoding: request, as: UTF8.self)
            return text.contains("want \(laterSource.id)\n") && text.contains("deepen 256\n")
        })
        let selectedIndex = try XCTUnwrap(requests.firstIndex { request in
            String(decoding: request, as: UTF8.self).contains("want \(laterBlob.id)\n")
        })
        let metadataIndex = try XCTUnwrap(requests.firstIndex { request in
            String(decoding: request, as: UTF8.self).contains("want \(laterSource.id)\n")
        })
        XCTAssertGreaterThan(selectedIndex, metadataIndex)
    }

    func testSourceAdvanceThatLeavesAcceptedPathOldRequiresReconciliation() async throws {
        let projectID = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
        let deviceID = UUID(uuidString: "22222222-2222-4222-8222-222222222222")!
        let scope = try CorpusScope(folder: "docs")
        let identity = try GitCommitIdentity(name: "Fixture", email: "fixture@example.invalid", timestamp: 10)
        let sourceBlob = GitObject.create(kind: .blob, data: Data("source".utf8))
        let sourceDocs = try GitTree.create(entries: [
            GitTreeEntry(name: "note.md", objectID: sourceBlob.id, kind: .file, executable: false)
        ], sha256: false)
        let sourceTree = try GitTree.create(entries: [
            GitTreeEntry(name: "docs", objectID: sourceDocs.id, kind: .folder, executable: false)
        ], sha256: false)
        let sourceRevision = makeCommit(treeID: sourceTree.id, parentID: nil, message: "desktop source")
        let proposalID = String(repeating: "b", count: 40)
        let accepted = CorpusSnapshot(revision: proposalID, files: [
            CorpusFile(path: "docs/note.md", content: Data("desktop resolution".utf8))
        ])
        let receipt = try GitIntegrationReceipt(
            projectID: projectID, deviceID: deviceID,
            branch: GitDeviceBranch.name(deviceID: deviceID, projectID: projectID),
            commitID: proposalID, baseRevision: sourceRevision.id,
            scope: scope, accepted: accepted)
        let acceptedBlob = GitObject.create(kind: .blob, data: Data("desktop resolution".utf8))
        let integrationDocs = try GitTree.create(entries: [
            GitTreeEntry(name: "note.md", objectID: acceptedBlob.id, kind: .file, executable: false)
        ], sha256: false)
        let integrationTree = try GitTree.create(entries: [
            GitTreeEntry(name: "docs", objectID: integrationDocs.id, kind: .folder, executable: false)
        ], sha256: false)
        let integration = try GitIntegrationResult.buildCommit(
            receipt: receipt, parentCommitID: proposalID, treeID: integrationTree.id,
            identity: identity, sourceRevision: sourceRevision.id)
        // This later commit contains an independent out-of-scope change but
        // retains the source selected blob. An ancestry-only consumer would
        // silently revert the accepted desktop resolution.
        let stagedOnlyBlob = GitObject.create(kind: .blob, data: Data("staged-only".utf8))
        let stagedOnlyTree = try GitTree.create(entries: [
            GitTreeEntry(name: "docs", objectID: sourceDocs.id, kind: .folder, executable: false),
            GitTreeEntry(name: "outside.md", objectID: stagedOnlyBlob.id, kind: .file, executable: false)
        ], sha256: false)
        let laterSource = makeCommit(treeID: stagedOnlyTree.id, parentID: sourceRevision.id,
                                     message: "out-of-scope desktop edit")
        let transport = IntegrationConsumerTransport(
            integrationRef: integration.result.integrationRef,
            integrationCommit: integration.commit,
            integrationTrees: [integrationTree, integrationDocs],
            sourceBranch: "refs/heads/main", sourceCommit: laterSource,
            sourceTrees: [stagedOnlyTree, sourceDocs, sourceRevision], selectedBlob: sourceBlob)
        let project = try OfflineProject(id: projectID, name: "Fixture", mode: .git,
                                         scope: scope,
                                         snapshot: acceptedSnapshot(integration: integration, accepted: accepted))
        let connection = try GitProjectConnection(projectID: projectID,
                                                  endpoint: URL(string: "https://example.invalid/repo.git")!,
                                                  branch: "refs/heads/main", scope: scope)

        let outcome = try await GitIntegrationConsumer(reader: GitRemoteReader(transport: transport),
                                                       deviceID: deviceID)
            .consume(project, connection: connection)
        guard case .requiresReconciliation = outcome else {
            return XCTFail("A source commit retaining the old selected bytes must require reconciliation")
        }
        var dirty = project
        try dirty.write(path: "docs/local-draft.md", content: Data("local draft".utf8))
        let dirtyOutcome = try await GitIntegrationConsumer(reader: GitRemoteReader(transport: transport),
                                                            deviceID: deviceID)
            .consume(dirty, connection: connection)
        guard case .requiresReconciliation = dirtyOutcome else {
            return XCTFail("A local draft must block automatic source-branch replacement")
        }
        let requests = await transport.requests
        XCTAssertFalse(requests.contains { request in
            let text = String(decoding: request, as: UTF8.self)
            return text.contains("want \(sourceBlob.id)\n") && !text.contains("filter blob:none\n")
        })
    }

    func testMissingIntegrationRefUsesPersistedBaselineAndRetainsAcceptedSnapshot() async throws {
        let projectID = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
        let deviceID = UUID(uuidString: "22222222-2222-4222-8222-222222222222")!
        let scope = try CorpusScope(folder: "docs")
        let identity = try GitCommitIdentity(name: "Fixture", email: "fixture@example.invalid", timestamp: 10)
        let sourceBlob = GitObject.create(kind: .blob, data: Data("source".utf8))
        let sourceDocs = try GitTree.create(entries: [
            GitTreeEntry(name: "note.md", objectID: sourceBlob.id, kind: .file, executable: false)
        ], sha256: false)
        let sourceTree = try GitTree.create(entries: [
            GitTreeEntry(name: "docs", objectID: sourceDocs.id, kind: .folder, executable: false)
        ], sha256: false)
        let sourceRevision = makeCommit(treeID: sourceTree.id, parentID: nil, message: "desktop source")
        let proposalID = String(repeating: "b", count: 40)
        let accepted = CorpusSnapshot(revision: proposalID, files: [
            CorpusFile(path: "docs/note.md", content: Data("desktop resolution".utf8))
        ])
        let receipt = try GitIntegrationReceipt(
            projectID: projectID, deviceID: deviceID,
            branch: GitDeviceBranch.name(deviceID: deviceID, projectID: projectID),
            commitID: proposalID, baseRevision: sourceRevision.id,
            scope: scope, accepted: accepted)
        let acceptedBlob = GitObject.create(kind: .blob, data: Data("desktop resolution".utf8))
        let integrationDocs = try GitTree.create(entries: [
            GitTreeEntry(name: "note.md", objectID: acceptedBlob.id, kind: .file, executable: false)
        ], sha256: false)
        let integrationTree = try GitTree.create(entries: [
            GitTreeEntry(name: "docs", objectID: integrationDocs.id, kind: .folder, executable: false)
        ], sha256: false)
        let integration = try GitIntegrationResult.buildCommit(
            receipt: receipt, parentCommitID: proposalID, treeID: integrationTree.id,
            identity: identity, sourceRevision: sourceRevision.id)
        let transport = IntegrationConsumerTransport(
            integrationRef: integration.result.integrationRef,
            integrationCommit: integration.commit,
            integrationTrees: [integrationTree, integrationDocs],
            sourceBranch: "refs/heads/main", sourceCommit: sourceRevision,
            sourceTrees: [sourceTree, sourceDocs], selectedBlob: sourceBlob,
            includeIntegrationRef: false)
        let baseline = try GitBaseline(commitID: integration.result.integrationCommitID,
                                       objects: [integration.commit, integrationTree, integrationDocs])
        let project = try OfflineProject(id: projectID, name: "Fixture", mode: .git,
                                         scope: scope,
                                         snapshot: acceptedSnapshot(integration: integration, accepted: accepted))
        let connection = try GitProjectConnection(projectID: projectID,
                                                  endpoint: URL(string: "https://example.invalid/repo.git")!,
                                                  branch: "refs/heads/main", scope: scope)

        let outcome = try await GitIntegrationConsumer(reader: GitRemoteReader(transport: transport),
                                                       deviceID: deviceID)
            .consume(project, connection: connection, currentBaseline: baseline)
        guard case .alreadyIntegrated = outcome else {
            return XCTFail("A pruned integration ref must not trigger a fallback to the old source branch")
        }
        XCTAssertEqual(project.base.files.first?.content, Data("desktop resolution".utf8))
        let requests = await transport.requests
        XCTAssertFalse(requests.contains { request in
            String(decoding: request, as: UTF8.self).contains("want \(sourceBlob.id)\n")
        })
    }

    func testAncestryProofExploresEveryMergeParentBeforeRejectingHistory() async throws {
        let treeID = String(repeating: "c", count: 40)
        let ancestor = makeCommit(treeID: treeID, parentID: nil, message: "ancestor")
        let unrelatedRoot = makeCommit(treeID: treeID, parentID: nil, message: "unrelated")
        let reachableParent = makeCommit(treeID: treeID, parentID: ancestor.id, message: "reachable")
        let mergeText = "tree \(treeID)\nparent \(unrelatedRoot.id)\nparent \(reachableParent.id)\n" +
            "author Fixture <fixture@example.invalid> 10 +0000\n" +
            "committer Fixture <fixture@example.invalid> 10 +0000\n\nmerge\n"
        let merge = GitObject.create(kind: .commit, data: Data(mergeText.utf8))
        let transport = AncestryTransport(tip: merge, objects: [merge, unrelatedRoot, reachableParent])
        let reader = GitRemoteReader(transport: transport)
        let discovery = try await reader.discover()

        let proof = try await reader.proveAncestry(ancestor: ancestor.id,
                                                   descendant: merge.id,
                                                   discovery: discovery,
                                                   maximumCommits: 8)
        XCTAssertEqual(proof, .proven)
    }

    func testAncestryProofRejectsBlobBearingMetadataResponse() async throws {
        let treeID = String(repeating: "c", count: 40)
        let tip = makeCommit(treeID: treeID, parentID: nil, message: "tip")
        let blob = GitObject.create(kind: .blob, data: Data("unexpected".utf8))
        let transport = AncestryTransport(tip: tip, objects: [tip, blob])
        let reader = GitRemoteReader(transport: transport)
        let discovery = try await reader.discover()

        do {
            _ = try await reader.proveAncestry(ancestor: String(repeating: "d", count: 40),
                                               descendant: tip.id,
                                               discovery: discovery)
            XCTFail("A blob-bearing metadata response must be rejected")
        } catch {
            guard let wireError = error as? GitWireError else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(wireError, .invalidPack)
        }
    }

    private func acceptedSnapshot(integration: GitIntegrationBuiltCommit,
                                  accepted: CorpusSnapshot) -> CorpusSnapshot {
        CorpusSnapshot(revision: integration.result.integrationCommitID, files: accepted.files)
    }

    private func makeCommit(treeID: String, parentID: String?, message: String) -> GitObject {
        let parent = parentID.map { "parent \($0)\n" } ?? ""
        let text = "tree \(treeID)\n\(parent)author Fixture <fixture@example.invalid> 10 +0000\n" +
            "committer Fixture <fixture@example.invalid> 10 +0000\n\n\(message)\n"
        return GitObject.create(kind: .commit, data: Data(text.utf8))
    }
}

private actor IntegrationConsumerTransport: GitRemoteTransport {
    let integrationRef: GitIntegrationRef
    let integrationCommit: GitObject
    let integrationTrees: [GitObject]
    let sourceBranch: String
    let sourceCommit: GitObject
    let sourceTrees: [GitObject]
    let selectedBlob: GitObject
    let includeIntegrationRef: Bool
    private(set) var requests: [Data] = []

    init(integrationRef: GitIntegrationRef, integrationCommit: GitObject,
         integrationTrees: [GitObject], sourceBranch: String, sourceCommit: GitObject,
         sourceTrees: [GitObject], selectedBlob: GitObject,
         includeIntegrationRef: Bool = true) {
        self.integrationRef = integrationRef
        self.integrationCommit = integrationCommit
        self.integrationTrees = integrationTrees
        self.sourceBranch = sourceBranch
        self.sourceCommit = sourceCommit
        self.sourceTrees = sourceTrees
        self.selectedBlob = selectedBlob
        self.includeIntegrationRef = includeIntegrationRef
    }

    func advertisement() async throws -> Data {
        var output = Data()
        for line in ["version 2", "ls-refs", "fetch=shallow filter", "object-format=sha1"] {
            output += try GitPacket.data(Data((line + "\n").utf8)).encoded()
        }
        output += try GitPacket.flush.encoded()
        return output
    }

    func uploadPack(request: Data) async throws -> Data {
        requests.append(request)
        let text = String(decoding: request, as: UTF8.self)
        if text.contains("command=ls-refs\n") {
            var output = try GitPacket.data(Data("\(sourceCommit.id) \(sourceBranch)\n".utf8)).encoded()
            if includeIntegrationRef {
                output += try GitPacket.data(Data("\(integrationCommit.id) \(integrationRef.name)\n".utf8)).encoded()
            }
            return try output + GitPacket.flush.encoded()
        }
        if text.contains("want \(integrationCommit.id)\n") {
            return try fetchResponse(objects: [integrationCommit] + integrationTrees,
                                     shallow: integrationCommit.id)
        }
        if text.contains("want \(sourceCommit.id)\n") {
            return try fetchResponse(objects: [sourceCommit] + sourceTrees, shallow: sourceCommit.id)
        }
        if text.contains("want \(selectedBlob.id)\n") {
            return try fetchResponse(objects: [selectedBlob], shallow: nil)
        }
        throw GitWireError.invalidFetchResponse
    }

    private func fetchResponse(objects: [GitObject], shallow: String?) throws -> Data {
        var output = Data()
        if let shallow {
            output += try GitPacket.data(Data("shallow-info\n".utf8)).encoded()
            output += try GitPacket.data(Data("shallow \(shallow)\n".utf8)).encoded()
            output += try GitPacket.delimiter.encoded()
        }
        output += try GitPacket.data(Data("packfile\n".utf8)).encoded()
        output += try GitPacket.data(Data([1]) + GitPackWriter.encode(objects: objects)).encoded()
        output += try GitPacket.flush.encoded()
        return output
    }
}

private actor AncestryTransport: GitRemoteTransport {
    let tip: GitObject
    let objects: [GitObject]

    init(tip: GitObject, objects: [GitObject]) {
        self.tip = tip
        self.objects = objects
    }

    func advertisement() async throws -> Data {
        var output = Data()
        for line in ["version 2", "ls-refs", "fetch=shallow filter", "object-format=sha1"] {
            output += try GitPacket.data(Data((line + "\n").utf8)).encoded()
        }
        output += try GitPacket.flush.encoded()
        return output
    }

    func uploadPack(request: Data) async throws -> Data {
        let text = String(decoding: request, as: UTF8.self)
        if text.contains("command=ls-refs\n") {
            return try GitPacket.data(Data("\(tip.id) refs/heads/main\n".utf8)).encoded()
                + GitPacket.flush.encoded()
        }
        guard text.contains("want \(tip.id)\n") else { throw GitWireError.invalidFetchResponse }
        var output = Data()
        output += try GitPacket.data(Data("shallow-info\n".utf8)).encoded()
        output += try GitPacket.data(Data("shallow \(tip.id)\n".utf8)).encoded()
        output += try GitPacket.delimiter.encoded()
        output += try GitPacket.data(Data("packfile\n".utf8)).encoded()
        output += try GitPacket.data(Data([1]) + GitPackWriter.encode(objects: objects)).encoded()
        output += try GitPacket.flush.encoded()
        return output
    }
}
