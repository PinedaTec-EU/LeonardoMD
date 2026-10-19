import XCTest
import LeonardoCore
import LeonardoSync
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

    private func leonardoFormFixture(
        in root: URL,
        name: String = "form"
    ) throws -> (template: URL, package: URL, source: String) {
        let template = root.appendingPathComponent(name).appendingPathExtension("mdlf")
        let package = root.appendingPathComponent(name).appendingPathExtension("mdlz")
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
        return (template, package, source)
    }

    private func leonardoResourceFormFixture(
        in root: URL,
        name: String,
        body: String
    ) throws -> (template: URL, asset: URL, source: String) {
        let template = root.appendingPathComponent(name).appendingPathExtension("mdlf")
        let asset = root.appendingPathComponent("logo.png")
        let document = LeonardoDocument(
            body: body,
            metadata: LeonardoMetadata(
                document: LeonardoDocumentDescriptor(kind: .form),
                fields: ["name": LeonardoFieldDefinition(required: true)]
            )
        )
        let source = try LeonardoFormatParser.serialize(document)
        try source.write(to: template, atomically: true, encoding: .utf8)
        try Data([137, 80, 78, 71, 1, 2, 3]).write(to: asset, options: .atomic)
        return (template, asset, source)
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

    func testMarkdownMigrationSeparatesYAMLFromLatestDraft() async throws {
        let (root, session) = try fixture()
        defer { session.stop(); try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("article.md")
        let header = "---\ntitle: Article\nauthor: José\ncustom:\n  nested: yes\n---\n"
        let original = header + "# Original\n"
        let editedBody = "# Edited article\n\nMy saved change,\n"
        try original.write(to: source, atomically: true, encoding: .utf8)
        await session.open(source)
        session.content = header + editedBody
        session.contentChanged()

        let migrated = await session.migrateMarkdownToLeonardo()

        XCTAssertTrue(migrated)
        let saved = try LeonardoFormatParser.parse(String(contentsOf: source.deletingPathExtension().appendingPathExtension("mdlf"), encoding: .utf8))
        XCTAssertEqual(saved.body, editedBody)
        XCTAssertEqual(saved.metadata.document.title, "Article")
        XCTAssertEqual(saved.metadata.values[LeonardoMarkdownMigration.frontMatterValueKey], .string(header))
        XCTAssertEqual(try String(contentsOf: source, encoding: .utf8), original)
        XCTAssertFalse(session.isDirty)
    }

    func testMarkdownMigrationPreservesValidLeonardoDocumentInDisguisedMarkdown() async throws {
        let (root, session) = try fixture()
        defer { session.stop(); try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("valid.md")
        let destination = root.appendingPathComponent("valid.mdlf")
        let document = LeonardoDocument(
            body: "Name: {{field:name}}",
            metadata: LeonardoMetadata(
                document: LeonardoDocumentDescriptor(kind: .form),
                fields: ["name": LeonardoFieldDefinition(required: true)],
                values: ["name": .string("Ada")]
            )
        )
        let original = try LeonardoFormatParser.serialize(document)
        try original.write(to: source, atomically: true, encoding: .utf8)

        await session.open(source)
        XCTAssertTrue(session.leonardoFormatWarning)
        let migrated = await session.migrateMarkdownToLeonardo()

        XCTAssertTrue(migrated)
        let loaded = try String(contentsOf: destination, encoding: .utf8)
        XCTAssertEqual(try LeonardoFormatParser.parse(loaded), document)
        XCTAssertEqual(try String(contentsOf: source, encoding: .utf8), original)
        XCTAssertEqual(session.documentURL, destination)
        XCTAssertEqual(session.documentKind, .leonardoTemplate)
        XCTAssertFalse(session.isDirty)
    }

    func testMarkdownMigrationRejectsFutureLeonardoVersionWithoutCreatingDestination() async throws {
        let (root, session) = try fixture()
        defer { session.stop(); try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("future.md")
        let destination = root.appendingPathComponent("future.mdlf")
        let original = """
        ---
        {
          "document" : { "kind" : "document" },
          "fields" : {},
          "format" : "mdlf",
          "formatVersion" : 99,
          "values" : {}
        }
        ---
        Future body
        """
        try original.write(to: source, atomically: true, encoding: .utf8)

        await session.open(source)
        var authorizationCalls = 0
        session.authorizePath = { _, _ in authorizationCalls += 1 }
        XCTAssertTrue(session.leonardoFormatWarning)
        let migrated = await session.migrateMarkdownToLeonardo()

        XCTAssertFalse(migrated)
        XCTAssertEqual(authorizationCalls, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
        XCTAssertEqual(try String(contentsOf: source, encoding: .utf8), original)
        XCTAssertEqual(session.documentURL, source)
        XCTAssertEqual(session.documentKind, .markdown)
        XCTAssertTrue(session.errorMessage?.contains("99") == true)
    }

    func testMarkdownMigrationRejectsMalformedLeonardoHeaderWithoutCreatingDestination() async throws {
        let (root, session) = try fixture()
        defer { session.stop(); try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("malformed.md")
        let destination = root.appendingPathComponent("malformed.mdlf")
        let original = """
        ---
        {
          "format" : "mdlf"
        }
        ---
        Malformed body
        """
        try original.write(to: source, atomically: true, encoding: .utf8)

        await session.open(source)
        var authorizationCalls = 0
        session.authorizePath = { _, _ in authorizationCalls += 1 }
        XCTAssertTrue(session.leonardoFormatWarning)
        let migrated = await session.migrateMarkdownToLeonardo()

        XCTAssertFalse(migrated)
        XCTAssertEqual(authorizationCalls, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
        XCTAssertEqual(try String(contentsOf: source, encoding: .utf8), original)
        XCTAssertEqual(session.documentURL, source)
        XCTAssertEqual(session.documentKind, .markdown)
        XCTAssertNotNil(session.errorMessage)
    }

    func testDeniedDirectMarkdownMigrationDoesNotCreateDestination() async throws {
        let (root, session) = try fixture()
        defer { session.stop(); try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("note.md")
        let destination = root.appendingPathComponent("note.mdlf")
        try "original".write(to: source, atomically: true, encoding: .utf8)
        await session.open(source)

        session.authorizePath = { _, _ in throw SyncError.outsideScope }
        let migrated = await session.migrateMarkdownToLeonardo()

        XCTAssertFalse(migrated)
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
        XCTAssertEqual(try String(contentsOf: source, encoding: .utf8), "original")
        XCTAssertEqual(session.documentURL, source)
        XCTAssertEqual(session.documentKind, .markdown)
        XCTAssertTrue(session.isProtected)
        XCTAssertNotNil(session.errorMessage)
    }

    func testMarkdownMigrationRejectsChangedSourceWithoutCreatingDestination() async throws {
        let (root, session) = try fixture()
        defer { session.stop(); try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("note.md")
        let destination = root.appendingPathComponent("note.mdlf")
        try "original".write(to: source, atomically: true, encoding: .utf8)
        await session.open(source)
        try "external".write(to: source, atomically: true, encoding: .utf8)

        let migrated = await session.migrateMarkdownToLeonardo()

        XCTAssertFalse(migrated)
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
        XCTAssertEqual(try String(contentsOf: source, encoding: .utf8), "external")
        XCTAssertEqual(session.documentURL, source)
        XCTAssertEqual(session.content, "original")
        XCTAssertTrue(session.externalConflict)
        XCTAssertNotNil(session.errorMessage)
    }

    func testDirectMarkdownMigrationRequiresAnIdleSession() async throws {
        let (root, session) = try fixture()
        defer { session.stop(); try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("note.md")
        let destination = root.appendingPathComponent("note.mdlf")
        try "original".write(to: source, atomically: true, encoding: .utf8)
        await session.open(source)

        session.busy = true
        let busyResult = await session.migrateMarkdownToLeonardo()
        XCTAssertFalse(busyResult)
        session.busy = false
        session.saving = true
        let savingResult = await session.migrateMarkdownToLeonardo()
        XCTAssertFalse(savingResult)
        session.saving = false
        session.fileOperationCount = 1
        let operationResult = await session.migrateMarkdownToLeonardo()
        XCTAssertFalse(operationResult)

        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
        XCTAssertEqual(session.documentURL, source)
    }

    func testMarkdownMigrationOnSaveAllowsAuthorizedClosingSave() async throws {
        let (root, session) = try fixture()
        let preferenceKey = "migrateMarkdownOnSave"
        let previousPreference = UserDefaults.standard.object(forKey: preferenceKey)
        defer {
            session.stop()
            try? FileManager.default.removeItem(at: root)
            if let previousPreference {
                UserDefaults.standard.set(previousPreference, forKey: preferenceKey)
            } else {
                UserDefaults.standard.removeObject(forKey: preferenceKey)
            }
        }

        let source = root.appendingPathComponent("closing.md")
        let destination = root.appendingPathComponent("closing.mdlf")
        try "original".write(to: source, atomically: true, encoding: .utf8)
        await session.open(source)
        session.migrateMarkdownOnSave = true
        session.content = "draft"
        session.contentChanged()
        session.isClosing = true

        await session.save(allowClosing: true)

        XCTAssertEqual(session.documentURL, destination)
        XCTAssertEqual(try String(contentsOf: source, encoding: .utf8), "original")
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.path))
        XCTAssertFalse(session.isDirty)
    }

    func testMarkdownMigrationRejectsDestinationCreatedDuringAuthorization() async throws {
        let (root, session) = try fixture()
        defer { session.stop(); try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("race.md")
        let destination = root.appendingPathComponent("race.mdlf")
        try "original".write(to: source, atomically: true, encoding: .utf8)
        await session.open(source)

        session.authorizePath = { url, _ in
            if url.standardizedFileURL == destination.standardizedFileURL {
                try "created during authorization".write(to: url, atomically: true, encoding: .utf8)
            }
        }
        let migrated = await session.migrateMarkdownToLeonardo()

        XCTAssertFalse(migrated)
        XCTAssertEqual(session.documentURL, source)
        XCTAssertEqual(session.documentKind, .markdown)
        XCTAssertEqual(try String(contentsOf: source, encoding: .utf8), "original")
        XCTAssertEqual(try String(contentsOf: destination, encoding: .utf8), "created during authorization")
        XCTAssertNotNil(session.errorMessage)
    }

    func testDeniedResponseExportsAuthorizeSourceBeforeWritingMDLRAndMDLZ() async throws {
        let (root, session) = try fixture()
        defer { session.stop(); try? FileManager.default.removeItem(at: root) }
        let fixture = try leonardoFormFixture(in: root)
        await session.open(fixture.template)

        for suffix in ["mdlr", "mdlz"] {
            let destination = root.appendingPathComponent("denied-source").appendingPathExtension(suffix)
            var authorized: [(URL, DesktopPeerPathIntent)] = []
            session.authorizePath = { url, intent in
                authorized.append((url, intent))
                if url.standardizedFileURL == fixture.template.standardizedFileURL {
                    throw SyncError.outsideScope
                }
            }

            await session.exportLeonardoResponse(
                to: destination,
                documentURL: fixture.template,
                panelRequiresPackage: false
            )

            XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
            XCTAssertTrue(authorized.contains {
                guard $0.0.standardizedFileURL == fixture.template.standardizedFileURL else { return false }
                if case .document = $0.1 { return true }
                return false
            })
        }
        XCTAssertEqual(try String(contentsOf: fixture.template, encoding: .utf8), fixture.source)
    }

    func testDeniedResponseExportsAuthorizeDestinationBeforeWritingMDLRAndMDLZ() async throws {
        let (root, session) = try fixture()
        defer { session.stop(); try? FileManager.default.removeItem(at: root) }
        let fixture = try leonardoFormFixture(in: root)
        await session.open(fixture.template)

        for suffix in ["mdlr", "mdlz"] {
            let destination = root.appendingPathComponent("denied-destination").appendingPathExtension(suffix)
            var authorized: [(URL, DesktopPeerPathIntent)] = []
            session.authorizePath = { url, intent in
                authorized.append((url, intent))
                if url.standardizedFileURL == destination.standardizedFileURL {
                    throw SyncError.outsideScope
                }
            }

            await session.exportLeonardoResponse(
                to: destination,
                documentURL: fixture.template,
                panelRequiresPackage: false
            )

            XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
            XCTAssertTrue(authorized.contains {
                guard $0.0.standardizedFileURL == fixture.template.standardizedFileURL else { return false }
                if case .document = $0.1 { return true }
                return false
            })
            XCTAssertTrue(authorized.contains {
                guard $0.0.standardizedFileURL == destination.standardizedFileURL else { return false }
                if case .document = $0.1 { return true }
                return false
            })
        }
        XCTAssertEqual(try String(contentsOf: fixture.template, encoding: .utf8), fixture.source)
    }

    func testResponseExportRejectsMDLRForHTMLAndReferenceImages() async throws {
        let (root, session) = try fixture()
        defer { session.stop(); try? FileManager.default.removeItem(at: root) }
        let cases = [
            ("html", "<img src=\"logo.png\" alt=\"Logo\">\n\nName: {{field:name}}"),
            ("reference", "![Logo][logo]\n\n[logo]: logo.png\n\nName: {{field:name}}")
        ]

        for (name, body) in cases {
            let fixture = try leonardoResourceFormFixture(in: root, name: name, body: body)
            let before = try Data(contentsOf: fixture.template)
            await session.open(fixture.template)
            let destination = root.appendingPathComponent("\(name)-response.mdlr")
            session.errorMessage = nil

            // A stale or manually overridden panel selection must not produce
            // a non-portable response when the document contains local media.
            await session.exportLeonardoResponse(
                to: destination,
                documentURL: fixture.template,
                panelRequiresPackage: false
            )

            XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
            XCTAssertEqual(try Data(contentsOf: fixture.template), before)
            XCTAssertNotNil(session.errorMessage)
        }
    }

    func testResponseExportPackagesHTMLAndReferenceImagesInMovedFolder() async throws {
        let (root, session) = try fixture()
        defer { session.stop(); try? FileManager.default.removeItem(at: root) }
        let moved = root.appendingPathComponent("moved")
        try FileManager.default.createDirectory(at: moved, withIntermediateDirectories: true)
        let cases = [
            ("html", "<img src=\"logo.png\" alt=\"Logo\">\n\nName: {{field:name}}"),
            ("reference", "![Logo][logo]\n\n[logo]: logo.png\n\nName: {{field:name}}")
        ]

        for (name, body) in cases {
            let fixture = try leonardoResourceFormFixture(in: root, name: name, body: body)
            let before = try Data(contentsOf: fixture.template)
            await session.open(fixture.template)
            let destination = moved.appendingPathComponent("\(name)-response.mdlz")

            await session.exportLeonardoResponse(
                to: destination,
                documentURL: fixture.template,
                panelRequiresPackage: false
            )

            XCTAssertTrue(FileManager.default.fileExists(atPath: destination.path))
            XCTAssertEqual(try Data(contentsOf: fixture.template), before)
            let workspace = try LeonardoPackageTransport.open(destination)
            defer { LeonardoPackageTransport.discard(workspace) }
            let loaded = try String(contentsOf: workspace.documentURL, encoding: .utf8)
            let parsed = try LeonardoFormatParser.parse(loaded)
            XCTAssertTrue(parsed.body.contains("assets/"))
            let assetsURL = workspace.directoryURL.appendingPathComponent("assets", isDirectory: true)
            let assets = try FileManager.default.contentsOfDirectory(
                at: assetsURL,
                includingPropertiesForKeys: nil
            )
            XCTAssertEqual(assets.count, 1)
            let sourceAsset = try Data(contentsOf: fixture.asset)
            let packagedAssetURL = try XCTUnwrap(assets.first)
            let packagedAsset = try Data(contentsOf: packagedAssetURL)
            XCTAssertEqual(packagedAsset, sourceAsset)
        }
    }

    func testResponseExportIgnoresCodeOnlyImageReferences() async throws {
        let (root, session) = try fixture()
        defer { session.stop(); try? FileManager.default.removeItem(at: root) }
        let fixture = try leonardoResourceFormFixture(
            in: root,
            name: "code-only",
            body: "```html\n<img src=\"logo.png\">\n```\n\nName: {{field:name}}"
        )
        let before = try Data(contentsOf: fixture.template)
        await session.open(fixture.template)
        let destination = root.appendingPathComponent("code-only-response.mdlr")

        await session.exportLeonardoResponse(
            to: destination,
            documentURL: fixture.template,
            panelRequiresPackage: false
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.path))
        XCTAssertEqual(try Data(contentsOf: fixture.template), before)
    }

    func testDeniedPackageResponseExportAuthorizesOriginalPackageBeforeWritingMDLZ() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let session = AppSession(preferencesURL: root.appendingPathComponent("preferences.json"))
        defer { session.stop(); try? FileManager.default.removeItem(at: root) }
        let fixture = try leonardoFormFixture(in: root)
        let opened = await session.openLeonardoPackage(fixture.package, extractingTo: nil)
        XCTAssertTrue(opened)
        let workingURL = try XCTUnwrap(session.documentURL)
        let output = root.appendingPathComponent("package-response.mdlz")
        let packageBefore = try Data(contentsOf: fixture.package)
        let workingBefore = try Data(contentsOf: workingURL)
        var authorized: [(URL, DesktopPeerPathIntent)] = []
        session.authorizePath = { url, intent in
            authorized.append((url, intent))
            if url.standardizedFileURL == fixture.package.standardizedFileURL {
                throw SyncError.outsideScope
            }
        }

        await session.exportLeonardoResponse(to: output, documentURL: workingURL, panelRequiresPackage: false)

        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
        XCTAssertEqual(try Data(contentsOf: fixture.package), packageBefore)
        XCTAssertEqual(try Data(contentsOf: workingURL), workingBefore)
        XCTAssertTrue(authorized.contains {
            guard $0.0.standardizedFileURL == workingURL.standardizedFileURL else { return false }
            if case .document = $0.1 { return true }
            return false
        })
        XCTAssertTrue(authorized.contains {
            guard $0.0.standardizedFileURL == fixture.package.standardizedFileURL else { return false }
            if case .document = $0.1 { return true }
            return false
        })
    }

    func testDeniedLeonardoPackageExportAuthorizesDestinationBeforeWriting() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let session = AppSession(preferencesURL: root.appendingPathComponent("preferences.json"))
        defer { session.stop(); try? FileManager.default.removeItem(at: root) }
        let fixture = try leonardoFormFixture(in: root)
        let opened = await session.openLeonardoPackage(fixture.package, extractingTo: nil)
        XCTAssertTrue(opened)
        let workingURL = try XCTUnwrap(session.documentURL)
        let output = root.appendingPathComponent("package-export.mdlz")
        var authorized: [(URL, DesktopPeerPathIntent)] = []
        session.authorizePath = { url, intent in
            authorized.append((url, intent))
            if url.standardizedFileURL == output.standardizedFileURL {
                throw SyncError.outsideScope
            }
        }

        await session.exportLeonardoPackage(to: output, documentURL: workingURL)

        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
        XCTAssertTrue(authorized.contains {
            guard $0.0.standardizedFileURL == workingURL.standardizedFileURL else { return false }
            if case .document = $0.1 { return true }
            return false
        })
        XCTAssertTrue(authorized.contains {
            guard $0.0.standardizedFileURL == fixture.package.standardizedFileURL else { return false }
            if case .document = $0.1 { return true }
            return false
        })
        XCTAssertTrue(authorized.contains {
            guard $0.0.standardizedFileURL == output.standardizedFileURL else { return false }
            if case .document = $0.1 { return true }
            return false
        })
    }

    func testDeniedPackageExtractionDoesNotCreateWorkspaceBeforeAuthorization() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let sourceSession = AppSession(preferencesURL: root.appendingPathComponent("source-preferences.json"))
        let destinationSession = AppSession(preferencesURL: root.appendingPathComponent("destination-preferences.json"))
        defer {
            sourceSession.stop()
            destinationSession.stop()
            try? FileManager.default.removeItem(at: root)
        }
        let fixture = try leonardoFormFixture(in: root)
        let sourceDeniedFolder = root.appendingPathComponent("source-denied")
        var sourceCalls: [(URL, DesktopPeerPathIntent)] = []
        sourceSession.authorizePath = { url, intent in
            sourceCalls.append((url, intent))
            throw SyncError.outsideScope
        }
        let sourceOpened = await sourceSession.openLeonardoPackage(fixture.package, extractingTo: sourceDeniedFolder)
        XCTAssertFalse(sourceOpened)
        XCTAssertFalse(FileManager.default.fileExists(atPath: sourceDeniedFolder.path))
        XCTAssertTrue(sourceCalls.contains {
            guard $0.0.standardizedFileURL == fixture.package.standardizedFileURL else { return false }
            if case .document = $0.1 { return true }
            return false
        })

        let destinationDeniedFolder = root.appendingPathComponent("destination-denied")
        var destinationCalls: [(URL, DesktopPeerPathIntent)] = []
        destinationSession.authorizePath = { url, intent in
            destinationCalls.append((url, intent))
            if url.standardizedFileURL == destinationDeniedFolder.standardizedFileURL {
                throw SyncError.outsideScope
            }
        }
        let destinationOpened = await destinationSession.openLeonardoPackage(fixture.package, extractingTo: destinationDeniedFolder)
        XCTAssertFalse(destinationOpened)
        XCTAssertFalse(FileManager.default.fileExists(atPath: destinationDeniedFolder.path))
        XCTAssertTrue(destinationCalls.contains {
            guard $0.0.standardizedFileURL == destinationDeniedFolder.standardizedFileURL else { return false }
            if case .directoryMutation = $0.1 { return true }
            return false
        })
    }

    func testExtractedPackageUsesWorkingFileIdentityForExportAuthorization() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let session = AppSession(preferencesURL: root.appendingPathComponent("preferences.json"))
        defer { session.stop(); try? FileManager.default.removeItem(at: root) }
        let fixture = try leonardoFormFixture(in: root)
        let extraction = root.appendingPathComponent("extracted")
        session.authorizePath = { _, _ in }
        let opened = await session.openLeonardoPackage(fixture.package, extractingTo: extraction)
        XCTAssertTrue(opened)
        XCTAssertEqual(session.documentStorage, .extracted)
        XCTAssertEqual(session.documentSourceURL?.standardizedFileURL, fixture.package.standardizedFileURL)
        let workingURL = try XCTUnwrap(session.documentURL)
        XCTAssertTrue(workingURL.path.hasPrefix(extraction.path + "/"))

        let output = root.appendingPathComponent("extracted-response.mdlr")
        var authorized: [(URL, DesktopPeerPathIntent)] = []
        session.authorizePath = { url, intent in
            authorized.append((url, intent))
            if url.standardizedFileURL == fixture.package.standardizedFileURL {
                throw SyncError.outsideScope
            }
        }
        await session.exportLeonardoResponse(to: output, documentURL: workingURL, panelRequiresPackage: false)

        XCTAssertTrue(FileManager.default.fileExists(atPath: output.path))
        XCTAssertTrue(authorized.contains {
            guard $0.0.standardizedFileURL == workingURL.standardizedFileURL else { return false }
            if case .document = $0.1 { return true }
            return false
        })
        XCTAssertFalse(authorized.contains {
            $0.0.standardizedFileURL == fixture.package.standardizedFileURL
        })
    }

    func testResponseExportRevalidatesDocumentIdentityAfterAuthorization() async throws {
        let (root, session) = try fixture()
        defer { session.stop(); try? FileManager.default.removeItem(at: root) }
        let fixture = try leonardoFormFixture(in: root)
        let other = root.appendingPathComponent("other.mdlf")
        let destination = root.appendingPathComponent("identity-race.mdlr")
        await session.open(fixture.template)
        session.authorizePath = { url, _ in
            if url.standardizedFileURL == fixture.template.standardizedFileURL {
                session.documentURL = other
            }
        }

        await session.exportLeonardoResponse(
            to: destination,
            documentURL: fixture.template,
            panelRequiresPackage: false
        )

        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
        XCTAssertEqual(session.documentURL, other)
    }

    func testResponseExportStopsWithoutWritingWhenAuthorizationStopsSession() async throws {
        let (root, session) = try fixture()
        defer { session.stop(); try? FileManager.default.removeItem(at: root) }
        let fixture = try leonardoFormFixture(in: root)
        let destination = root.appendingPathComponent("stopped-race.mdlz")
        await session.open(fixture.template)
        session.authorizePath = { _, _ in session.stop() }

        await session.exportLeonardoResponse(
            to: destination,
            documentURL: fixture.template,
            panelRequiresPackage: false
        )

        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
        XCTAssertTrue(session.stopped)
    }

    func testPackageExtractionRevalidatesSessionIdentityBeforeTransportWrites() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let changedSession = AppSession(preferencesURL: root.appendingPathComponent("changed-preferences.json"))
        let stoppedSession = AppSession(preferencesURL: root.appendingPathComponent("stopped-preferences.json"))
        defer {
            changedSession.stop()
            stoppedSession.stop()
            try? FileManager.default.removeItem(at: root)
        }
        let fixture = try leonardoFormFixture(in: root)
        let current = root.appendingPathComponent("current.md")
        try "current".write(to: current, atomically: true, encoding: .utf8)
        await changedSession.open(current)
        let changedDestination = root.appendingPathComponent("changed-extraction")
        let other = root.appendingPathComponent("other.md")
        changedSession.authorizePath = { url, _ in
            if url.standardizedFileURL == fixture.package.standardizedFileURL {
                changedSession.documentURL = other
            }
        }
        let changedOpened = await changedSession.openLeonardoPackage(
            fixture.package,
            extractingTo: changedDestination
        )
        XCTAssertFalse(changedOpened)
        XCTAssertFalse(FileManager.default.fileExists(atPath: changedDestination.path))
        XCTAssertEqual(changedSession.documentURL, other)

        let stoppedDestination = root.appendingPathComponent("stopped-extraction")
        stoppedSession.authorizePath = { _, _ in stoppedSession.stop() }
        let stoppedOpened = await stoppedSession.openLeonardoPackage(
            fixture.package,
            extractingTo: stoppedDestination
        )
        XCTAssertFalse(stoppedOpened)
        XCTAssertFalse(FileManager.default.fileExists(atPath: stoppedDestination.path))
        XCTAssertTrue(stoppedSession.stopped)
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

    func testDeniedPackageSaveAuthorizesPackageBeforeWritingWorkingDocument() async throws {
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
        let packageBefore = try Data(contentsOf: package)

        let session = tabs.activeSession
        session.packageOpenPreference = .package
        await session.open(package)
        let workingURL = try XCTUnwrap(session.documentURL)
        let workingBefore = try Data(contentsOf: workingURL)
        await session.setDocumentMode(.fill)
        XCTAssertTrue(session.updateLeonardoField("name", text: "Ada"))

        var authorized: [(URL, DesktopPeerPathIntent)] = []
        session.authorizePath = { url, intent in
            authorized.append((url, intent))
            if url.standardizedFileURL == package.standardizedFileURL {
                throw SyncError.outsideScope
            }
        }
        await session.save()

        XCTAssertTrue(authorized.contains {
            guard $0.0.standardizedFileURL == package.standardizedFileURL else { return false }
            if case .document = $0.1 { return true }
            return false
        })
        XCTAssertEqual(try Data(contentsOf: package), packageBefore)
        XCTAssertEqual(try Data(contentsOf: workingURL), workingBefore)
        XCTAssertTrue(session.isDirty)
        XCTAssertNotNil(session.errorMessage)
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
