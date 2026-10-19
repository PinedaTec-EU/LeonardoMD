import XCTest
import Foundation
import LeonardoCore
@testable import LeonardoApp

@MainActor
final class SessionPackageSaveTests: XCTestCase {
    private final class PackageArchiveCommitGate: @unchecked Sendable {
        let reached: XCTestExpectation
        private let release = DispatchSemaphore(value: 0)

        init(reached: XCTestExpectation) {
            self.reached = reached
        }

        func pause() {
            reached.fulfill()
            release.wait()
        }

        func open() {
            release.signal()
        }
    }

    @MainActor private struct PackageFixture {
        let root: URL
        let template: URL
        let package: URL
        let source: String
        let tabs: DocumentTabs

        var session: AppSession { tabs.activeSession }
    }

    private func documentSource(body: String) throws -> String {
        try LeonardoFormatParser.serialize(
            LeonardoDocument(
                body: body,
                metadata: LeonardoMetadata(
                    document: LeonardoDocumentDescriptor(title: "Request", kind: .form),
                    fields: ["name": LeonardoFieldDefinition(required: true)]
                )
            )
        )
    }

    private func packageFixture() async throws -> PackageFixture {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("LeonardoPackageSave-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let tabs = DocumentTabs(preferencesURL: root.appendingPathComponent("preferences.json"))
        let session = tabs.activeSession
        session.authorizePath = { _, _ in }
        let template = root.appendingPathComponent("request.mdlf")
        let package = root.appendingPathComponent("request.mdlz")
        let source = try documentSource(body: "Name: {{field:name}}")
        try source.write(to: template, atomically: true, encoding: .utf8)
        try LeonardoPackageTransport.export(documentURL: template, content: source, to: package)
        let opened = await session.openLeonardoPackage(package, extractingTo: nil)
        XCTAssertTrue(opened)
        return PackageFixture(root: root, template: template, package: package, source: source, tabs: tabs)
    }

    func testAcceptedCloseJoinsPackageRetirementBeforeReturning() async throws {
        let fixture = try await packageFixture()
        let session = fixture.session
        let workspace = try XCTUnwrap(session.packageWorkspace)
        defer { fixture.tabs.stop(); try? FileManager.default.removeItem(at: fixture.root) }
        let prepared = await fixture.tabs.prepareClose()
        XCTAssertTrue(prepared)
        XCTAssertTrue(FileManager.default.fileExists(atPath: workspace.directoryURL.path))
        await fixture.tabs.finishPreparedClose()
        XCTAssertTrue(session.stopped)
        XCTAssertFalse(FileManager.default.fileExists(atPath: workspace.directoryURL.path))
    }

    func testCancelledClosePreservesPackageWorkspace() async throws {
        let fixture = try await packageFixture()
        let session = fixture.session
        let workspace = try XCTUnwrap(session.packageWorkspace)
        defer { fixture.tabs.stop(); try? FileManager.default.removeItem(at: fixture.root) }
        let prepared = await fixture.tabs.prepareClose()
        XCTAssertTrue(prepared)
        fixture.tabs.cancelPreparedClose()
        await fixture.tabs.finishPreparedClose()
        XCTAssertFalse(session.stopped)
        XCTAssertEqual(session.packageWorkspace?.directoryURL, workspace.directoryURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: workspace.documentURL.path))
        XCTAssertEqual(session.content, fixture.source)
    }

    func testDirectPackageRevocationMatchesDurableSourceArchive() async throws {
        let fixture = try await packageFixture()
        let session = fixture.session
        defer { fixture.tabs.stop(); try? FileManager.default.removeItem(at: fixture.root) }
        let workspace = try XCTUnwrap(session.packageWorkspace)
        let packageBefore = try Data(contentsOf: fixture.package)

        XCTAssertNil(session.projectURL)
        XCTAssertEqual(session.documentSourceURL?.standardizedFileURL, fixture.package.standardizedFileURL)

        await fixture.tabs.revokeWorkspaces([fixture.root])

        XCTAssertTrue(session.stopped)
        XCTAssertFalse(fixture.tabs.tabs.contains { $0.session === session })
        XCTAssertNil(session.documentURL)
        XCTAssertNil(session.documentSourceURL)
        XCTAssertNil(session.packageWorkspace)
        XCTAssertEqual(session.content, "")
        XCTAssertFalse(FileManager.default.fileExists(atPath: workspace.directoryURL.path))
        XCTAssertEqual(try Data(contentsOf: fixture.package), packageBefore)
    }

    func testRevocationWaitsForPausedPackageRepackAndCancelsBeforeCommit() async throws {
        let fixture = try await packageFixture()
        let session = fixture.session
        let workspace = try XCTUnwrap(session.packageWorkspace)
        let packageBefore = try Data(contentsOf: fixture.package)
        let draft = try documentSource(body: "Draft: {{field:name}}")
        let reached = expectation(description: "package archive commit paused")
        let gate = PackageArchiveCommitGate(reached: reached)
        defer {
            gate.open()
            session.beforePackageArchiveCommitForTesting = nil
            fixture.tabs.stop()
            try? FileManager.default.removeItem(at: fixture.root)
        }

        session.beforePackageArchiveCommitForTesting = { gate.pause() }
        session.content = draft
        session.contentChanged()
        let save = Task { @MainActor in await session.save() }
        await fulfillment(of: [reached], timeout: 2)

        let revocation = Task { @MainActor in
            await fixture.tabs.revokeWorkspaces([fixture.root])
        }
        while !session.stopped { await Task.yield() }
        for _ in 0..<20 { await Task.yield() }

        XCTAssertTrue(FileManager.default.fileExists(atPath: workspace.directoryURL.path))
        XCTAssertEqual(try Data(contentsOf: fixture.package), packageBefore)

        gate.open()
        await revocation.value
        await save.value

        XCTAssertFalse(FileManager.default.fileExists(atPath: workspace.directoryURL.path))
        XCTAssertEqual(try Data(contentsOf: fixture.package), packageBefore)
        XCTAssertNil(session.documentURL)
        XCTAssertNil(session.snapshot)
        XCTAssertEqual(session.content, "")
    }

    func testStopWaitsForPausedPackageRepackBeforeDisposal() async throws {
        let fixture = try await packageFixture()
        let session = fixture.session
        let workspace = try XCTUnwrap(session.packageWorkspace)
        let packageBefore = try Data(contentsOf: fixture.package)
        let reached = expectation(description: "package commit paused before stop")
        let gate = PackageArchiveCommitGate(reached: reached)
        defer {
            gate.open()
            fixture.tabs.stop()
            try? FileManager.default.removeItem(at: fixture.root)
        }
        session.beforePackageArchiveCommitForTesting = { gate.pause() }
        session.content = try documentSource(body: "Draft to cancel")
        let save = Task { await session.save() }
        await fulfillment(of: [reached], timeout: 2)
        session.stop()
        XCTAssertTrue(FileManager.default.fileExists(atPath: workspace.directoryURL.path))
        gate.open()
        await save.value
        await session.waitForPackageWorkspaceDisposal()
        XCTAssertFalse(FileManager.default.fileExists(atPath: workspace.directoryURL.path))
        XCTAssertEqual(try Data(contentsOf: fixture.package), packageBefore)
    }

    func testSaveAbortsBeforeWritingWhenAuthorizationChangesLocalIdentity() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("LeonardoLocalSave-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let tabs = DocumentTabs(preferencesURL: root.appendingPathComponent("preferences.json"))
        let session = tabs.activeSession
        defer { tabs.stop(); try? FileManager.default.removeItem(at: root) }

        let source = root.appendingPathComponent("source.md")
        let other = root.appendingPathComponent("other.md")
        try "original".write(to: source, atomically: true, encoding: .utf8)
        try "other".write(to: other, atomically: true, encoding: .utf8)
        await session.open(source)
        let otherSnapshot = try await session.documents.read(other)
        let original = try XCTUnwrap(session.snapshot)
        session.content = "draft"
        session.contentChanged()

        session.authorizePath = { url, _ in
            guard url.standardizedFileURL == source.standardizedFileURL else { return }
            session.documentURL = other
            session.documentSourceURL = nil
            session.documentKind = .markdown
            session.documentStorage = .localFile
            session.packageWorkspace = nil
            session.snapshot = otherSnapshot
            session.content = otherSnapshot.content
        }

        await session.save()

        XCTAssertEqual(try String(contentsOf: source, encoding: .utf8), original.content)
        XCTAssertEqual(session.documentURL?.standardizedFileURL, other.standardizedFileURL)
        XCTAssertEqual(session.snapshot, otherSnapshot)
        XCTAssertEqual(session.content, otherSnapshot.content)
        XCTAssertFalse(session.saving)
        XCTAssertNotEqual(session.saveStatus, "Saving…")
    }

    func testPackageSaveAbortsBeforeWorkingWriteWhenWorkspaceChanges() async throws {
        let fixture = try await packageFixture()
        let session = fixture.session
        defer { fixture.tabs.stop(); try? FileManager.default.removeItem(at: fixture.root) }
        let workspace = try XCTUnwrap(session.packageWorkspace)
        let workingBefore = try Data(contentsOf: workspace.documentURL)
        let packageBefore = try Data(contentsOf: fixture.package)
        let draft = try documentSource(body: "Draft: {{field:name}}")
        session.content = draft
        session.contentChanged()
        let replacement = fixture.root.appendingPathComponent("replacement.mdlz")

        session.authorizePath = { url, _ in
            guard url.standardizedFileURL == fixture.package.standardizedFileURL else { return }
            session.packageWorkspace = LeonardoPackageTransport.relocating(workspace, to: replacement)
        }

        await session.save()

        XCTAssertEqual(try Data(contentsOf: fixture.package), packageBefore)
        XCTAssertEqual(try Data(contentsOf: workspace.documentURL), workingBefore)
        XCTAssertEqual(session.content, draft)
        XCTAssertEqual(session.snapshot?.content, fixture.source)
        XCTAssertTrue(session.isDirty)
        XCTAssertFalse(session.saving)
        XCTAssertNotEqual(session.saveStatus, "Saving…")
    }

    func testPackageSaveRollsBackWorkingDocumentWhenWorkspaceChangesBeforeRepack() async throws {
        let fixture = try await packageFixture()
        let session = fixture.session
        defer { fixture.tabs.stop(); try? FileManager.default.removeItem(at: fixture.root) }
        let workspace = try XCTUnwrap(session.packageWorkspace)
        let workingBefore = try Data(contentsOf: workspace.documentURL)
        let packageBefore = try Data(contentsOf: fixture.package)
        let draft = try documentSource(body: "Draft: {{field:name}}")
        session.content = draft
        session.contentChanged()
        let replacement = fixture.root.appendingPathComponent("replacement-after-write.mdlz")
        var packageAuthorizationCount = 0

        session.authorizePath = { url, _ in
            guard url.standardizedFileURL == fixture.package.standardizedFileURL else { return }
            packageAuthorizationCount += 1
            guard packageAuthorizationCount == 2 else { return }
            session.packageWorkspace = LeonardoPackageTransport.relocating(workspace, to: replacement)
        }

        await session.save()

        XCTAssertEqual(packageAuthorizationCount, 2)
        XCTAssertEqual(try Data(contentsOf: fixture.package), packageBefore)
        XCTAssertEqual(try Data(contentsOf: workspace.documentURL), workingBefore)
        XCTAssertEqual(session.content, draft)
        XCTAssertEqual(session.snapshot?.content, fixture.source)
        XCTAssertTrue(session.isDirty)
        XCTAssertFalse(session.saving)
        XCTAssertNotEqual(session.saveStatus, "Saving…")
    }

    func testPackageSaveKeepsNewerDraftAfterRepackGuardAndRetriesWithoutConflict() async throws {
        let fixture = try await packageFixture()
        let session = fixture.session
        defer { fixture.tabs.stop(); try? FileManager.default.removeItem(at: fixture.root) }
        let workspace = try XCTUnwrap(session.packageWorkspace)
        let workingBefore = try Data(contentsOf: workspace.documentURL)
        let packageBefore = try Data(contentsOf: fixture.package)
        let initialSnapshot = try XCTUnwrap(session.snapshot)
        let firstDraft = try documentSource(body: "Name: first")
        let newerDraft = try documentSource(body: "Name: newfield")
        session.content = firstDraft
        session.contentChanged()
        var packageAuthorizationCount = 0

        session.authorizePath = { url, _ in
            guard url.standardizedFileURL == fixture.package.standardizedFileURL else { return }
            packageAuthorizationCount += 1
            if packageAuthorizationCount == 2 {
                session.content = newerDraft
                session.contentChanged()
            }
        }

        await session.save()

        XCTAssertEqual(packageAuthorizationCount, 2)
        XCTAssertEqual(try Data(contentsOf: fixture.package), packageBefore)
        XCTAssertEqual(try Data(contentsOf: workspace.documentURL), workingBefore)
        XCTAssertEqual(session.content, newerDraft)
        XCTAssertEqual(session.snapshot?.content, fixture.source)
        XCTAssertEqual(session.snapshot?.url, initialSnapshot.url)
        XCTAssertTrue(session.isDirty)
        XCTAssertFalse(session.externalConflict)
        XCTAssertFalse(session.saving)
        XCTAssertNotEqual(session.saveStatus, "Saving…")

        session.authorizePath = { _, _ in }
        await session.save()

        XCTAssertFalse(session.isDirty)
        XCTAssertFalse(session.externalConflict)
        XCTAssertEqual(session.snapshot?.content, newerDraft)
        let reopened = try LeonardoPackageTransport.open(fixture.package)
        defer { LeonardoPackageTransport.discard(reopened) }
        let reopenedDocument = try LeonardoFormatParser.parse(
            String(contentsOf: reopened.documentURL, encoding: .utf8)
        )
        XCTAssertEqual(reopenedDocument.body, "Name: newfield")
    }

    func testPackageConflictReloadsFreshWorkspaceThenSavesLatestPackage() async throws {
        let fixture = try await packageFixture()
        let session = fixture.session
        defer { fixture.tabs.stop(); try? FileManager.default.removeItem(at: fixture.root) }
        let oldWorkspace = try XCTUnwrap(session.packageWorkspace)
        let oldDirectory = oldWorkspace.directoryURL
        let latest = try documentSource(body: "Latest: {{field:name}}")
        try LeonardoPackageTransport.export(
            documentURL: fixture.template,
            content: latest,
            to: fixture.package
        )
        let draft = try documentSource(body: "Unsaved: {{field:name}}")
        session.content = draft
        session.contentChanged()

        await session.save()

        XCTAssertTrue(session.externalConflict)
        XCTAssertEqual(session.content, draft)
        XCTAssertTrue(FileManager.default.fileExists(atPath: oldDirectory.path))

        session.confirmDiscardForReload = { true }
        try Data("not a package".utf8).write(to: fixture.package, options: .atomic)
        await session.reloadFromDisk()

        XCTAssertTrue(session.externalConflict)
        XCTAssertEqual(session.content, draft)
        XCTAssertEqual(session.packageWorkspace?.directoryURL.standardizedFileURL, oldDirectory.standardizedFileURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: oldDirectory.path))

        try LeonardoPackageTransport.export(
            documentURL: fixture.template,
            content: latest,
            to: fixture.package
        )
        await session.reloadFromDisk()

        let refreshed = try XCTUnwrap(session.packageWorkspace)
        XCTAssertFalse(session.externalConflict)
        XCTAssertEqual(session.content, latest)
        XCTAssertEqual(refreshed.packageURL?.standardizedFileURL, fixture.package.standardizedFileURL)
        XCTAssertNotEqual(refreshed.directoryURL.standardizedFileURL, oldDirectory.standardizedFileURL)
        XCTAssertFalse(FileManager.default.fileExists(atPath: oldDirectory.path))

        let saved = try documentSource(body: "Saved: {{field:name}}")
        session.content = saved
        session.contentChanged()
        await session.save()
        XCTAssertFalse(session.isDirty)
        XCTAssertFalse(session.externalConflict)

        let reopened = try LeonardoPackageTransport.open(fixture.package)
        defer { LeonardoPackageTransport.discard(reopened) }
        let reopenedSource = try String(contentsOf: reopened.documentURL, encoding: .utf8)
        XCTAssertEqual(try LeonardoFormatParser.parse(reopenedSource).body, "Saved: {{field:name}}")
    }
}
