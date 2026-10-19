import XCTest
import LeonardoCore
@testable import LeonardoApp

@MainActor
final class AppSessionTests: XCTestCase {
    private func fixture() throws -> (URL, AppSession) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let session = AppSession(preferencesURL: root.appendingPathComponent("preferences.json"))
        session.unsavedChangesDecision = { _ in .save }
        return (root, session)
    }

    func testTagActivationPopulatesProjectSearchAndRevealsSidebar() async throws {
        let (root, session) = try fixture()
        defer { session.stop(); try? FileManager.default.removeItem(at: root) }
        try "---\ntags: ['Design Systems']\n---\n# Note".write(to: root.appendingPathComponent("note.md"), atomically: true, encoding: .utf8)
        await session.openProject(root)
        session.focus = true
        session.search(tag: "Design Systems")
        XCTAssertEqual(session.searchQuery, "tag:\"Design Systems\"")
        XCTAssertTrue(session.presentation.showsSidebar)
        await session.searchTask?.value
        XCTAssertEqual(session.searchResults.map { $0.url.lastPathComponent }, ["note.md"])
        await session.detachProject()
        session.search(tag: "Swift")
        XCTAssertTrue(session.searchQuery.isEmpty)
    }

    func testGlobalExtensionChangesWhileProjectOpenPreserveProjectOverrides() async throws {
        let (root, session) = try fixture()
        defer { session.stop(); try? FileManager.default.removeItem(at: root) }
        await session.openProject(root)
        session.setMath(true, project: true)
        await session.settingsTask?.value
        let override = session.projectConfiguration.markdown
        session.setMermaid(true, project: false)
        await session.settingsTask?.value
        XCTAssertEqual(session.projectConfiguration.markdown, override)
        XCTAssertFalse(session.features.mermaidEnabled)
        let saved = try await session.configurations.loadGlobalPreferences(at: session.globalPreferencesURL)
        XCTAssertTrue(saved.markdown.mermaidEnabled)
        XCTAssertFalse(saved.markdown.mathEnabled)
        session.inheritFeatures(true)
        await session.settingsTask?.value
        XCTAssertNil(session.projectConfiguration.markdown)
        XCTAssertTrue(session.features.mermaidEnabled)
        XCTAssertFalse(session.features.mathEnabled)
        let project = try await session.configurations.loadProjectConfiguration(for: root)
        XCTAssertNil(project.markdown)
    }

    func testProjectExtensionOverridePreservesInheritedFlagsAndGlobalSettings() async throws {
        let (root, session) = try fixture()
        defer { session.stop(); try? FileManager.default.removeItem(at: root) }
        session.setMermaid(true, project: false)
        await session.settingsTask?.value
        await session.openProject(root)
        session.setMath(true, project: true)
        await session.settingsTask?.value
        XCTAssertTrue(session.features.mermaidEnabled)
        XCTAssertTrue(session.features.mathEnabled)
        XCTAssertFalse(session.globalPreferences.markdown.mathEnabled)
        let project = try await session.configurations.loadProjectConfiguration(for: root)
        XCTAssertTrue(project.markdown?.mermaidEnabled == true)
        XCTAssertTrue(project.markdown?.mathEnabled == true)
    }

    func testOpeningStandaloneAfterProjectDetachesFolderAndUsesGlobalFeatures() async throws {
        let (root, session) = try fixture()
        defer { session.stop(); try? FileManager.default.removeItem(at: root) }
        let document = root.appendingPathComponent("note.md")
        try "# Hello".write(to: document, atomically: true, encoding: .utf8)
        await session.openProject(root)
        XCTAssertTrue(session.presentation.showsSidebar)
        session.projectConfiguration.markdown = MarkdownFeatures(mermaidEnabled: true)
        await session.open(document)
        XCTAssertNil(session.projectURL)
        XCTAssertFalse(session.presentation.showsSidebar)
        XCTAssertFalse(session.features.mermaidEnabled)
        XCTAssertEqual(session.content, "# Hello")
    }

    func testNavigationSavesDraftBeforeSwitchingDocument() async throws {
        let (root, session) = try fixture()
        defer { session.stop(); try? FileManager.default.removeItem(at: root) }
        let first = root.appendingPathComponent("first.md")
        let second = root.appendingPathComponent("second.md")
        try "first".write(to: first, atomically: true, encoding: .utf8)
        try "second".write(to: second, atomically: true, encoding: .utf8)
        await session.open(first)
        session.content = "edited"
        session.contentChanged()
        await session.open(second)
        XCTAssertEqual(try String(contentsOf: first, encoding: .utf8), "edited")
        XCTAssertEqual(session.content, "second")
        XCTAssertFalse(session.isDirty)
    }

    func testExternalConflictRetainsDraftAndBlocksNavigation() async throws {
        let (root, session) = try fixture()
        defer { session.stop(); try? FileManager.default.removeItem(at: root) }
        let document = root.appendingPathComponent("note.md")
        let second = root.appendingPathComponent("second.md")
        try "original".write(to: document, atomically: true, encoding: .utf8)
        try "second".write(to: second, atomically: true, encoding: .utf8)
        await session.open(document)
        session.content = "my draft"
        try "external".write(to: document, atomically: true, encoding: .utf8)
        await session.save()
        XCTAssertTrue(session.externalConflict)
        await session.open(second)
        XCTAssertEqual(session.documentURL, document)
        XCTAssertEqual(session.content, "my draft")
        XCTAssertEqual(try String(contentsOf: document, encoding: .utf8), "external")
    }

    func testTwoWindowsPreserveUnrelatedGlobalSettings() async throws {
        let (root, first) = try fixture()
        let second = AppSession(preferencesURL: first.globalPreferencesURL)
        defer { first.stop(); second.stop(); try? FileManager.default.removeItem(at: root) }
        await first.initialize()
        await second.initialize()
        first.setPalette(PaletteID.graphiteGlass.rawValue, project: false)
        second.globalPreferences.showHiddenFiles = true
        second.persistSettings()
        await first.settingsTask?.value
        await second.settingsTask?.value
        let saved = try await first.configurations.loadGlobalPreferences(at: first.globalPreferencesURL)
        XCTAssertEqual(saved.palette, .graphiteGlass)
        XCTAssertTrue(saved.showHiddenFiles)
        await first.checkExternalChanges()
        XCTAssertTrue(first.showHidden)
    }

    func testProjectSwitchCancelsOldSearchAndClearsResults() async throws {
        let (root, session) = try fixture()
        defer { session.stop(); try? FileManager.default.removeItem(at: root) }
        let first = root.appendingPathComponent("A")
        let second = root.appendingPathComponent("B")
        try FileManager.default.createDirectory(at: first, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: second, withIntermediateDirectories: true)
        await session.openProject(first)
        session.searchQuery = "old"
        session.searchResults = [SearchResult(url: first.appendingPathComponent("old.md"), line: 5, snippet: "old")]
        session.scheduleSearch()
        await session.openProject(second)
        XCTAssertEqual(session.projectURL, second)
        XCTAssertTrue(session.searchQuery.isEmpty)
        XCTAssertTrue(session.searchResults.isEmpty)
        XCTAssertNil(session.searchTask)
        XCTAssertFalse(session.searching)
    }

    func testOpeningMissingProjectReturnsFailureForDurableReviewCallers() async throws {
        let (root, session) = try fixture()
        defer { session.stop(); try? FileManager.default.removeItem(at: root) }

        let opened = await session.openProject(root.appendingPathComponent("missing-project"))

        XCTAssertFalse(opened)
        XCTAssertNil(session.projectURL)
    }

    func testTwoWindowsCreatingFeatureOverridesPreserveIndependentToggles() async throws {
        let (root, first) = try fixture()
        let second = AppSession(preferencesURL: first.globalPreferencesURL)
        defer { first.stop(); second.stop(); try? FileManager.default.removeItem(at: root) }
        await first.openProject(root)
        await second.openProject(root)
        await first.settingsTask?.value
        await second.settingsTask?.value
        first.setMermaid(true)
        second.setMath(true)
        await first.settingsTask?.value
        await second.settingsTask?.value
        let saved = try await first.configurations.loadProjectConfiguration(for: root)
        XCTAssertEqual(saved.markdown?.mermaidEnabled, true)
        XCTAssertEqual(saved.markdown?.mathEnabled, true)
    }

    func testGitOperationPreventsDocumentContextSwitch() async throws {
        let (root, session) = try fixture()
        defer { session.stop(); try? FileManager.default.removeItem(at: root) }
        let first = root.appendingPathComponent("A.md")
        let second = root.appendingPathComponent("B.md")
        try "A".write(to: first, atomically: true, encoding: .utf8)
        try "B".write(to: second, atomically: true, encoding: .utf8)
        await session.open(first)
        session.gitBusy = true
        await session.open(second)
        XCTAssertEqual(session.documentURL, first)
        XCTAssertEqual(session.content, "A")
        XCTAssertNotNil(session.errorMessage)
        session.gitBusy = false
    }

    func testOutlineExcludesFencedSourceAndNonHeadings() throws {
        let (root, session) = try fixture()
        defer { session.stop(); try? FileManager.default.removeItem(at: root) }
        session.content = "# Title\n```md\n# Example\n```\n#hashtag\n## Section"
        XCTAssertEqual(session.headings.map(\.title), ["Title", "Section"])
        XCTAssertEqual(session.headings.map(\.line), [1, 6])
    }

    func testCancelledPackageOpenPreservesDocumentWithoutInventingAnError() async throws {
        let (root, session) = try fixture()
        defer { session.stop(); try? FileManager.default.removeItem(at: root) }
        let document = root.appendingPathComponent("current.md")
        try "Current document".write(to: document, atomically: true, encoding: .utf8)
        await session.open(document)
        session.openPackageDocument = { _, _ in false }
        await session.open(root.appendingPathComponent("cancelled.mdlz"))
        XCTAssertNil(session.errorMessage)
        XCTAssertEqual(session.documentURL, document)
        XCTAssertEqual(session.content, "Current document")
        session.openPackageDocument = { [weak session] _, _ in
            session?.errorMessage = "Specific transport error"
            return false
        }
        await session.open(root.appendingPathComponent("failed.mdlz"))
        XCTAssertEqual(session.errorMessage, "Specific transport error")
        XCTAssertEqual(session.documentURL, document)
    }

    func testMarkdownWarningOnlyRecognizesAnExplicitLeonardoHeader() async throws {
        let (root, session) = try fixture()
        defer { session.stop(); try? FileManager.default.removeItem(at: root) }
        let tokenExample = root.appendingPathComponent("token.md")
        try "# Example\n\n{{field:name}}".write(to: tokenExample, atomically: true, encoding: .utf8)
        await session.open(tokenExample)
        XCTAssertFalse(session.leonardoFormatWarning)

        let explicit = root.appendingPathComponent("explicit.md")
        try "---\n{\"format\":\"mdlf\"}\n---\n# Example".write(to: explicit, atomically: true, encoding: .utf8)
        await session.open(explicit)
        XCTAssertTrue(session.leonardoFormatWarning)
    }

    func testProtectedResponseCanUpdateDeclaredFieldThroughFillMode() async throws {
        let (root, session) = try fixture()
        defer { session.stop(); try? FileManager.default.removeItem(at: root) }
        let response = root.appendingPathComponent("response.mdlr")
        let document = LeonardoDocument(
            body: "Name: {{field:name}}",
            metadata: LeonardoMetadata(
                document: LeonardoDocumentDescriptor(kind: .form),
                fields: ["name": LeonardoFieldDefinition(required: true)]
            )
        )
        try LeonardoFormatParser.serialize(document).write(to: response, atomically: true, encoding: .utf8)

        await session.open(response)
        XCTAssertEqual(session.mode, .fill)
        XCTAssertTrue(session.isProtected)
        XCTAssertTrue(session.updateLeonardoField("name", text: "Ada"))
        XCTAssertEqual(session.leonardoFieldText("name"), "Ada")
        XCTAssertTrue(session.isDirty)
    }

    func testMarkdownMigrationFailurePreservesSourceAndDraft() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let tabs = DocumentTabs(preferencesURL: root.appendingPathComponent("preferences.json"))
        let preferenceKey = "migrateMarkdownOnSave"
        let previousPreference = UserDefaults.standard.object(forKey: preferenceKey)
        defer {
            tabs.stop()
            try? FileManager.default.removeItem(at: root)
            if let previousPreference {
                UserDefaults.standard.set(previousPreference, forKey: preferenceKey)
            } else {
                UserDefaults.standard.removeObject(forKey: preferenceKey)
            }
        }
        let source = root.appendingPathComponent("note.md")
        let destination = root.appendingPathComponent("note.mdlf")
        try "original".write(to: source, atomically: true, encoding: .utf8)
        try "existing destination".write(to: destination, atomically: true, encoding: .utf8)

        let session = tabs.activeSession
        await session.open(source)
        session.migrateMarkdownOnSave = true
        session.content = "draft"
        session.contentChanged()
        await session.save()

        XCTAssertEqual(session.documentURL, source)
        XCTAssertEqual(session.content, "draft")
        XCTAssertTrue(session.isDirty)
        XCTAssertEqual(try String(contentsOf: source, encoding: .utf8), "original")
        XCTAssertEqual(try String(contentsOf: destination, encoding: .utf8), "existing destination")
    }

    func testOpeningPackageSavesFieldValuesBackToThePackage() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let tabs = DocumentTabs(preferencesURL: root.appendingPathComponent("preferences.json"))
        defer { tabs.stop(); try? FileManager.default.removeItem(at: root) }
        let template = root.appendingPathComponent("form.mdlf")
        let package = root.appendingPathComponent("form.mdlz")
        let document = LeonardoDocument(
            body: "Name: {{field:name}}",
            metadata: LeonardoMetadata(
                document: LeonardoDocumentDescriptor(kind: .form),
                fields: ["name": LeonardoFieldDefinition(required: true)]
            )
        )
        let source = try LeonardoFormatParser.serialize(document)
        try source.write(to: template, atomically: true, encoding: .utf8)
        try LeonardoPackageTransport.export(documentURL: template, content: source, to: package)

        let session = tabs.activeSession
        session.packageOpenPreference = .package
        await session.open(package)
        XCTAssertEqual(session.documentStorage, .package)
        XCTAssertEqual(session.documentKind, .leonardoTemplate)
        await session.setDocumentMode(.fill)
        XCTAssertTrue(session.updateLeonardoField("name", text: "Ada"))
        await session.save()
        XCTAssertFalse(session.isDirty)

        let reopened = try LeonardoPackageTransport.open(package)
        defer { LeonardoPackageTransport.discard(reopened) }
        let loaded = try await session.documents.read(reopened.documentURL)
        XCTAssertEqual(try LeonardoFormatParser.parse(loaded.content).metadata.values["name"]?.stringValue, "Ada")
    }
    func testWorkspaceRenameRemapsStandaloneDocumentAndPreservesDraftAndMode() async throws {
        let (root, session) = try fixture()
        defer { session.stop(); try? FileManager.default.removeItem(at: root) }
        let project = try await session.files.createProject(named: "Project", in: root)
        let document = project.rootURL.appendingPathComponent("note.md")
        try "original".write(to: document, atomically: true, encoding: .utf8)
        await session.open(document)
        session.workspaceURL = root
        session.mode = .split
        session.content = "saved draft"
        session.contentChanged()
        await session.renameProject(project, to: "Renamed")
        let moved = root.appendingPathComponent("Renamed/note.md")
        XCTAssertEqual(session.documentURL, moved)
        XCTAssertEqual(session.snapshot?.url, moved)
        XCTAssertNil(session.projectURL)
        XCTAssertEqual(session.mode, .split)
        XCTAssertEqual(session.content, "saved draft")
        session.content = "after rename"
        await session.save()
        XCTAssertEqual(try String(contentsOf: moved, encoding: .utf8), "after rename")
        XCTAssertNil(session.errorMessage)
    }

    func testWorkspaceDeleteClearsStandaloneDescendantDocument() async throws {
        let (root, session) = try fixture()
        defer { session.stop(); try? FileManager.default.removeItem(at: root) }
        let project = try await session.files.createProject(named: "Project", in: root)
        let document = project.rootURL.appendingPathComponent("note.md")
        try "original".write(to: document, atomically: true, encoding: .utf8)
        await session.open(document)
        session.workspaceURL = root
        await session.deleteConfirmedProject(project)
        XCTAssertNil(session.documentURL)
        XCTAssertNil(session.snapshot)
        XCTAssertNil(session.projectURL)
        XCTAssertTrue(session.content.isEmpty)
        XCTAssertFalse(session.externalConflict)
        XCTAssertFalse(FileManager.default.fileExists(atPath: document.path))
        await session.checkExternalChanges()
        XCTAssertNil(session.errorMessage)
    }

    func testWorkspaceChangesPreserveStandaloneDocumentInSimilarlyNamedSibling() async throws {
        let (root, session) = try fixture()
        defer { session.stop(); try? FileManager.default.removeItem(at: root) }
        let project = try await session.files.createProject(named: "Project", in: root)
        let sibling = try await session.files.createProject(named: "ProjectSibling", in: root)
        let document = sibling.rootURL.appendingPathComponent("note.md")
        try "unrelated".write(to: document, atomically: true, encoding: .utf8)
        await session.open(document)
        session.workspaceURL = root
        await session.renameProject(project, to: "Renamed")
        await session.deleteConfirmedProject(ProjectDescriptor(name: "Renamed", rootURL: root.appendingPathComponent("Renamed")))
        XCTAssertEqual(session.documentURL, document)
        XCTAssertEqual(session.content, "unrelated")
        XCTAssertNil(session.projectURL)
        XCTAssertNil(session.errorMessage)
    }

}
