import XCTest
import LeonardoCore
@testable import LeonardoApp

@MainActor
final class SessionPackageLifecycleTests: XCTestCase {
    @MainActor private struct Fixture {
        let root: URL
        let project: ProjectDescriptor
        let package: URL
        let tabs: DocumentTabs

        var session: AppSession { tabs.activeSession }
    }

    private func fixture() async throws -> Fixture {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("LeonardoPackageLifecycle-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let tabs = DocumentTabs(preferencesURL: root.appendingPathComponent("preferences.json"))
        let session = tabs.activeSession
        session.authorizePath = { _, _ in }
        let project = try await session.files.createProject(named: "Project", in: root)
        let template = project.rootURL.appendingPathComponent("request.mdlf")
        let package = project.rootURL.appendingPathComponent("request.mdlz")
        let document = LeonardoDocument(
            body: "Name: {{field:name}}",
            metadata: LeonardoMetadata(
                document: LeonardoDocumentDescriptor(title: "Request", kind: .form),
                fields: ["name": LeonardoFieldDefinition(required: true)]
            )
        )
        let source = try LeonardoFormatParser.serialize(document)
        try source.write(to: template, atomically: true, encoding: .utf8)
        try LeonardoPackageTransport.export(documentURL: template, content: source, to: package)
        await session.openProject(project.rootURL)
        let opened = await session.openLeonardoPackage(package, extractingTo: nil)
        XCTAssertTrue(opened)
        XCTAssertEqual(session.documentStorage, .package)
        session.mode = .fill
        return Fixture(root: root, project: project, package: package, tabs: tabs)
    }

    private func saveValue(_ value: String, in session: AppSession) async throws {
        session.mode = .fill
        XCTAssertTrue(session.updateLeonardoField("name", text: value))
        await session.save()
        XCTAssertFalse(session.isDirty)
        XCTAssertNil(session.errorMessage)
    }

    private func readValue(from package: URL, using session: AppSession) async throws -> String? {
        let workspace = try LeonardoPackageTransport.open(package)
        defer { LeonardoPackageTransport.discard(workspace) }
        let loaded = try await session.documents.read(workspace.documentURL)
        return try LeonardoFormatParser.parse(loaded.content).metadata.values["name"]?.stringValue
    }

    private func waitForFileSystemChange(_ condition: () -> Bool, timeout: TimeInterval = 2) async throws -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if condition() { return true }
            try await Task.sleep(for: .milliseconds(10))
        } while Date() < deadline
        return condition()
    }

    func testSelectingContainingProjectsPreservesOpenPackageIdentityAndContent() async throws {
        let fixture = try await fixture()
        let session = fixture.session
        defer { fixture.tabs.stop(); try? FileManager.default.removeItem(at: fixture.root) }
        try await saveValue("Ada", in: session)
        let workspace = try XCTUnwrap(session.packageWorkspace)
        let documentURL = try XCTUnwrap(session.documentURL)
        let content = session.content

        for project in [fixture.project.rootURL, fixture.root] {
            let opened = await session.openProject(project)
            XCTAssertTrue(opened)
            XCTAssertEqual(session.documentStorage, .package)
            XCTAssertEqual(session.documentSourceURL, fixture.package)
            XCTAssertEqual(session.documentURL, documentURL)
            XCTAssertEqual(session.packageWorkspace?.directoryURL, workspace.directoryURL)
            XCTAssertEqual(session.packageWorkspace?.packageURL, fixture.package)
            XCTAssertEqual(session.content, content)
            XCTAssertTrue(FileManager.default.fileExists(atPath: documentURL.path))
        }
        let value = try await readValue(from: fixture.package, using: session)
        XCTAssertEqual(value, "Ada")
    }

    func testOwnerPackageFileRenameRemapsArchiveAndSurvivesSaveAndReopen() async throws {
        let fixture = try await fixture()
        let session = fixture.session
        defer { fixture.tabs.stop(); try? FileManager.default.removeItem(at: fixture.root) }

        let renamed = fixture.project.rootURL.appendingPathComponent("renamed.mdlz")
        let node = try await session.files.rename(
            "request.mdlz",
            in: fixture.project,
            to: "renamed.mdlz"
        )
        await session.updateMovedDocument(from: fixture.package, to: node.url)

        XCTAssertEqual(session.documentSourceURL?.standardizedFileURL, renamed.standardizedFileURL)
        XCTAssertEqual(session.packageWorkspace?.packageURL?.standardizedFileURL, renamed.standardizedFileURL)
        try await saveValue("Ada", in: session)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.package.path))
        let value = try await readValue(from: renamed, using: session)
        XCTAssertEqual(value, "Ada")
    }

    func testOwnerPackageFolderMoveRemapsArchiveAndSurvivesSaveAndReopen() async throws {
        let fixture = try await fixture()
        let session = fixture.session
        defer { fixture.tabs.stop(); try? FileManager.default.removeItem(at: fixture.root) }

        let folder = try await session.files.createFolder(named: "Moved", in: fixture.project)
        let operation = try XCTUnwrap(session.move(fixture.package, into: folder.url))
        await operation.value
        let moved = folder.url.appendingPathComponent("request.mdlz")
        XCTAssertEqual(session.documentSourceURL?.standardizedFileURL, moved.standardizedFileURL)
        XCTAssertEqual(session.packageWorkspace?.packageURL?.standardizedFileURL, moved.standardizedFileURL)
        try await saveValue("Grace", in: session)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.package.path))
        let value = try await readValue(from: moved, using: session)
        XCTAssertEqual(value, "Grace")
    }

    func testMoveBatchTreatsSameTargetItemAsNoOpAndRejectsRealCollisionAtomically() async throws {
        let fixture = try await fixture()
        let session = fixture.session
        defer { fixture.tabs.stop(); try? FileManager.default.removeItem(at: fixture.root) }
        session.monitorTask?.cancel()

        let target = try await session.files.createFolder(named: "Target", in: fixture.project)
        let sourceFolder = try await session.files.createFolder(named: "Source", in: fixture.project)
        let alreadyInTarget = try await session.files.createMarkdown(
            named: "already.md", in: fixture.project, at: target.relativePath, contents: "target"
        )
        let newItem = try await session.files.createMarkdown(
            named: "new.md", in: fixture.project, at: sourceFolder.relativePath, contents: "new"
        )

        let noOpAndMove = try XCTUnwrap(session.move([alreadyInTarget.url, newItem.url], into: target.url))
        await noOpAndMove.value
        XCTAssertTrue(FileManager.default.fileExists(atPath: alreadyInTarget.url.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: newItem.url.path))
        XCTAssertEqual(try String(contentsOf: target.url.appendingPathComponent("new.md"), encoding: .utf8), "new")

        let collidingSource = try await session.files.createMarkdown(
            named: "already.md", in: fixture.project, at: sourceFolder.relativePath, contents: "source collision"
        )
        let untouchedSource = try await session.files.createMarkdown(
            named: "untouched.md", in: fixture.project, at: sourceFolder.relativePath, contents: "untouched"
        )
        let collidingBatch = try XCTUnwrap(
            session.move([alreadyInTarget.url, collidingSource.url, untouchedSource.url], into: target.url)
        )
        await collidingBatch.value

        XCTAssertTrue(FileManager.default.fileExists(atPath: collidingSource.url.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: untouchedSource.url.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: target.url.appendingPathComponent("untouched.md").path))
        XCTAssertEqual(try String(contentsOf: alreadyInTarget.url, encoding: .utf8), "target")
        XCTAssertNotNil(session.errorMessage)
    }

    func testMoveBatchTreatsSameTargetItemAsNoOpThroughSymlinkAlias() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("LeonardoAliasTransfer-\(UUID().uuidString)", isDirectory: true)
        let physicalParent = root.appendingPathComponent("physical", isDirectory: true)
        let aliasParent = root.appendingPathComponent("alias", isDirectory: true)
        let projectRoot = aliasParent.appendingPathComponent("Project", isDirectory: true)
        try FileManager.default.createDirectory(at: physicalParent, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: aliasParent, withDestinationURL: physicalParent)
        try FileManager.default.createDirectory(at: projectRoot, withIntermediateDirectories: true)

        let tabs = DocumentTabs(preferencesURL: root.appendingPathComponent("preferences.json"))
        let session = tabs.activeSession
        session.authorizePath = { _, _ in }
        defer { tabs.stop(); try? FileManager.default.removeItem(at: root) }

        let projectOpened = await session.openProject(projectRoot)
        XCTAssertTrue(projectOpened)
        session.monitorTask?.cancel()
        let project = try await session.files.project(at: projectRoot)
        let target = try await session.files.createFolder(named: "Target", in: project)
        let sourceFolder = try await session.files.createFolder(named: "Source", in: project)
        let alreadyInTarget = try await session.files.createMarkdown(
            named: "already.md", in: project, at: target.relativePath, contents: "target"
        )
        let newItem = try await session.files.createMarkdown(
            named: "new.md", in: project, at: sourceFolder.relativePath, contents: "new"
        )

        XCTAssertNil(session.move([alreadyInTarget.url], into: target.url))
        let noOpAndMove = try XCTUnwrap(session.move([alreadyInTarget.url, newItem.url], into: target.url))
        await noOpAndMove.value

        XCTAssertTrue(FileManager.default.fileExists(atPath: alreadyInTarget.url.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: newItem.url.path))
        XCTAssertEqual(try String(contentsOf: target.url.appendingPathComponent("new.md"), encoding: .utf8), "new")
        XCTAssertNil(session.errorMessage)
    }

    func testProjectTreeDropMovesAndCopiesMixedFileAndFolderSelection() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("LeonardoProjectTreeDrop-\(UUID().uuidString)", isDirectory: true)
        let projectRoot = root.appendingPathComponent("Project", isDirectory: true)
        try FileManager.default.createDirectory(at: projectRoot, withIntermediateDirectories: true)
        let tabs = DocumentTabs(preferencesURL: root.appendingPathComponent("preferences.json"))
        let session = tabs.activeSession
        session.authorizePath = { _, _ in }
        defer { tabs.stop(); try? FileManager.default.removeItem(at: root) }

        let projectOpened = await session.openProject(projectRoot)
        XCTAssertTrue(projectOpened)
        session.monitorTask?.cancel()
        let project = try await session.files.project(at: projectRoot)
        let target = try await session.files.createFolder(named: "Target", in: project)
        let moveFolder = try await session.files.createFolder(named: "MoveFolder", in: project)
        let moveFile = try await session.files.createMarkdown(
            named: "MoveSource.md", in: project, contents: "move"
        )
        _ = try await session.files.createMarkdown(
            named: "Nested.md", in: project, at: moveFolder.relativePath, contents: "nested"
        )
        let source = ProjectTreeDragSourceView(frame: .zero)
        source.session = session
        let drag = ProjectTreeDragSourceRegistry()
        let moveSelection = [moveFile.url, moveFolder.url]
        drag.begin(source, root: try XCTUnwrap(session.projectURL), urls: moveSelection)
        XCTAssertNil(drag.selection(for: session, destination: moveFolder.url))
        source.isActiveTab = false
        XCTAssertNil(drag.selection(for: session, destination: target.url))
        source.isActiveTab = true
        let droppedMove = try XCTUnwrap(drag.selection(for: session, destination: target.url))
        XCTAssertEqual(droppedMove, moveSelection)
        XCTAssertTrue(session.acceptProjectTreeDrop(droppedMove, into: target.url, copy: false))
        drag.end(source)
        XCTAssertNil(drag.selection(for: session, destination: target.url))
        let moved = try await waitForFileSystemChange {
            FileManager.default.fileExists(atPath: target.url.appendingPathComponent("MoveSource.md").path) &&
            FileManager.default.fileExists(atPath: target.url.appendingPathComponent("MoveFolder/Nested.md").path)
        }
        XCTAssertTrue(moved, "The internal project-tree drop should move the complete mixed selection")
        XCTAssertFalse(FileManager.default.fileExists(atPath: moveFile.url.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: moveFolder.url.path))

        let copyFolder = try await session.files.createFolder(named: "CopyFolder", in: project)
        let copyFile = try await session.files.createMarkdown(
            named: "CopySource.md", in: project, contents: "copy"
        )
        _ = try await session.files.createMarkdown(
            named: "NestedCopy.md", in: project, at: copyFolder.relativePath, contents: "nested copy"
        )
        let copySelection = [copyFile.url, copyFolder.url]
        drag.begin(source, root: try XCTUnwrap(session.projectURL), urls: copySelection)
        let droppedCopy = try XCTUnwrap(drag.selection(for: session, destination: target.url))
        XCTAssertTrue(session.acceptProjectTreeDrop(droppedCopy, into: target.url, copy: true))
        drag.end(source)
        let copied = try await waitForFileSystemChange {
            FileManager.default.fileExists(atPath: target.url.appendingPathComponent("CopySource.md").path) &&
            FileManager.default.fileExists(atPath: target.url.appendingPathComponent("CopyFolder/NestedCopy.md").path)
        }
        XCTAssertTrue(copied, "The Option-copy path should retain and duplicate each selected item")
        XCTAssertTrue(FileManager.default.fileExists(atPath: copyFile.url.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: copyFolder.url.path))

        let movedFile = target.url.appendingPathComponent("MoveSource.md")
        XCTAssertTrue(session.acceptProjectTreeDrop([movedFile], into: projectRoot, copy: true))
        let copiedBack = try await waitForFileSystemChange {
            FileManager.default.fileExists(atPath: moveFile.url.path)
        }
        XCTAssertTrue(copiedBack)
        XCTAssertTrue(FileManager.default.fileExists(atPath: movedFile.path))

        let movedFolder = target.url.appendingPathComponent("MoveFolder", isDirectory: true)
        XCTAssertTrue(session.acceptProjectTreeDrop([movedFolder], into: projectRoot, copy: false))
        let movedBack = try await waitForFileSystemChange {
            FileManager.default.fileExists(atPath: moveFolder.url.appendingPathComponent("Nested.md").path)
        }
        XCTAssertTrue(movedBack)
        XCTAssertFalse(FileManager.default.fileExists(atPath: movedFolder.path))

        let existingCopy = try await session.files.createMarkdown(
            named: "CopySource copy.md", in: project, contents: "existing"
        )
        XCTAssertTrue(session.acceptProjectTreeDrop([copyFile.url], into: projectRoot, copy: true))
        let duplicate = projectRoot.appendingPathComponent("CopySource copy 2.md")
        let duplicated = try await waitForFileSystemChange {
            FileManager.default.fileExists(atPath: duplicate.path)
        }
        XCTAssertTrue(duplicated)
        XCTAssertEqual(try String(contentsOf: duplicate, encoding: .utf8),
                       try String(contentsOf: copyFile.url, encoding: .utf8))
        XCTAssertEqual(try String(contentsOf: existingCopy.url, encoding: .utf8), "existing")
    }

    func testDeletingOwnerPackageClearsOnlyPackageTabAndPreservesExtractedTab() async throws {
        let fixture = try await fixture()
        let owner = fixture.session
        defer { fixture.tabs.stop(); try? FileManager.default.removeItem(at: fixture.root) }

        let ownerWorkspace = try XCTUnwrap(owner.packageWorkspace?.directoryURL)
        let extractedID = try XCTUnwrap(fixture.tabs.addTab())
        let extracted = try XCTUnwrap(fixture.tabs.tabs.first { $0.id == extractedID }?.session)
        extracted.authorizePath = { _, _ in }
        let extraction = fixture.root.appendingPathComponent("extracted", isDirectory: true)
        let extractedOpened = await extracted.openLeonardoPackage(fixture.package, extractingTo: extraction)
        XCTAssertTrue(extractedOpened)
        let extractedDocument = try XCTUnwrap(extracted.documentURL)
        XCTAssertEqual(extracted.documentStorage, .extracted)

        try await owner.files.delete("request.mdlz", in: fixture.project)
        fixture.tabs.pathDeleted(fixture.package, excluding: owner)
        await owner.waitForPackageWorkspaceDisposal()

        XCTAssertNil(owner.packageWorkspace)
        XCTAssertNil(owner.documentURL)
        XCTAssertNil(owner.documentSourceURL)
        XCTAssertEqual(owner.documentStorage, .localFile)
        XCTAssertFalse(FileManager.default.fileExists(atPath: ownerWorkspace.path))
        XCTAssertEqual(extracted.documentStorage, .extracted)
        XCTAssertEqual(extracted.documentURL?.standardizedFileURL, extractedDocument.standardizedFileURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: extraction.path))
    }
}
