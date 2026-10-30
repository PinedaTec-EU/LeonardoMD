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

    private func packageFixture(withImage: Bool = false) async throws -> PackageFixture {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("LeonardoPackageSave-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let tabs = DocumentTabs(preferencesURL: root.appendingPathComponent("preferences.json"))
        let session = tabs.activeSession
        session.authorizePath = { _, _ in }
        let template = root.appendingPathComponent("request.mdlf")
        let package = root.appendingPathComponent("request.mdlz")
        let source = try documentSource(body: "Name: {{field:name}}" + (withImage ? "\n\n![Blue](assets/blue.svg)" : ""))
        if withImage {
            let assets = root.appendingPathComponent("assets", isDirectory: true)
            try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
            try Data("<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"10\" height=\"10\"><rect width=\"10\" height=\"10\" fill=\"blue\"/></svg>".utf8)
                .write(to: assets.appendingPathComponent("blue.svg"))
        }
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
    func testMonitorReloadsExternallyReplacedPackageWithoutSwitchingDocuments() async throws {
        let fixture = try await packageFixture()
        let session = fixture.session
        defer { fixture.tabs.stop(); try? FileManager.default.removeItem(at: fixture.root) }
        let oldWorkspace = try XCTUnwrap(session.packageWorkspace)
        let latest = try documentSource(body: "External: {{field:name}}")
        try LeonardoPackageTransport.export(documentURL: fixture.template, content: latest, to: fixture.package)

        await session.checkExternalChanges()

        XCTAssertEqual(session.content, latest)
        XCTAssertFalse(session.externalConflict)
        XCTAssertFalse(session.isDirty)
        XCTAssertNotEqual(session.packageWorkspace?.directoryURL, oldWorkspace.directoryURL)
        XCTAssertFalse(FileManager.default.fileExists(atPath: oldWorkspace.directoryURL.path))
        XCTAssertFalse(try XCTUnwrap(session.packageWorkspace).hasSourceChanged())
        let refreshedDirectory = session.packageWorkspace?.directoryURL
        await session.checkExternalChanges()
        XCTAssertEqual(session.packageWorkspace?.directoryURL, refreshedDirectory)
    }

    func testMonitorProtectsLocalDraftUntilUserChoosesReload() async throws {
        let fixture = try await packageFixture()
        let session = fixture.session
        defer { fixture.tabs.stop(); try? FileManager.default.removeItem(at: fixture.root) }
        let draft = try documentSource(body: "Local: {{field:name}}")
        session.content = draft
        session.contentChanged()
        let latest = try documentSource(body: "External: {{field:name}}")
        try LeonardoPackageTransport.export(documentURL: fixture.template, content: latest, to: fixture.package)
        let diskBytes = try Data(contentsOf: fixture.package)

        await session.checkExternalChanges()
        XCTAssertTrue(session.externalConflict)
        XCTAssertEqual(session.content, draft)
        await session.save()
        XCTAssertEqual(try Data(contentsOf: fixture.package), diskBytes)
        session.confirmDiscardForReload = { false }
        await session.reloadFromDisk()
        XCTAssertEqual(session.content, draft)
        XCTAssertTrue(session.externalConflict)
        session.confirmDiscardForReload = { true }
        await session.reloadFromDisk()
        XCTAssertEqual(session.content, latest)
        XCTAssertFalse(session.externalConflict)
        XCTAssertFalse(session.isDirty)
    }

    func testMonitorProtectsContentWhenPackageIsDeleted() async throws {
        let fixture = try await packageFixture()
        let session = fixture.session
        defer { fixture.tabs.stop(); try? FileManager.default.removeItem(at: fixture.root) }
        try FileManager.default.removeItem(at: fixture.package)

        await session.checkExternalChanges()

        XCTAssertTrue(session.externalConflict)
        XCTAssertEqual(session.content, fixture.source)
        XCTAssertNotNil(session.errorMessage)
        XCTAssertTrue(FileManager.default.fileExists(atPath: try XCTUnwrap(session.documentURL).path))
    }

    func testMonitorDoesNotFlagOwnPackageSave() async throws {
        let fixture = try await packageFixture()
        let session = fixture.session
        defer { fixture.tabs.stop(); try? FileManager.default.removeItem(at: fixture.root) }
        session.content = try documentSource(body: "Saved locally: {{field:name}}")
        session.contentChanged()
        await session.save()
        let saved = session.content
        let directory = session.packageWorkspace?.directoryURL

        await session.checkExternalChanges()

        XCTAssertEqual(session.content, saved)
        XCTAssertEqual(session.packageWorkspace?.directoryURL, directory)
        XCTAssertFalse(session.externalConflict)
        XCTAssertFalse(session.isDirty)
    }

    func testMonitorDiscardsOldSourceResultAfterPackageMove() async throws {
        let fixture = try await packageFixture()
        let session = fixture.session
        defer { fixture.tabs.stop(); try? FileManager.default.removeItem(at: fixture.root) }
        let draft = try documentSource(body: "Local: {{field:name}}")
        session.content = draft
        session.contentChanged()
        let extraction = session.packageWorkspace?.directoryURL
        let reached = expectation(description: "Source digest suspended")
        let gate = PackageArchiveCommitGate(reached: reached)
        let monitor = Task {
            await session.checkExternalChanges { workspace in
                await Task.detached {
                    gate.pause()
                    return workspace.hasSourceChanged()
                }.value
            }
        }
        await fulfillment(of: [reached], timeout: 5)
        let moved = fixture.root.appendingPathComponent("moved.mdlz")
        do {
            try FileManager.default.moveItem(at: fixture.package, to: moved)
        } catch {
            gate.open()
            await monitor.value
            throw error
        }
        await session.updateMovedDocument(from: fixture.package, to: moved)
        gate.open()
        await monitor.value

        XCTAssertFalse(session.externalConflict)
        XCTAssertEqual(session.content, draft)
        XCTAssertEqual(session.documentSourceURL, moved)
        XCTAssertEqual(session.packageWorkspace?.directoryURL, extraction)
        await session.save()
        XCTAssertFalse(session.isDirty)
        XCTAssertFalse(session.externalConflict)
        let reopened = try LeonardoPackageTransport.open(moved)
        defer { LeonardoPackageTransport.discard(reopened) }
        XCTAssertEqual(try String(contentsOf: reopened.documentURL, encoding: .utf8), draft)
    }

    func testMonitorDiscardsSourceResultWhileFileOperationIsInProgress() async throws {
        let fixture = try await packageFixture()
        let session = fixture.session
        defer { fixture.tabs.stop(); try? FileManager.default.removeItem(at: fixture.root) }
        session.content = try documentSource(body: "Local draft: {{field:name}}")
        session.contentChanged()
        let draft = session.content
        let reached = expectation(description: "Source digest suspended")
        let gate = PackageArchiveCommitGate(reached: reached)
        let monitor = Task {
            await session.checkExternalChanges { workspace in
                await Task.detached {
                    gate.pause()
                    return workspace.hasSourceChanged()
                }.value
            }
        }
        await fulfillment(of: [reached], timeout: 5)
        let moved = fixture.root.appendingPathComponent("moving.mdlz")
        do {
            try FileManager.default.moveItem(at: fixture.package, to: moved)
        } catch {
            gate.open()
            await monitor.value
            throw error
        }
        session.fileOperationCount += 1
        gate.open()
        await monitor.value
        XCTAssertFalse(session.externalConflict)
        XCTAssertEqual(session.content, draft)
        await session.updateMovedDocument(from: fixture.package, to: moved)
        session.fileOperationCount -= 1
        await session.checkExternalChanges()
        XCTAssertFalse(session.externalConflict)
        XCTAssertEqual(session.content, draft)
    }

    func testMonitorWaitsForFileOperationInAnotherTab() async throws {
        let fixture = try await packageFixture()
        let session = fixture.session
        defer { fixture.tabs.stop(); try? FileManager.default.removeItem(at: fixture.root) }
        let reached = expectation(description: "Source digest suspended")
        let gate = PackageArchiveCommitGate(reached: reached)
        let monitor = Task {
            await session.checkExternalChanges { workspace in
                await Task.detached {
                    gate.pause()
                    return workspace.hasSourceChanged()
                }.value
            }
        }
        await fulfillment(of: [reached], timeout: 5)
        guard let otherID = fixture.tabs.addTab(),
              let other = fixture.tabs.tabs.first(where: { $0.id == otherID })?.session else {
            gate.open()
            await monitor.value
            return XCTFail("Expected another tab")
        }
        let moved = fixture.root.appendingPathComponent("other-tab-move.mdlz")
        other.fileOperationCount += 1
        do {
            try FileManager.default.moveItem(at: fixture.package, to: moved)
        } catch {
            gate.open()
            await monitor.value
            other.fileOperationCount -= 1
            throw error
        }
        gate.open()
        await monitor.value
        XCTAssertFalse(session.externalConflict)
        XCTAssertNil(session.errorMessage)
        XCTAssertEqual(session.content, fixture.source)
        await fixture.tabs.pathMoved(fixture.package, to: moved, excluding: other)
        other.fileOperationCount -= 1
        await session.checkExternalChanges()
        XCTAssertFalse(session.externalConflict)
        XCTAssertNil(session.errorMessage)
        XCTAssertEqual(session.documentSourceURL, moved)
    }

    private func packageImage(in workspace: LeonardoPackageWorkspace) throws -> URL {
        let files = FileManager.default.enumerator(at: workspace.directoryURL, includingPropertiesForKeys: nil)?.allObjects as? [URL]
        return try XCTUnwrap(files?.first { $0.pathExtension == "svg" })
    }

    func testConflictCopyPreservesPackageAnswersAndOriginalImageBytes() async throws {
        let fixture = try await packageFixture(withImage: true)
        let session = fixture.session
        defer { fixture.tabs.stop(); try? FileManager.default.removeItem(at: fixture.root) }
        let originalURL = try XCTUnwrap(session.documentURL)
        let oldWorkspace = try XCTUnwrap(session.packageWorkspace)
        let image = try Data(contentsOf: try packageImage(in: oldWorkspace))
        var draft = try LeonardoFormatParser.parse(session.content)
        draft.metadata.values["name"] = .string("Pending answer 308")
        session.content = try LeonardoFormatParser.serialize(draft)
        session.contentChanged()
        session.mode = .fill
        // The source archive now belongs to an external writer; it must survive recovery.
        let external = try documentSource(body: "External version")
        try LeonardoPackageTransport.export(documentURL: fixture.template, content: external, to: fixture.package)
        let sourceBytes = try Data(contentsOf: fixture.package)
        await session.checkExternalChanges()
        XCTAssertTrue(session.externalConflict)
        let destination = fixture.root.appendingPathComponent("recovered.mdlz")

        await session.saveCopyAndOpen(to: destination, sourceURL: originalURL)

        XCTAssertEqual(session.documentStorage, .package)
        XCTAssertEqual(session.documentSourceURL, destination)
        XCTAssertEqual(session.mode, .fill)
        XCTAssertFalse(session.externalConflict)
        XCTAssertFalse(session.isDirty)
        XCTAssertEqual(try Data(contentsOf: fixture.package), sourceBytes)
        let reopened = try LeonardoPackageTransport.open(destination)
        defer { LeonardoPackageTransport.discard(reopened) }
        let recovered = try LeonardoFormatParser.parse(String(contentsOf: reopened.documentURL, encoding: .utf8))
        XCTAssertEqual(recovered.metadata.values["name"], .string("Pending answer 308"))
        XCTAssertEqual(try Data(contentsOf: try packageImage(in: reopened)), image)
        await session.waitForPackageWorkspaceDisposal()
        XCTAssertFalse(FileManager.default.fileExists(atPath: oldWorkspace.directoryURL.path))
    }

    func testPackageConflictCopyRejectsTextOrOriginalArchiveDestination() async throws {
        let fixture = try await packageFixture(withImage: true)
        let session = fixture.session
        defer { fixture.tabs.stop(); try? FileManager.default.removeItem(at: fixture.root) }
        let originalURL = try XCTUnwrap(session.documentURL)
        let workspace = try XCTUnwrap(session.packageWorkspace)
        session.content += "\nPending draft"
        session.contentChanged()
        session.externalConflict = true
        let draft = session.content
        let originalBytes = try Data(contentsOf: fixture.package)
        let destinations = [fixture.root.appendingPathComponent("unsafe.mdlf"), fixture.package,
                            workspace.directoryURL.appendingPathComponent("temporary-copy.mdlz")]
        for destination in destinations {
            await session.saveCopyAndOpen(to: destination, sourceURL: originalURL)
            XCTAssertEqual(session.documentURL, originalURL)
            XCTAssertEqual(session.content, draft)
            XCTAssertTrue(session.externalConflict)
            XCTAssertTrue(session.isDirty)
            XCTAssertNotNil(session.errorMessage)
            XCTAssertEqual(session.packageWorkspace?.directoryURL, workspace.directoryURL)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.root.appendingPathComponent("unsafe.mdlf").path))
        XCTAssertEqual(try Data(contentsOf: fixture.package), originalBytes)
    }

    func testFailedPackageConflictCopyRetainsOriginalWorkspaceAndDraft() async throws {
        let fixture = try await packageFixture(withImage: true)
        let session = fixture.session
        defer { fixture.tabs.stop(); try? FileManager.default.removeItem(at: fixture.root) }
        let originalURL = try XCTUnwrap(session.documentURL)
        let workspace = try XCTUnwrap(session.packageWorkspace)
        session.content += "\nPending draft"
        session.contentChanged()
        session.externalConflict = true
        let draft = session.content
        await session.saveCopyAndOpen(to: fixture.root.appendingPathComponent("missing/copy.mdlz"), sourceURL: originalURL)
        XCTAssertEqual(session.documentURL, originalURL)
        XCTAssertEqual(session.content, draft)
        XCTAssertTrue(session.externalConflict)
        XCTAssertTrue(session.isDirty)
        XCTAssertEqual(session.packageWorkspace?.directoryURL, workspace.directoryURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: workspace.documentURL.path))
        XCTAssertNotNil(session.errorMessage)
    }

    func testPackageConflictCopyAuthorizesSourceAndRejectsDeniedDestination() async throws {
        let fixture = try await packageFixture(withImage: true)
        let session = fixture.session
        defer { fixture.tabs.stop(); try? FileManager.default.removeItem(at: fixture.root) }
        let originalURL = try XCTUnwrap(session.documentURL)
        let workspace = try XCTUnwrap(session.packageWorkspace)
        let destination = fixture.root.appendingPathComponent("denied.mdlz")
        session.content += "\nPending draft"
        session.contentChanged()
        session.externalConflict = true
        let draft = session.content
        var authorized: [URL] = []
        session.authorizePath = { url, _ in
            authorized.append(url.standardizedFileURL)
            XCTAssertFalse(session.editDocument(expected: draft, replacement: "Late input"))
            if url.standardizedFileURL == destination.standardizedFileURL { throw CocoaError(.fileWriteNoPermission) }
        }
        await session.saveCopyAndOpen(to: destination, sourceURL: originalURL)
        XCTAssertEqual(authorized, [originalURL.standardizedFileURL, fixture.package.standardizedFileURL, destination.standardizedFileURL])
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
        XCTAssertEqual(session.documentURL, originalURL)
        XCTAssertEqual(session.content, draft)
        XCTAssertEqual(session.packageWorkspace?.directoryURL, workspace.directoryURL)
        XCTAssertTrue(session.externalConflict)
        XCTAssertTrue(session.isDirty)
    }

    func testPackageConflictCopyDoesNotWriteAfterAuthorizationInvalidatesSession() async throws {
        let fixture = try await packageFixture(withImage: true)
        let session = fixture.session
        defer { fixture.tabs.stop(); try? FileManager.default.removeItem(at: fixture.root) }
        let originalURL = try XCTUnwrap(session.documentURL)
        let destination = fixture.root.appendingPathComponent("stale.mdlz")
        session.authorizePath = { _, _ in session.isClosing = true }
        await session.saveCopyAndOpen(to: destination, sourceURL: originalURL)
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
        XCTAssertEqual(session.documentURL, originalURL)
        XCTAssertNotNil(session.packageWorkspace)
        session.isClosing = false
    }

    func testPackageConflictCopyMissingResourceRetainsDraftWithoutPartialArchive() async throws {
        let fixture = try await packageFixture(withImage: true)
        let session = fixture.session
        defer { fixture.tabs.stop(); try? FileManager.default.removeItem(at: fixture.root) }
        let originalURL = try XCTUnwrap(session.documentURL)
        let workspace = try XCTUnwrap(session.packageWorkspace)
        let destination = fixture.root.appendingPathComponent("missing-resource.mdlz")
        session.content += "\nPending draft"
        session.contentChanged()
        session.externalConflict = true
        let draft = session.content
        try FileManager.default.removeItem(at: packageImage(in: workspace))
        await session.saveCopyAndOpen(to: destination, sourceURL: originalURL)
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
        XCTAssertEqual(session.documentURL, originalURL)
        XCTAssertEqual(session.content, draft)
        XCTAssertEqual(session.packageWorkspace?.directoryURL, workspace.directoryURL)
        XCTAssertTrue(session.externalConflict)
        XCTAssertTrue(session.isDirty)
        XCTAssertNotNil(session.errorMessage)
    }

}
