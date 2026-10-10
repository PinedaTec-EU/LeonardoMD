import XCTest
@testable import LeonardoGit
import LeonardoSync

final class GitPublicationStoreTests: XCTestCase {
    private func fixture(sha256: Bool) throws -> (OfflineProject, GitBaseline) {
        let old = Data("old".utf8)
        let blob = GitObject.create(kind: .blob, data: old, sha256: sha256)
        let docs = try GitTree.create(entries: [GitTreeEntry(name: "note.md", objectID: blob.id, kind: .file, executable: false),
            GitTreeEntry(name: "keep.md", objectID: blob.id, kind: .file, executable: false)], sha256: sha256)
        let root = try GitTree.create(entries: [GitTreeEntry(name: "docs", objectID: docs.id, kind: .folder, executable: false),
            GitTreeEntry(name: "outside.bin", objectID: blob.id, kind: .file, executable: false)], sha256: sha256)
        let commit = GitObject.create(kind: .commit, data: Data("tree \(root.id)\n\nfixture\n".utf8), sha256: sha256)
        let baseline = try GitBaseline(commitID: commit.id, objects: [commit, root, docs])
        let files = [CorpusFile(path: "docs/keep.md", content: old), CorpusFile(path: "docs/note.md", content: old)]
        var project = try OfflineProject(name: "Fixture", mode: .git, scope: CorpusScope(folder: "docs"), snapshot: CorpusSnapshot(revision: commit.id, files: files))
        try project.write(path: "docs/note.md", content: Data("first edit".utf8))
        return (project, baseline)
    }

    func testPreparedCaptureSurvivesRestartAndLaterEditsInBothFormats() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = GitPublicationStore(root: root)
        for sha256 in [false, true] {
            var (project, baseline) = try fixture(sha256: sha256)
            let identity = try GitCommitIdentity(name: "Fixture", email: "fixture@example.invalid", timestamp: 1_700_000_000)
            let prepared = try GitPreparedPublication(project: project, baseline: baseline, deviceID: UUID(), identity: identity, expectedOldID: nil)
            try await store.save(prepared)
            let restarted = GitPublicationStore(root: root)
            let loaded = try await restarted.load(projectID: project.id)
            XCTAssertEqual(loaded, prepared)
            try project.write(path: "docs/note.md", content: Data("later edit".utf8))
            try project.write(path: "docs/new.md", content: Data("later creation".utf8))
            let restored = try XCTUnwrap(loaded).restore(project: project, baseline: baseline)
            XCTAssertEqual(restored.commit.commit.id, prepared.commitID)
            XCTAssertEqual(restored.capture.files.first(where: { $0.path == "docs/note.md" })?.content, Data("first edit".utf8))
            XCTAssertFalse(restored.capture.files.contains { $0.path == "docs/new.md" })
            let before = project.files
            try project.markPublished(restored.capture)
            XCTAssertEqual(project.files, before)
            XCTAssertEqual(project.publishedFiles, restored.capture.files)
            XCTAssertEqual(project.publication, .sent)
            try project.acceptIntegration(restored.capture)
            XCTAssertEqual(project.files, before)
            XCTAssertEqual(project.publication, .localChanges)
            let url = root.appendingPathComponent(project.id.uuidString).appendingPathExtension("json")
            XCTAssertEqual((try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber)?.intValue, 0o600)
            try await restarted.remove(projectID: project.id)
            let absent = try await restarted.load(projectID: project.id)
            XCTAssertNil(absent)
        }
    }

    func testPendingIntentCannotBeReplacedAndTamperingCannotChangeScopeOrCommit() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = GitPublicationStore(root: root)
        var (project, baseline) = try fixture(sha256: false)
        let identity = try GitCommitIdentity(name: "Fixture", email: "fixture@example.invalid", timestamp: 1)
        let prepared = try GitPreparedPublication(project: project, baseline: baseline, deviceID: UUID(), identity: identity, expectedOldID: nil)
        try await store.save(prepared)
        try project.write(path: "docs/note.md", content: Data("different".utf8))
        let another = try GitPreparedPublication(project: project, baseline: baseline, deviceID: prepared.deviceID, identity: identity, expectedOldID: nil)
        do { try await store.save(another); XCTFail("Pending capture replaced") } catch {}
        let encoder = JSONEncoder()
        let original = try XCTUnwrap(JSONSerialization.jsonObject(with: encoder.encode(prepared)) as? [String: Any])
        var mutations: [[String: Any]] = []
        var wrongCommit = original; wrongCommit["commitID"] = String(repeating: "a", count: 40); mutations.append(wrongCommit)
        var wrongPack = original; wrongPack["pack"] = Data([1]).base64EncodedString(); mutations.append(wrongPack)
        var outside = original
        var files = try XCTUnwrap(outside["files"] as? [[String: Any]])
        files[0]["path"] = "outside.md"; outside["files"] = files; mutations.append(outside)
        for value in mutations {
            let data = try JSONSerialization.data(withJSONObject: value)
            let tampered = try JSONDecoder().decode(GitPreparedPublication.self, from: data)
            XCTAssertThrowsError(try tampered.restore(project: project, baseline: baseline))
        }
        let unchanged = try await store.load(projectID: project.id)
        XCTAssertEqual(unchanged, prepared)
        let url = root.appendingPathComponent(project.id.uuidString).appendingPathExtension("json")
        try FileManager.default.removeItem(at: url)
        try FileManager.default.createSymbolicLink(at: url, withDestinationURL: root.appendingPathComponent("outside"))
        do { try await store.save(prepared); XCTFail("Symlink write accepted") } catch {}
    }

    func testReconciliationRequestPublishesCleanSnapshotWithHashBoundPurpose() throws {
        let (_, baseline) = try fixture(sha256: false)
        let clean = try OfflineProject(
            name: "Fixture", mode: .git, scope: CorpusScope(folder: "docs"),
            snapshot: CorpusSnapshot(revision: baseline.commitID, files: [
                CorpusFile(path: "docs/keep.md", content: Data("old".utf8)),
                CorpusFile(path: "docs/note.md", content: Data("old".utf8))
            ]))
        let identity = try GitCommitIdentity(name: "Fixture", email: "fixture@example.invalid", timestamp: 1)
        let prepared = try GitPreparedPublication(
            project: clean, baseline: baseline, deviceID: UUID(), identity: identity,
            expectedOldID: nil, purpose: .reconciliationRequest)
        XCTAssertEqual(prepared.purpose, .reconciliationRequest)
        let restarted = try JSONDecoder().decode(GitPreparedPublication.self,
                                                 from: JSONEncoder().encode(prepared))
        XCTAssertEqual(restarted, prepared)

        var missingPurpose = try XCTUnwrap(JSONSerialization.jsonObject(
            with: JSONEncoder().encode(prepared)) as? [String: Any])
        missingPurpose.removeValue(forKey: "purpose")
        let missingPurposeData = try JSONSerialization.data(withJSONObject: missingPurpose)
        XCTAssertThrowsError(try JSONDecoder().decode(GitPreparedPublication.self,
                                                        from: missingPurposeData))

        var missingMetadata = try XCTUnwrap(JSONSerialization.jsonObject(
            with: JSONEncoder().encode(prepared)) as? [String: Any])
        missingMetadata.removeValue(forKey: "publicationMetadata")
        let missingMetadataData = try JSONSerialization.data(withJSONObject: missingMetadata)
        XCTAssertThrowsError(try JSONDecoder().decode(GitPreparedPublication.self,
                                                        from: missingMetadataData))

        let restored = try restarted.restore(project: clean, baseline: baseline)
        XCTAssertEqual(restored.capture.files, clean.files)
        let metadata = try GitPublicationMetadata.parse(commit: restored.commit.commit,
                                                        expectedCommitID: restored.commit.commit.id)
        XCTAssertEqual(metadata.purpose, .reconciliationRequest)

        var sent = clean
        try sent.markPublished(restored.capture, purpose: .reconciliationRequest)
        XCTAssertEqual(sent.publication, .sent)
        XCTAssertEqual(sent.publishedFiles, clean.files)
        XCTAssertThrowsError(try GitCommitBuilder.build(project: clean, baseline: baseline,
                                                        identity: identity))
        XCTAssertThrowsError(try GitCommitBuilder.build(project: clean, baseline: baseline,
                                                        identity: identity,
                                                        purpose: .reconciliationRequest))
    }
}
