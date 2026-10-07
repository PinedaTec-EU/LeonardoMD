import Foundation
import XCTest
@testable import LeonardoCore

final class GitRepositoryTests: XCTestCase {
    func testStatusStageCommitAndHistory() async throws {
        let directory = try TemporaryDirectory()
        let repository = GitRepository(rootURL: directory.url)

        let noRepository = try await repository.status()
        XCTAssertEqual(noRepository.state, .noRepository)
        _ = try await repository.initialize()
        try runGit(["config", "user.name", "LeonardoMD Tests"], at: directory.url)
        try runGit(["config", "user.email", "tests@example.invalid"], at: directory.url)
        let emptyHistory = try await repository.history(limit: 5)
        XCTAssertTrue(emptyHistory.isEmpty)

        let dashFile = directory.url.appendingPathComponent("-notes.md")
        let spacedFile = directory.url.appendingPathComponent("space name.md")
        try Data("one".utf8).write(to: dashFile)
        try Data("two".utf8).write(to: spacedFile)
        let pending = try await repository.status()
        XCTAssertEqual(pending.state, .changesPending)
        XCTAssertEqual(Set(pending.changes.map(\.path)), ["-notes.md", "space name.md"])

        _ = try await repository.stage(paths: ["-notes.md", "space name.md"])
        let commitHash = try await repository.commit(message: "Initial notes")
        XCTAssertFalse(commitHash.isEmpty)
        let cleanStatus = try await repository.status()
        XCTAssertEqual(cleanStatus.state, .clean)

        let history = try await repository.history(limit: 5)
        XCTAssertEqual(history.count, 1)
        XCTAssertEqual(history[0].subject, "Initial notes")
        XCTAssertEqual(history[0].hash, commitHash)
    }

    func testPullRefusesDirtyWorktreeAndPathsAreValidated() async throws {
        let directory = try TemporaryDirectory()
        let repository = GitRepository(rootURL: directory.url)
        _ = try await repository.initialize()
        try runGit(["config", "user.name", "LeonardoMD Tests"], at: directory.url)
        try runGit(["config", "user.email", "tests@example.invalid"], at: directory.url)
        let file = directory.url.appendingPathComponent("note.md")
        try Data("one".utf8).write(to: file)
        _ = try await repository.stageAll()
        _ = try await repository.commit(message: "Initial")
        try Data("changed".utf8).write(to: file)

        do {
            _ = try await repository.pull()
            XCTFail("Expected pull to refuse a dirty worktree")
        } catch let error as GitError {
            XCTAssertEqual(error, .workingTreeDirty)
        }

        do {
            _ = try await repository.stage(paths: ["../outside"])
            XCTFail("Expected path validation")
        } catch let error as GitError {
            XCTAssertEqual(error, .invalidPath("../outside"))
        }
    }

    func testLocalBareRemoteTracksAheadBehindAcrossFetchPullAndPush() async throws {
        let directory = try TemporaryDirectory()
        let remote = directory.url.appendingPathComponent("remote.git", isDirectory: true)
        let seed = directory.url.appendingPathComponent("seed", isDirectory: true)
        let local = directory.url.appendingPathComponent("local", isDirectory: true)
        try runGit(["init", "--bare", remote.path], at: directory.url)
        try runGit(["clone", remote.path, seed.path], at: directory.url)
        try configureIdentity(at: seed)

        try Data("base".utf8).write(to: seed.appendingPathComponent("notes.md"))
        try runGit(["add", "--", "notes.md"], at: seed)
        try runGit(["commit", "-m", "base"], at: seed)
        try runGit(["push", "-u", "origin", "HEAD"], at: seed)
        try runGit(["clone", remote.path, local.path], at: directory.url)
        try configureIdentity(at: local)

        let repository = GitRepository(rootURL: local)
        let initial = try await repository.status()
        XCTAssertEqual(initial.ahead, 0)
        XCTAssertEqual(initial.behind, 0)

        try Data("remote change".utf8).write(to: seed.appendingPathComponent("remote.md"))
        try runGit(["add", "--", "remote.md"], at: seed)
        try runGit(["commit", "-m", "remote"], at: seed)
        try runGit(["push"], at: seed)
        _ = try await repository.fetch()
        let behind = try await repository.status()
        XCTAssertEqual(behind.behind, 1)
        XCTAssertEqual(behind.ahead, 0)

        _ = try await repository.pull()
        let synchronized = try await repository.status()
        XCTAssertEqual(synchronized.behind, 0)
        XCTAssertEqual(synchronized.ahead, 0)

        try Data("local change".utf8).write(to: local.appendingPathComponent("local.md"))
        _ = try await repository.stageAll()
        _ = try await repository.commit(message: "local")
        let ahead = try await repository.status()
        XCTAssertEqual(ahead.ahead, 1)
        XCTAssertEqual(ahead.behind, 0)
        _ = try await repository.push()
        let final = try await repository.status()
        XCTAssertEqual(final.ahead, 0)
        XCTAssertEqual(final.behind, 0)
    }

    func testStatusReportsConflictedFiles() async throws {
        let directory = try TemporaryDirectory()
        let repository = GitRepository(rootURL: directory.url)
        _ = try await repository.initialize()
        try configureIdentity(at: directory.url)
        let file = directory.url.appendingPathComponent("conflict.md")
        try Data("base".utf8).write(to: file)
        _ = try await repository.stageAll()
        _ = try await repository.commit(message: "base")
        let mainBranch = try runGitOutput(["branch", "--show-current"], at: directory.url)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        try runGit(["checkout", "-b", "topic"], at: directory.url)
        try Data("topic".utf8).write(to: file)
        try runGit(["add", "--", "conflict.md"], at: directory.url)
        try runGit(["commit", "-m", "topic"], at: directory.url)
        try runGit(["checkout", mainBranch], at: directory.url)
        try Data("main".utf8).write(to: file)
        try runGit(["add", "--", "conflict.md"], at: directory.url)
        try runGit(["commit", "-m", "main"], at: directory.url)
        let merge = try runGitResult(["merge", "topic"], at: directory.url)
        XCTAssertNotEqual(merge.status, 0)

        let status = try await repository.status()
        XCTAssertEqual(status.state, .conflicted)
        XCTAssertEqual(status.changes.first?.status, .conflicted)
        XCTAssertEqual(status.changes.first?.path, "conflict.md")
    }

    func testStatusPreservesDashUnicodeAndNewlinePaths() async throws {
        let directory = try TemporaryDirectory()
        let repository = GitRepository(rootURL: directory.url)
        _ = try await repository.initialize()
        try configureIdentity(at: directory.url)
        let names = ["-dash.md", "naïve.md", "line\nbreak.md"]
        for (index, name) in names.enumerated() {
            try Data("note \(index)".utf8).write(to: directory.url.appendingPathComponent(name))
        }

        let pending = try await repository.status()
        XCTAssertEqual(Set(pending.changes.map(\.path)), Set(names))
        _ = try await repository.stage(paths: names)
        _ = try await repository.commit(message: "special paths")

        let renamed = "renamed\né.md"
        try runGit(["mv", "--", "line\nbreak.md", renamed], at: directory.url)
        let renamedStatus = try await repository.status()
        XCTAssertTrue(renamedStatus.changes.contains { $0.path == renamed && $0.status == .renamed })
    }

    func testGitRunnerDrainsLargeOutputWithoutDeadlock() async throws {
        let directory = try TemporaryDirectory()
        let executable = directory.url.appendingPathComponent("fake-git.sh")
        try Data("#!/bin/sh\ndd if=/dev/zero bs=1048576 count=2 2>/dev/null\n".utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)

        let repository = GitRepository(rootURL: directory.url, executableURL: executable)
        let status = try await repository.status()
        XCTAssertEqual(status.state, .clean)
    }

    private func configureIdentity(at directory: URL) throws {
        try runGit(["config", "user.name", "LeonardoMD Tests"], at: directory)
        try runGit(["config", "user.email", "tests@example.invalid"], at: directory)
    }

    private func runGit(_ arguments: [String], at directory: URL) throws {
        let result = try runGitResult(arguments, at: directory)
        guard result.status == 0 else {
            XCTFail("git failed: \(result.output)")
            return
        }
    }

    private func runGitOutput(_ arguments: [String], at directory: URL) throws -> String {
        let result = try runGitResult(arguments, at: directory)
        guard result.status == 0 else {
            XCTFail("git failed: \(result.output)")
            return ""
        }
        return result.output
    }

    private func runGitResult(_ arguments: [String], at directory: URL) throws -> (status: Int32, output: String) {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.currentDirectoryURL = directory
        process.standardOutput = output
        process.standardError = output
        try process.run()
        process.waitUntilExit()
        let message = String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return (process.terminationStatus, message)
    }
}
