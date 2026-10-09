#if os(macOS)
import AppKit
import Foundation
import SwiftUI
import XCTest
@testable import LeonardoGit
import LeonardoSync
@testable import LeonardoApp

@MainActor
final class DesktopGitControllerTests: XCTestCase {
    func testControllerAppliesExactScopedPublicationWithoutTouchingIndexOrOutsideFiles() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        let state = fixture.root.appendingPathComponent("state", isDirectory: true)
        let selection = try CorpusSelection(folders: ["docs"], documents: [])
        let indexBefore = try Data(contentsOf: fixture.desktop.appendingPathComponent(".git/index"))
        let statusBefore = try runGit(["status", "--porcelain=v2", "-z", "--branch", "--untracked-files=all"], at: fixture.desktop)

        let lease = NativeReconciliationLease.shared
        let previousSessions = lease.sessions
        lease.sessions = { [] }
        defer { lease.sessions = previousSessions }

        var notified: GitIntegrationReceipt?
        let controller = DesktopGitController(
            projectRoot: fixture.desktop,
            stateRoot: state,
            lease: lease,
            notice: { receipt in notified = receipt })

        await controller.refreshRemotes()
        XCTAssertEqual(controller.selectedRemote, "origin")
        await controller.fetchPublications()
        let branch = try XCTUnwrap(controller.branches.first)
        XCTAssertEqual(branch.name, fixture.branch)
        XCTAssertEqual(branch.commitID, fixture.publicationID)

        await controller.inspectSelectedBranch()
        XCTAssertEqual(controller.proposalMetadata?.baseRevision, fixture.baseID)
        XCTAssertEqual(controller.proposalMetadata?.scope.folder, "docs")
        XCTAssertEqual(controller.proposalMetadata?.purpose, .normalChanges)

        await controller.approveScope()
        let review = try XCTUnwrap(controller.review)
        XCTAssertEqual(review.commitID, fixture.publicationID)
        XCTAssertEqual(review.scope.folder, "docs")
        try await captureReviewEvidenceIfRequested(controller: controller, review: review)

        // Advance both visible refs after review. The local review must continue
        // applying the captured publication commit, never a re-read branch tip.
        try runGit(["update-ref", fixture.branch, fixture.baseID], at: fixture.remote)
        try runGit(["update-ref", fixture.branch, fixture.baseID], at: fixture.desktop)
        let applied = await controller.apply(decisions: ["docs/note.md": .remote])
        XCTAssertTrue(applied)

        XCTAssertEqual(notified?.commitID, fixture.publicationID)
        let receipts = GitIntegrationReceiptStore(root: state.appendingPathComponent("Receipts"))
        let stored = try await receipts.load(projectID: fixture.projectID, deviceID: fixture.deviceID,
                                              commitID: fixture.publicationID)
        XCTAssertEqual(stored?.commitID, fixture.publicationID)
        XCTAssertEqual(stored?.baseRevision, fixture.baseID)
        let expectedScope = try CorpusScope(folder: "docs")
        XCTAssertEqual(stored?.scope, expectedScope)

        let integrationRef = try GitIntegrationRef(deviceID: fixture.deviceID,
                                                    projectID: fixture.projectID,
                                                    proposalCommitID: fixture.publicationID)
        let integrationID = try runGit(["rev-parse", integrationRef.name], at: fixture.desktop)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertEqual(try runGit(["rev-parse", "\(integrationID)^"], at: fixture.desktop),
                       fixture.publicationID + "\n")

        XCTAssertEqual(try Data(contentsOf: fixture.desktop.appendingPathComponent("docs/note.md")), Data("remote".utf8))
        XCTAssertEqual(try Data(contentsOf: fixture.desktop.appendingPathComponent("docs/keep.md")), Data("keep".utf8))
        XCTAssertEqual(try Data(contentsOf: fixture.desktop.appendingPathComponent("outside.md")), Data("local outside".utf8))
        XCTAssertEqual(try Data(contentsOf: fixture.desktop.appendingPathComponent("outside-draft.md")), Data("draft outside".utf8))
        XCTAssertEqual(try Data(contentsOf: fixture.desktop.appendingPathComponent("outside-staged.md")), Data("staged".utf8))
        XCTAssertEqual(try Data(contentsOf: fixture.desktop.appendingPathComponent(".git/index")), indexBefore)

        let statusAfter = try runGit(["status", "--porcelain=v2", "-z", "--branch", "--untracked-files=all"], at: fixture.desktop)
        XCTAssertTrue(statusAfter.contains("docs/note.md"))
        XCTAssertTrue(statusAfter.contains("outside-staged.md"))
        XCTAssertTrue(statusAfter.contains("outside-draft.md"))
        XCTAssertFalse(statusBefore.contains("docs/note.md"))
    }

    private struct Fixture {
        let root: URL
        let remote: URL
        let desktop: URL
        let projectID: UUID
        let deviceID: UUID
        let branch: String
        let baseID: String
        let publicationID: String
    }

    private func makeFixture() throws -> Fixture {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let remote = root.appendingPathComponent("remote.git", isDirectory: true)
        let source = root.appendingPathComponent("source", isDirectory: true)
        let desktop = root.appendingPathComponent("desktop", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: desktop, withIntermediateDirectories: true)
        try runGit(["init", "--bare", remote.path], at: root)
        try runGit(["config", "uploadpack.allowFilter", "true"], at: remote)
        try runGit(["config", "uploadpack.allowAnySHA1InWant", "true"], at: remote)
        try runGit(["init"], at: source)

        let projectID = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
        let deviceID = UUID(uuidString: "22222222-2222-4222-8222-222222222222")!
        let scope = try CorpusScope(folder: "docs")
        let keep = GitObject.create(kind: .blob, data: Data("keep".utf8))
        let old = GitObject.create(kind: .blob, data: Data("old".utf8))
        let outside = GitObject.create(kind: .blob, data: Data("outside".utf8))
        let remoteNote = GitObject.create(kind: .blob, data: Data("remote".utf8))
        let docsBase = try GitTree.create(entries: [
            GitTreeEntry(name: "keep.md", objectID: keep.id, kind: .file, executable: false),
            GitTreeEntry(name: "note.md", objectID: old.id, kind: .file, executable: false)
        ], sha256: false)
        let rootBase = try GitTree.create(entries: [
            GitTreeEntry(name: "docs", objectID: docsBase.id, kind: .folder, executable: false),
            GitTreeEntry(name: "outside.md", objectID: outside.id, kind: .file, executable: false)
        ], sha256: false)
        let baseText = "tree \(rootBase.id)\nauthor Fixture <fixture@example.invalid> 1 +0000\n" +
            "committer Fixture <fixture@example.invalid> 1 +0000\n\nbase\n"
        let base = GitObject.create(kind: .commit, data: Data(baseText.utf8))
        let publicationMetadata = try GitPublicationMetadata(projectID: projectID, deviceID: deviceID,
                                                              baseRevision: base.id, scope: scope)
        let docsRemote = try GitTree.create(entries: [
            GitTreeEntry(name: "keep.md", objectID: keep.id, kind: .file, executable: false),
            GitTreeEntry(name: "note.md", objectID: remoteNote.id, kind: .file, executable: false)
        ], sha256: false)
        let rootRemote = try GitTree.create(entries: [
            GitTreeEntry(name: "docs", objectID: docsRemote.id, kind: .folder, executable: false),
            GitTreeEntry(name: "outside.md", objectID: outside.id, kind: .file, executable: false)
        ], sha256: false)
        var publicationHeaders = [
            "tree \(rootRemote.id)", "parent \(base.id)",
            "author Fixture <fixture@example.invalid> 2 +0000",
            "committer Fixture <fixture@example.invalid> 2 +0000"
        ]
        publicationHeaders.append(contentsOf: publicationMetadata.commitHeaders)
        let publicationText = publicationHeaders.joined(separator: "\n") + "\n\nremote publication\n"
        let publication = GitObject.create(kind: .commit, data: Data(publicationText.utf8))
        let branch = GitDeviceBranch.name(deviceID: deviceID, projectID: projectID)

        for object in [keep, old, outside, remoteNote, docsBase, rootBase, base, docsRemote, rootRemote, publication] {
            let written = try runGit(["hash-object", "-w", "--stdin", "-t", object.kind.rawValue], at: source, input: object.data)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            XCTAssertEqual(written, object.id)
        }
        try runGit(["symbolic-ref", "HEAD", "refs/heads/main"], at: source)
        try runGit(["update-ref", "refs/heads/main", base.id], at: source)
        try runGit(["update-ref", branch, publication.id], at: source)
        try runGit(["remote", "add", "origin", remote.path], at: source)
        try runGit(["push", "origin", "refs/heads/main:refs/heads/main", branch + ":" + branch], at: source)

        try runGit(["init"], at: desktop)
        try runGit(["config", "user.name", "Desktop Fixture"], at: desktop)
        try runGit(["config", "user.email", "fixture@example.invalid"], at: desktop)
        try runGit(["remote", "add", "origin", remote.path], at: desktop)
        try runGit(["fetch", "--no-tags", "origin", "refs/heads/main:refs/remotes/origin/main"], at: desktop)
        try runGit(["checkout", "-B", "main", "refs/remotes/origin/main"], at: desktop)
        try Data("staged".utf8).write(to: desktop.appendingPathComponent("outside-staged.md"))
        try runGit(["add", "outside-staged.md"], at: desktop)
        try Data("local outside".utf8).write(to: desktop.appendingPathComponent("outside.md"))
        try Data("draft outside".utf8).write(to: desktop.appendingPathComponent("outside-draft.md"))

        return Fixture(root: root, remote: remote, desktop: desktop, projectID: projectID, deviceID: deviceID,
                       branch: branch, baseID: base.id, publicationID: publication.id)
    }

    private func runGit(_ arguments: [String], at root: URL, input: Data? = nil) throws -> String {
        String(decoding: try runGitData(arguments, at: root, input: input), as: UTF8.self)
    }

    private func runGitData(_ arguments: [String], at root: URL, input: Data? = nil) throws -> Data {
        try DesktopGitProcessTestSupport.run(arguments: arguments, at: root, input: input)
    }

    private func captureReviewEvidenceIfRequested(controller: DesktopGitController,
                                                  review: DesktopGitReview) async throws {
        guard let path = ProcessInfo.processInfo.environment["LEONARDO_LOCALIZATION_EVIDENCE"] else { return }
        let destination = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let previous = LanguageSettings.shared.language
        defer { LanguageSettings.shared.language = previous }
        for language in AppLanguage.allCases {
            LanguageSettings.shared.language = language
            for width in [960, 1_020] {
                let host = NSHostingView(rootView: DesktopGitReviewView(controller: controller, value: review)
                    .background(Color(nsColor: .windowBackgroundColor)))
                try await capture(host, size: NSSize(width: width, height: 700),
                                  to: destination.appendingPathComponent("desktop-git-review-\(language.rawValue)-\(width).png"),
                                  settlingMilliseconds: 600)
            }
        }
    }

    private func capture(_ view: NSView, size: NSSize, to url: URL,
                         settlingMilliseconds: Int) async throws {
        view.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.title = "Leonardo Git review QA"
        window.isReleasedWhenClosed = false
        window.contentView = view
        window.orderFront(nil)
        defer { window.close() }
        try await Task.sleep(for: .milliseconds(settlingMilliseconds))
        view.layoutSubtreeIfNeeded()
        view.displayIfNeeded()
        let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        try png.write(to: url)
    }
}
#endif
