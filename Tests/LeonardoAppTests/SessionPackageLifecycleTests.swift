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
        session.workspaceURL = root
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
        session.move(fixture.package, into: folder.url)
        for _ in 0..<100 {
            await Task.yield()
            if session.documentSourceURL?.lastPathComponent == "request.mdlz",
               session.documentSourceURL?.deletingLastPathComponent().standardizedFileURL == folder.url.standardizedFileURL {
                break
            }
        }
        let moved = folder.url.appendingPathComponent("request.mdlz")
        XCTAssertEqual(session.documentSourceURL?.standardizedFileURL, moved.standardizedFileURL)
        XCTAssertEqual(session.packageWorkspace?.packageURL?.standardizedFileURL, moved.standardizedFileURL)
        try await saveValue("Grace", in: session)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.package.path))
        let value = try await readValue(from: moved, using: session)
        XCTAssertEqual(value, "Grace")
    }

    func testOwnerPackageProjectRenameRemapsArchiveAndSurvivesSaveAndReopen() async throws {
        let fixture = try await fixture()
        let session = fixture.session
        defer { fixture.tabs.stop(); try? FileManager.default.removeItem(at: fixture.root) }

        await session.renameProject(fixture.project, to: "Renamed")
        let renamedProject = fixture.root.appendingPathComponent("Renamed", isDirectory: true)
        let renamed = renamedProject.appendingPathComponent("request.mdlz")
        XCTAssertEqual(session.projectURL?.standardizedFileURL, renamedProject.standardizedFileURL)
        XCTAssertEqual(session.documentSourceURL?.standardizedFileURL, renamed.standardizedFileURL)
        XCTAssertEqual(session.packageWorkspace?.packageURL?.standardizedFileURL, renamed.standardizedFileURL)
        try await saveValue("Lin", in: session)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.package.path))
        let value = try await readValue(from: renamed, using: session)
        XCTAssertEqual(value, "Lin")
    }

    func testDeletingOwnerProjectDiscardsPackageWorkspaceAndClearsIdentity() async throws {
        let fixture = try await fixture()
        let session = fixture.session
        defer { fixture.tabs.stop(); try? FileManager.default.removeItem(at: fixture.root) }

        await session.deleteConfirmedProject(fixture.project)
        XCTAssertNil(session.packageWorkspace)
        XCTAssertNil(session.documentURL)
        XCTAssertNil(session.documentSourceURL)
        XCTAssertEqual(session.documentStorage, .localFile)
        XCTAssertEqual(session.documentKind, .markdown)
        XCTAssertTrue(session.content.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.project.rootURL.path))
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
