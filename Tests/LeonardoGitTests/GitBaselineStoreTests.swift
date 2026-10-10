import XCTest
@testable import LeonardoGit
import LeonardoSync

final class GitBaselineStoreTests: XCTestCase {
    private func baseline(sha256: Bool = false, message: String = "fixture") throws -> GitBaseline {
        let tree = GitObject.create(kind: .tree, data: Data(), sha256: sha256)
        let commit = GitObject.create(kind: .commit, data: Data("tree \(tree.id)\n\n\(message)\n".utf8), sha256: sha256)
        return try GitBaseline(commitID: commit.id, objects: [commit, tree])
    }

    func testExactRevisionsRoundTripAndOldArchiveSurvivesUntilExplicitRetention() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = GitBaselineStore(root: root)
        for sha256 in [false, true] {
            let id = UUID()
            let old = try baseline(sha256: sha256)
            let new = try baseline(sha256: sha256, message: "advanced")
            try await store.save(old, projectID: id)
            try await store.save(new, projectID: id)
            let loadedOld = try await store.load(projectID: id, revision: old.commitID)
            let loadedNew = try await store.load(projectID: id, revision: new.commitID)
            XCTAssertEqual(loadedOld, old)
            XCTAssertEqual(loadedNew, new)
            let url = root.appendingPathComponent(id.uuidString).appendingPathComponent(new.commitID + ".pack")
            XCTAssertEqual((try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber)?.intValue, 0o600)
            let unrelated = url.deletingLastPathComponent().appendingPathComponent("unrelated.txt")
            try Data("untouched".utf8).write(to: unrelated)
            try await store.retain(projectID: id, revision: new.commitID)
            XCTAssertEqual(try Data(contentsOf: unrelated), Data("untouched".utf8))
            let absent = try await store.load(projectID: id, revision: old.commitID)
            XCTAssertNil(absent)
            let retained = try await store.load(projectID: id, revision: new.commitID)
            XCTAssertEqual(retained, new)
            try await store.remove(projectID: id)
            XCTAssertFalse(FileManager.default.fileExists(atPath: url.deletingLastPathComponent().path))
        }
    }

    func testCorruptionWrongRevisionAndSymlinkAreRejected() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = GitBaselineStore(root: root)
        let value = try baseline()
        let id = UUID()
        try await store.save(value, projectID: id)
        let url = root.appendingPathComponent(id.uuidString).appendingPathComponent(value.commitID + ".pack")
        var pack = try Data(contentsOf: url)
        pack[pack.count - 1] ^= 1
        try pack.write(to: url)
        do { _ = try await store.load(projectID: id, revision: value.commitID); XCTFail("Corrupt pack accepted") } catch {}
        try await store.save(value, projectID: id)
        let other = root.appendingPathComponent(id.uuidString).appendingPathComponent(String(repeating: "a", count: 40) + ".pack")
        try Data(contentsOf: url).write(to: other)
        do { _ = try await store.load(projectID: id, revision: String(repeating: "a", count: 40)); XCTFail("Wrong commit accepted") } catch {}
        try FileManager.default.removeItem(at: url)
        try FileManager.default.createSymbolicLink(at: url, withDestinationURL: other)
        do { _ = try await store.load(projectID: id, revision: value.commitID); XCTFail("Symlink read accepted") } catch {}
        do { try await store.save(value, projectID: id); XCTFail("Symlink write accepted") } catch {}
        do { _ = try await store.load(projectID: id, revision: "../../outside"); XCTFail("Traversal accepted") } catch {}
    }

    func testBaselineRejectsBlobsTamperedIDsAndIncompleteTrees() throws {
        let value = try baseline()
        let blob = GitObject.create(kind: .blob, data: Data("secret".utf8))
        XCTAssertThrowsError(try GitBaseline(commitID: value.commitID, objects: value.objects + [blob]))
        let corrupted = GitObject(id: value.commitID, kind: .commit, data: Data("tampered".utf8))
        XCTAssertThrowsError(try GitBaseline(commitID: value.commitID, objects: [corrupted]))
        let folder = GitTreeEntry(name: "missing", objectID: String(repeating: "a", count: 40), kind: .folder, executable: false)
        let tree = try GitTree.create(entries: [folder], sha256: false)
        let commit = GitObject.create(kind: .commit, data: Data("tree \(tree.id)\n\nfixture\n".utf8))
        XCTAssertThrowsError(try GitBaseline(commitID: commit.id, objects: [commit, tree]))
    }
}
