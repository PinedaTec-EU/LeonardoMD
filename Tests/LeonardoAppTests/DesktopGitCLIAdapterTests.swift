#if os(macOS)
import Foundation
import XCTest
import LeonardoGit
import LeonardoSync
@testable import LeonardoApp

@MainActor
final class DesktopGitCLIAdapterTests: XCTestCase {
    func testFilteredPublicationFetchPreservesIndexAndWorktreeAndServesExactObjects() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let local = root.appendingPathComponent("local", isDirectory: true)
        let remote = root.appendingPathComponent("remote.git", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: local, withIntermediateDirectories: true)
        try runGit(["init", "--bare", remote.path], at: root)
        try runGit(["config", "uploadpack.allowFilter", "true"], at: remote)
        try runGit(["config", "uploadpack.allowAnySHA1InWant", "true"], at: remote)
        try runGit(["init"], at: local)
        try runGit(["config", "user.name", "Fixture"], at: local)
        try runGit(["config", "user.email", "fixture@example.invalid"], at: local)
        try FileManager.default.createDirectory(at: local.appendingPathComponent("docs"), withIntermediateDirectories: true)
        try Data("base".utf8).write(to: local.appendingPathComponent("docs/note.md"))
        try runGit(["add", "."], at: local)
        try runGit(["commit", "-m", "base"], at: local)
        let commitID = try runGit(["rev-parse", "HEAD"], at: local).trimmingCharacters(in: .whitespacesAndNewlines)
        let projectID = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
        let deviceID = UUID(uuidString: "22222222-2222-4222-8222-222222222222")!
        let branch = GitDeviceBranch.name(deviceID: deviceID, projectID: projectID)
        try runGit(["update-ref", branch, commitID], at: local)
        try runGit(["remote", "add", "origin", remote.path], at: local)
        try runGit(["remote", "add", "credentials", "https://alice:secret@example.invalid/repo.git"], at: local)
        try runGit(["remote", "add", "scp", "alice@example.invalid:repo"], at: local)
        try runGit(["push", "origin", "HEAD:refs/heads/main", branch + ":" + branch], at: local)
        let ordinaryMainBefore = try? runGit(["show-ref", "--verify", "refs/remotes/origin/main"], at: local)

        try Data("staged".utf8).write(to: local.appendingPathComponent("docs/staged.md"))
        try runGit(["add", "docs/staged.md"], at: local)
        try Data("draft".utf8).write(to: local.appendingPathComponent("draft.md"))
        let statusBefore = try runGit(["status", "--porcelain=v2", "-z", "--branch", "--untracked-files=all"], at: local)
        let indexBefore = try Data(contentsOf: local.appendingPathComponent(".git/index"))

        let adapter = DesktopGitCLIAdapter(projectRoot: local)
        let remotes = try await adapter.remotes()
        let credentialRemote = try XCTUnwrap(remotes.first { $0.name == "credentials" })
        XCTAssertFalse(credentialRemote.urls.joined().contains("secret"))
        XCTAssertFalse(credentialRemote.urls.joined().contains("alice@"))
        let scpRemote = try XCTUnwrap(remotes.first { $0.name == "scp" })
        XCTAssertFalse(scpRemote.urls.joined().contains("alice@"))
        XCTAssertFalse(DesktopGitCLIAdapter.sanitize("fatal: alice@example.invalid:repo").contains("alice@"))

        let branches = try await adapter.fetchPublishedBranches(remote: "origin")
        XCTAssertEqual(branches.map(\.name), [branch])
        XCTAssertEqual(try runGit(["status", "--porcelain=v2", "-z", "--branch", "--untracked-files=all"], at: local), statusBefore)
        XCTAssertEqual(try Data(contentsOf: local.appendingPathComponent(".git/index")), indexBefore)
        XCTAssertEqual(try? runGit(["show-ref", "--verify", "refs/remotes/origin/main"], at: local), ordinaryMainBefore)

        let transport = await adapter.transport()
        let reader = GitRemoteReader(transport: transport)
        let discovery = try await reader.discover()
        let discovered = try reader.publishedBranches(from: discovery)
        XCTAssertEqual(discovered.first?.commitID, commitID)
        let metadata = try await reader.metadata(commitID: commitID, discovery: discovery)
        let snapshot = try await reader.snapshot(metadata: metadata, scope: CorpusScope(folder: "docs"))
        XCTAssertEqual(snapshot.files.first?.content, Data("base".utf8))
    }

    private func runGit(_ arguments: [String], at root: URL) throws -> String {
        String(decoding: try DesktopGitProcessTestSupport.run(arguments: arguments, at: root), as: UTF8.self)
    }
}
#endif
