import XCTest
@testable import LeonardoGit
import LeonardoSync

final class GitPushTests: XCTestCase {
    private let branch = "refs/heads/little-leonardo/device/project"

    private func built(sha256: Bool, parent: String? = nil, message: String = "fixture") -> GitBuiltCommit {
        let tree = GitObject.create(kind: .tree, data: Data(), sha256: sha256)
        let parentLine = parent.map { "parent \($0)\n" } ?? ""
        let data = Data("tree \(tree.id)\n\(parentLine)author Fixture <fixture@example.invalid> 1700000000 +0000\ncommitter Fixture <fixture@example.invalid> 1700000000 +0000\n\n\(message)\n".utf8)
        let commit = GitObject.create(kind: .commit, data: data, sha256: sha256)
        return GitBuiltCommit(commit: commit, objects: [tree, commit])
    }

    func testMalformedReportsCannotConfirmPublication() throws {
        func wire(_ lines: [String]) throws -> Data {
            try lines.reduce(into: Data()) { $0 += try GitPacket.data(Data(($1 + "\n").utf8)).encoded() } + GitPacket.flush.encoded()
        }
        try GitPushReport.validate(wire(["unpack ok", "ok \(branch)"]), branch: branch)
        for lines in [["unpack failed", "ng \(branch) unpack failure"], ["unpack ok", "ng \(branch) hook declined"],
                      ["unpack ok", "ok refs/heads/main"], ["unpack ok"], ["unpack ok", "ok \(branch)", "ok \(branch)"],
                      ["unpack ok", "ok \(branch)\nextra"]] {
            XCTAssertThrowsError(try GitPushReport.validate(wire(lines), branch: branch))
        }
    }

    func testAdvertisementEnvelopesCapabilitiesAndReferenceGuards() throws {
        func wire(_ lines: [String]) throws -> Data {
            try lines.reduce(into: Data()) { $0 += try GitPacket.data(Data(($1 + "\n").utf8)).encoded() } + GitPacket.flush.encoded()
        }
        let oid = String(repeating: "a", count: 40)
        let valid = try wire(["\(oid) refs/heads/main\0report-status object-format=sha1"])
        let envelope = try GitPacket.data(Data("# service=git-receive-pack\n".utf8)).encoded() + GitPacket.flush.encoded()
        XCTAssertEqual(try GitPushAdvertisement(data: envelope + valid).references["refs/heads/main"], oid)
        for lines in [["\(oid) refs/heads/main"], ["\(oid) refs/heads/main\0report-status report-status"],
                      ["\(oid) refs/heads/main\0report-status object-format=sha512"],
                      ["\(oid) refs/heads/main\0report-status", "\(oid) refs/heads/main"],
                      ["\(oid) refs/heads/main\0report-status", "\(oid) refs/heads/second\0extra"]] {
            XCTAssertThrowsError(try GitPushAdvertisement(data: wire(lines)))
        }
        let noStatus = try GitPushAdvertisement(data: wire(["\(oid) refs/heads/main\0report-status-v2"]))
        XCTAssertThrowsError(try noStatus.request(branch: branch, expectedOldID: nil, commit: built(sha256: false)))
        let zero = String(repeating: "0", count: 40)
        XCTAssertTrue(try GitPushAdvertisement(data: wire(["\(zero) capabilities^{}\0report-status"])).references.isEmpty)
        let generated = GitDeviceBranch.name(deviceID: UUID(), projectID: UUID())
        XCTAssertTrue(GitReference.isValidName(generated))
        XCTAssertTrue(generated.hasPrefix("refs/heads/little-leonardo/"))
    }

    #if os(macOS)
    func testPreparedPublicationRecoversAfterRemoteAcceptanceWithoutLosingLaterEdits() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        for sha256 in [false, true] {
            let directory = root.appendingPathComponent(sha256 ? "sha256" : "sha1")
            _ = try runGit(["init", "--bare", "--quiet", "--object-format=\(sha256 ? "sha256" : "sha1")", directory.path])
            let old = GitObject.create(kind: .blob, data: Data("old".utf8), sha256: sha256)
            let tree = try GitTree.create(entries: [GitTreeEntry(name: "note.md", objectID: old.id, kind: .file, executable: false)], sha256: sha256)
            let initial = GitObject.create(kind: .commit, data: Data("tree \(tree.id)\nauthor Fixture <fixture@example.invalid> 1 +0000\ncommitter Fixture <fixture@example.invalid> 1 +0000\n\nfixture\n".utf8), sha256: sha256)
            _ = try runGit(["-C", directory.path, "index-pack", "--stdin"], input: GitPackWriter.encode(objects: [old, tree, initial], sha256: sha256))
            _ = try runGit(["-C", directory.path, "update-ref", "refs/heads/main", initial.id])
            let baseline = try GitBaseline(commitID: initial.id, objects: [initial, tree])
            var project = try OfflineProject(name: "Recovery", mode: .git, scope: CorpusScope(folder: ""),
                snapshot: CorpusSnapshot(revision: initial.id, files: [CorpusFile(path: "note.md", content: old.data)]))
            try project.write(path: "note.md", content: Data("captured edit".utf8))
            let journalRoot = directory.appendingPathComponent("publication-journal")
            let journal = GitPublicationStore(root: journalRoot)
            let prepared = try GitPreparedPublication(project: project, baseline: baseline, deviceID: UUID(),
                identity: GitCommitIdentity(name: "Fixture", email: "fixture@example.invalid", timestamp: 1), expectedOldID: nil)
            try await journal.save(prepared)
            let transport = GitReceiveFixture(root: directory.path)
            let publisher = GitPublisher(transport: transport)
            let first = try prepared.restore(project: project, baseline: baseline)
            let accepted = try await publisher.publish(first.commit, branch: prepared.branch, expectedOldID: prepared.expectedOldID)
            XCTAssertEqual(accepted, .accepted)
            // Simulate termination after the server accepts, before local acknowledgement is saved.
            try project.write(path: "note.md", content: Data("later edit".utf8))
            let restarted = GitPublicationStore(root: journalRoot)
            let reloaded = try await restarted.load(projectID: project.id)
            let pending = try XCTUnwrap(reloaded)
            let retry = try pending.restore(project: project, baseline: baseline)
            let recovered = try await publisher.publish(retry.commit, branch: pending.branch, expectedOldID: pending.expectedOldID)
            XCTAssertEqual(recovered, .alreadyAccepted)
            let pushes = await transport.pushCount
            XCTAssertEqual(pushes, 1)
            try project.markPublished(retry.capture)
            let corpus = OfflineCorpusStore(root: directory.appendingPathComponent("corpus"))
            try await corpus.save(project)
            try await restarted.remove(projectID: project.id)
            let persisted = try await corpus.load(id: project.id)
            XCTAssertEqual(persisted?.files.first?.content, Data("later edit".utf8))
            XCTAssertEqual(persisted?.publishedFiles?.first?.content, Data("captured edit".utf8))
            XCTAssertEqual(persisted?.publishedRevision, pending.commitID)
            let remoteContent = try runGit(["-C", directory.path, "show", "\(pending.branch):note.md"])
            XCTAssertEqual(remoteContent, Data("captured edit".utf8))
            _ = try runGit(["-C", directory.path, "fsck", "--full"])
        }
    }

    func testRealReceivePackAcceptsBothFormatsAndRetryIsIdempotent() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        for sha256 in [false, true] {
            let directory = root.appendingPathComponent(sha256 ? "sha256" : "sha1")
            _ = try runGit(["init", "--bare", "--quiet", "--object-format=\(sha256 ? "sha256" : "sha1")", directory.path])
            let transport = GitReceiveFixture(root: directory.path)
            let publisher = GitPublisher(transport: transport)
            let first = built(sha256: sha256)
            let result = try await publisher.publish(first, branch: branch, expectedOldID: nil)
            XCTAssertEqual(result, .accepted)
            let actual = String(decoding: try runGit(["-C", directory.path, "rev-parse", branch]), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            XCTAssertEqual(actual, first.commit.id)
            let retried = try await publisher.publish(first, branch: branch, expectedOldID: nil)
            XCTAssertEqual(retried, .alreadyAccepted)
            let pushes = await transport.pushCount
            XCTAssertEqual(pushes, 1)
            let second = built(sha256: sha256, parent: first.commit.id, message: "second")
            do { _ = try await publisher.publish(second, branch: branch, expectedOldID: nil); XCTFail("Unexpected branch replacement") }
            catch { XCTAssertEqual(error as? GitPushError, .staleReference) }
            let updated = try await publisher.publish(second, branch: branch, expectedOldID: first.commit.id)
            XCTAssertEqual(updated, .accepted)
            _ = try runGit(["-C", directory.path, "fsck", "--full"])
            let hook = directory.appendingPathComponent("hooks/pre-receive")
            try Data("#!/bin/sh\nexit 1\n".utf8).write(to: hook)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: hook.path)
            let third = built(sha256: sha256, parent: second.commit.id, message: "rejected")
            do { _ = try await publisher.publish(third, branch: branch, expectedOldID: second.commit.id); XCTFail("Rejected push confirmed") }
            catch { XCTAssertEqual(error as? GitPushError, .rejected) }
            let after = String(decoding: try runGit(["-C", directory.path, "rev-parse", branch]), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            XCTAssertEqual(after, second.commit.id)
            do { _ = try await publisher.publish(third, branch: "refs/heads/main", expectedOldID: nil); XCTFail("Main publication allowed") } catch {}
        }
    }
    #endif
}

#if os(macOS)
private actor GitReceiveFixture: GitPushTransport {
    let root: String
    private(set) var pushCount = 0
    init(root: String) { self.root = root }
    func receiveAdvertisement() async throws -> Data { try runGit(["receive-pack", "--stateless-rpc", "--advertise-refs", root]) }
    func receivePack(request: Data) async throws -> Data {
        pushCount += 1
        return try runGit(["receive-pack", "--stateless-rpc", root], input: request)
    }
}

private func runGit(_ arguments: [String], input: Data? = nil) throws -> Data {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
    process.arguments = arguments
    process.environment = ProcessInfo.processInfo.environment.merging(["GIT_CONFIG_NOSYSTEM": "1", "GIT_CONFIG_GLOBAL": "/dev/null"]) { _, new in new }
    let output = Pipe(), stdin = Pipe()
    process.standardOutput = output
    process.standardError = FileHandle.nullDevice
    process.standardInput = input == nil ? FileHandle.nullDevice : stdin
    try process.run()
    if let input { try stdin.fileHandleForWriting.write(contentsOf: input); try stdin.fileHandleForWriting.close() }
    let result = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else { throw GitWireError.remoteFailure }
    return result
}
#endif
