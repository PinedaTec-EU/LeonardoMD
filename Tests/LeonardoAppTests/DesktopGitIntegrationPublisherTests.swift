#if os(macOS)
import XCTest
@testable import LeonardoApp
@testable import LeonardoGit
import LeonardoSync

@MainActor
final class DesktopGitIntegrationPublisherTests: XCTestCase {
    func testPublisherCreatesExactScopedCommitAndPreservesWorktreeIndex() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let receipt = try makeReceipt(fixture: fixture, content: "merged")
        let indexBefore = try Data(contentsOf: fixture.desktop.appendingPathComponent(".git/index"))
        let statusBefore = try runGitData(["status", "--porcelain=v2", "-z", "--untracked-files=all"], at: fixture.desktop)
        let lease = NativeReconciliationLease()
        lease.sessions = { [] }
        let publisher = DesktopGitIntegrationPublisher(projectRoot: fixture.desktop,
                                                        stateRoot: fixture.root.appendingPathComponent("state"),
                                                        lease: lease)
        let identity = try GitCommitIdentity(name: "Desktop Fixture", email: "fixture@example.invalid", timestamp: 3)

        let envelope = try await publisher.publish(receipt: receipt, remoteName: "origin", identity: identity)
        XCTAssertEqual(envelope.result.proposalCommitID, fixture.headID)
        XCTAssertNotEqual(envelope.result.integrationCommitID, fixture.headID)
        XCTAssertEqual(envelope.result.parentCommitID, fixture.headID)
        XCTAssertEqual(envelope.result.sourceRevision, fixture.headID)
        XCTAssertEqual(try runGit(["rev-parse", "\(envelope.result.integrationCommitID)^"], at: fixture.desktop),
                       fixture.headID + "\n")

        XCTAssertEqual(try runGit(["show", "\(envelope.result.integrationCommitID):docs/note.md"], at: fixture.desktop),
                       "merged")
        XCTAssertEqual(try runGit(["show", "\(envelope.result.integrationCommitID):docs/keep.md"], at: fixture.desktop),
                       "keep")
        XCTAssertEqual(try runGit(["show", "\(envelope.result.integrationCommitID):outside.md"], at: fixture.desktop),
                       "outside")
        XCTAssertThrowsError(try runGit(["show", "\(envelope.result.integrationCommitID):outside-draft.md"], at: fixture.desktop))
        XCTAssertEqual(try Data(contentsOf: fixture.desktop.appendingPathComponent(".git/index")), indexBefore)
        XCTAssertEqual(try runGitData(["status", "--porcelain=v2", "-z", "--untracked-files=all"], at: fixture.desktop), statusBefore)

        let remote = try runGit(["ls-remote", "--refs", "origin", envelope.integrationRef.name], at: fixture.desktop)
        XCTAssertTrue(remote.contains(envelope.result.integrationCommitID))
        let outbox = DesktopGitIntegrationOutboxStore(root: fixture.root.appendingPathComponent("state/GitIntegrationOutbox"))
        let remaining = try await outbox.all()
        XCTAssertTrue(remaining.isEmpty)
    }

    func testPublisherUsesLaterOutOfScopeHeadAsSourceRevision() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let receipt = try makeReceipt(fixture: fixture, content: "merged")

        // Advance the desktop source after the proposal was captured. `--only`
        // commits the outside-scope file while retaining the staged sentinel.
        try Data("desktop outside".utf8).write(to: fixture.desktop.appendingPathComponent("outside.md"))
        try runGit(["commit", "--only", "outside.md", "-m", "desktop outside-only"], at: fixture.desktop)
        let sourceRevision = try runGit(["rev-parse", "HEAD"], at: fixture.desktop)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertNotEqual(sourceRevision, fixture.headID)
        let indexBefore = try Data(contentsOf: fixture.desktop.appendingPathComponent(".git/index"))
        let statusBefore = try runGitData(["status", "--porcelain=v2", "-z", "--untracked-files=all"], at: fixture.desktop)
        XCTAssertTrue(String(decoding: statusBefore, as: UTF8.self).contains("outside-staged.md"))

        let lease = NativeReconciliationLease()
        lease.sessions = { [] }
        let publisher = DesktopGitIntegrationPublisher(projectRoot: fixture.desktop,
                                                        stateRoot: fixture.root.appendingPathComponent("state"),
                                                        lease: lease)
        let identity = try GitCommitIdentity(name: "Desktop Fixture", email: "fixture@example.invalid", timestamp: 7)

        let envelope = try await publisher.publish(receipt: receipt, remoteName: "origin", identity: identity)
        XCTAssertEqual(envelope.result.sourceRevision, sourceRevision)
        XCTAssertNotEqual(envelope.result.sourceRevision, envelope.result.baseRevision)
        XCTAssertEqual(envelope.result.baseRevision, fixture.headID)
        XCTAssertEqual(envelope.result.proposalCommitID, fixture.headID)
        XCTAssertEqual(envelope.result.parentCommitID, fixture.headID)
        XCTAssertEqual(try runGit(["rev-parse", "\(envelope.result.integrationCommitID)^"], at: fixture.desktop),
                       fixture.headID + "\n")
        XCTAssertEqual(try runGit(["rev-parse", "\(envelope.result.integrationCommitID)^{tree}"], at: fixture.desktop),
                       envelope.result.treeID + "\n")

        // The integrated tree uses the later desktop tree as its basis while
        // replacing only the reviewed scope with the accepted receipt bytes.
        XCTAssertEqual(try runGit(["show", "\(envelope.result.integrationCommitID):docs/note.md"], at: fixture.desktop), "merged")
        XCTAssertEqual(try runGit(["show", "\(envelope.result.integrationCommitID):docs/keep.md"], at: fixture.desktop), "keep")
        XCTAssertEqual(try runGit(["show", "\(envelope.result.integrationCommitID):outside.md"], at: fixture.desktop), "desktop outside")
        XCTAssertThrowsError(try runGit(["show", "\(envelope.result.integrationCommitID):outside-draft.md"], at: fixture.desktop))
        XCTAssertEqual(try Data(contentsOf: fixture.desktop.appendingPathComponent(".git/index")), indexBefore)
        XCTAssertEqual(try runGitData(["status", "--porcelain=v2", "-z", "--untracked-files=all"], at: fixture.desktop),
                       statusBefore)
    }

    func testFailedPushKeepsExactOutboxAndRetryPublishesSameCommit() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let receipt = try makeReceipt(fixture: fixture, content: "retry")
        let hook = fixture.remote.appendingPathComponent("hooks/pre-receive")
        try Data("#!/bin/sh\nexit 1\n".utf8).write(to: hook)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: hook.path)
        let lease = NativeReconciliationLease()
        lease.sessions = { [] }
        let stateRoot = fixture.root.appendingPathComponent("state")
        let publisher = DesktopGitIntegrationPublisher(projectRoot: fixture.desktop,
                                                        stateRoot: stateRoot, lease: lease)
        let identity = try GitCommitIdentity(name: "Desktop Fixture", email: "fixture@example.invalid", timestamp: 4)

        do {
            _ = try await publisher.publish(receipt: receipt, remoteName: "origin", identity: identity)
            XCTFail("The rejecting receive hook accepted the push")
        } catch {
            XCTAssertTrue(error is DesktopGitIntegrationError)
        }
        let outbox = DesktopGitIntegrationOutboxStore(root: stateRoot.appendingPathComponent("GitIntegrationOutbox"))
        let pending = try await outbox.all()
        let pendingEntry = try XCTUnwrap(pending.first)
        let exactID = pendingEntry.envelope.result.integrationCommitID
        XCTAssertEqual(pendingEntry.envelope.receipt, receipt)
        XCTAssertEqual(try runGit(["rev-parse", pendingEntry.localRef], at: fixture.desktop), exactID + "\n")

        try FileManager.default.removeItem(at: hook)
        let retried = try await publisher.retryPending()
        XCTAssertEqual(retried.map(\.result.integrationCommitID), [exactID])
        let remaining = try await outbox.all()
        XCTAssertTrue(remaining.isEmpty)
        XCTAssertTrue(try runGit(["ls-remote", "--refs", "origin", pendingEntry.localRef], at: fixture.desktop)
            .contains(exactID))
    }

    func testHistoricalDeletionWinsWhenThePathWasRecreatedAfterReceipt() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let receipt = try makeDeletionReceipt(fixture: fixture)
        try Data("recreated after review".utf8).write(to: fixture.desktop.appendingPathComponent("docs/note.md"))
        let indexBefore = try Data(contentsOf: fixture.desktop.appendingPathComponent(".git/index"))
        let statusBefore = try runGitData(["status", "--porcelain=v2", "-z", "--untracked-files=all"], at: fixture.desktop)
        let lease = NativeReconciliationLease()
        lease.sessions = { [] }
        let publisher = DesktopGitIntegrationPublisher(projectRoot: fixture.desktop,
                                                        stateRoot: fixture.root.appendingPathComponent("state"),
                                                        lease: lease)
        let identity = try GitCommitIdentity(name: "Desktop Fixture", email: "fixture@example.invalid", timestamp: 5)

        let envelope = try await publisher.publish(receipt: receipt, remoteName: "origin", identity: identity)
        XCTAssertEqual(try runGit(["show", "\(envelope.integrationCommitID):docs/keep.md"], at: fixture.desktop),
                       "keep")
        XCTAssertThrowsError(try runGit(["show", "\(envelope.integrationCommitID):docs/note.md"], at: fixture.desktop))
        XCTAssertEqual(try Data(contentsOf: fixture.desktop.appendingPathComponent("docs/note.md")),
                       Data("recreated after review".utf8))
        XCTAssertEqual(try Data(contentsOf: fixture.desktop.appendingPathComponent(".git/index")), indexBefore)
        XCTAssertEqual(try runGitData(["status", "--porcelain=v2", "-z", "--untracked-files=all"], at: fixture.desktop),
                       statusBefore)
    }

    func testIntegrationCommitAllowsSecondMobileProposalFastForwardAndPreservesDeletion() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let proposalBranch = GitDeviceBranch.name(deviceID: fixture.deviceID, projectID: fixture.projectID)
        // The mobile proposal branch is still at the exact publication commit
        // while the desktop reviews it. The integration commit must descend
        // from that tip so the next mobile proposal can fast-forward it.
        try runGit(["--git-dir", fixture.remote.path, "update-ref", proposalBranch, fixture.headID],
                   at: fixture.root)

        let indexBefore = try Data(contentsOf: fixture.desktop.appendingPathComponent(".git/index"))
        let statusBefore = try runGitData(["status", "--porcelain=v2", "-z", "--untracked-files=all"], at: fixture.desktop)
        let lease = NativeReconciliationLease()
        lease.sessions = { [] }
        let publisher = DesktopGitIntegrationPublisher(projectRoot: fixture.desktop,
                                                        stateRoot: fixture.root.appendingPathComponent("state"),
                                                        lease: lease)
        let identity = try GitCommitIdentity(name: "Desktop Fixture", email: "fixture@example.invalid", timestamp: 6)

        let integration = try await publisher.publish(
            receipt: makeDeletionReceipt(fixture: fixture), remoteName: "origin", identity: identity)
        XCTAssertEqual(integration.result.sourceRevision, fixture.headID)
        XCTAssertEqual(try runGit(["rev-parse", "\(integration.result.integrationCommitID)^"], at: fixture.desktop)
            .trimmingCharacters(in: .whitespacesAndNewlines), fixture.headID)
        XCTAssertThrowsError(try runGit(["show", "\(integration.result.integrationCommitID):docs/note.md"],
                                        at: fixture.desktop))

        // A separate mobile checkout starts from the published integration
        // tree, changes one selected file, and pushes the next proposal to the
        // original per-device branch. Its commit remains a descendant of the
        // old proposal through the desktop integration commit.
        let mobile = fixture.root.appendingPathComponent("mobile", isDirectory: true)
        try runGit(["clone", "--branch", "main", fixture.remote.path, mobile.path], at: fixture.root)
        try runGit(["config", "user.name", "Mobile Fixture"], at: mobile)
        try runGit(["config", "user.email", "mobile@example.invalid"], at: mobile)
        try runGit(["fetch", "origin", integration.integrationRef.name + ":" + integration.integrationRef.name], at: mobile)
        try runGit(["checkout", "-B", "next-proposal", integration.result.integrationCommitID], at: mobile)
        try Data("mobile update".utf8).write(to: mobile.appendingPathComponent("docs/keep.md"))
        try runGit(["add", "docs/keep.md"], at: mobile)
        try runGit(["commit", "-m", "mobile follow-up"], at: mobile)
        let secondProposalID = try runGit(["rev-parse", "HEAD"], at: mobile)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        try runGit(["push", "origin", "HEAD:\(proposalBranch)"], at: mobile)

        XCTAssertEqual(try runGit(["--git-dir", fixture.remote.path, "rev-parse", proposalBranch], at: fixture.root)
            .trimmingCharacters(in: .whitespacesAndNewlines), secondProposalID)
        XCTAssertEqual(try runGit(["rev-parse", "\(secondProposalID)^"], at: mobile)
            .trimmingCharacters(in: .whitespacesAndNewlines), integration.result.integrationCommitID)
        XCTAssertEqual(try runGit(["merge-base", "--is-ancestor", integration.result.integrationCommitID,
                                   secondProposalID], at: mobile), "")
        XCTAssertEqual(try runGit(["show", "\(secondProposalID):docs/keep.md"], at: mobile), "mobile update")
        XCTAssertThrowsError(try runGit(["show", "\(secondProposalID):docs/note.md"], at: mobile))
        XCTAssertEqual(try runGit(["show", "\(secondProposalID):outside.md"], at: mobile), "outside")

        // Publishing and mobile work use separate checkouts; the desktop's
        // staged index and later out-of-scope files must remain byte-for-byte
        // unchanged after the full round trip.
        XCTAssertEqual(try Data(contentsOf: fixture.desktop.appendingPathComponent(".git/index")), indexBefore)
        XCTAssertEqual(try runGitData(["status", "--porcelain=v2", "-z", "--untracked-files=all"], at: fixture.desktop),
                       statusBefore)
        XCTAssertEqual(try Data(contentsOf: fixture.desktop.appendingPathComponent("outside.md")),
                       Data("local outside".utf8))
        XCTAssertEqual(try Data(contentsOf: fixture.desktop.appendingPathComponent("outside-draft.md")),
                       Data("draft outside".utf8))
    }

    private struct Fixture {
        let root: URL
        let remote: URL
        let desktop: URL
        let projectID: UUID
        let deviceID: UUID
        let headID: String
    }

    private func makeReceipt(fixture: Fixture, content: String) throws -> GitIntegrationReceipt {
        let scope = try CorpusScope(folder: "docs")
        let accepted = CorpusSnapshot(revision: fixture.headID, files: [
            CorpusFile(path: "docs/keep.md", content: Data("keep".utf8)),
            CorpusFile(path: "docs/note.md", content: Data(content.utf8)),
        ])
        return try GitIntegrationReceipt(
            projectID: fixture.projectID, deviceID: fixture.deviceID,
            branch: GitDeviceBranch.name(deviceID: fixture.deviceID, projectID: fixture.projectID),
            commitID: fixture.headID, baseRevision: fixture.headID,
            scope: scope, accepted: accepted)
    }

    private func makeDeletionReceipt(fixture: Fixture) throws -> GitIntegrationReceipt {
        let scope = try CorpusScope(folder: "docs")
        let accepted = CorpusSnapshot(revision: fixture.headID, files: [
            CorpusFile(path: "docs/keep.md", content: Data("keep".utf8)),
        ])
        return try GitIntegrationReceipt(
            projectID: fixture.projectID, deviceID: fixture.deviceID,
            branch: GitDeviceBranch.name(deviceID: fixture.deviceID, projectID: fixture.projectID),
            commitID: fixture.headID, baseRevision: fixture.headID,
            scope: scope, accepted: accepted)
    }

    private func makeFixture() throws -> Fixture {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let remote = root.appendingPathComponent("remote.git", isDirectory: true)
        let source = root.appendingPathComponent("source", isDirectory: true)
        let desktop = root.appendingPathComponent("desktop", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try runGit(["init", "--bare", remote.path], at: root)
        try runGit(["init", source.path], at: root)
        try runGit(["config", "user.name", "Fixture"], at: source)
        try runGit(["config", "user.email", "fixture@example.invalid"], at: source)
        try FileManager.default.createDirectory(at: source.appendingPathComponent("docs"), withIntermediateDirectories: true)
        try Data("keep".utf8).write(to: source.appendingPathComponent("docs/keep.md"))
        try Data("old".utf8).write(to: source.appendingPathComponent("docs/note.md"))
        try Data("outside".utf8).write(to: source.appendingPathComponent("outside.md"))
        try runGit(["add", "."], at: source)
        try runGit(["commit", "-m", "base"], at: source)
        let headID = try runGit(["rev-parse", "HEAD"], at: source).trimmingCharacters(in: .whitespacesAndNewlines)
        try runGit(["branch", "-M", "main"], at: source)
        try runGit(["remote", "add", "origin", remote.path], at: source)
        try runGit(["push", "origin", "main:main"], at: source)
        try runGit(["clone", "--branch", "main", remote.path, desktop.path], at: root)
        try Data("staged".utf8).write(to: desktop.appendingPathComponent("outside-staged.md"))
        try runGit(["add", "outside-staged.md"], at: desktop)
        try Data("local outside".utf8).write(to: desktop.appendingPathComponent("outside.md"))
        try Data("draft outside".utf8).write(to: desktop.appendingPathComponent("outside-draft.md"))
        let projectID = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
        let deviceID = UUID(uuidString: "22222222-2222-4222-8222-222222222222")!
        return Fixture(root: root, remote: remote, desktop: desktop,
                       projectID: projectID, deviceID: deviceID, headID: headID)
    }

    private func runGit(_ arguments: [String], at root: URL, input: Data? = nil) throws -> String {
        String(decoding: try runGitData(arguments, at: root, input: input), as: UTF8.self)
    }

    private func runGitData(_ arguments: [String], at root: URL, input: Data? = nil) throws -> Data {
        try DesktopGitProcessTestSupport.run(arguments: arguments, at: root, input: input)
    }
}
#endif
