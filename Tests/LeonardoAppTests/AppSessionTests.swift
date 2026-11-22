import XCTest
import LeonardoCore
import LeonardoSync
@testable import LeonardoApp

@MainActor
final class AppSessionTests: XCTestCase {
    private func fixture(
        signingCredentialStore: LeonardoSigningCredentialStore = LeonardoSigningCredentialStore()
    ) throws -> (URL, AppSession) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let session = AppSession(
            preferencesURL: root.appendingPathComponent("preferences.json"),
            signingCredentialStore: signingCredentialStore
        )
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

    func testProjectSearchHidesNonDocumentsUntilPreferenceIsEnabled() async throws {
        let (root, session) = try fixture()
        defer { session.stop(); try? FileManager.default.removeItem(at: root) }
        let image = root.appendingPathComponent("logo.png")
        try Data([137, 80, 78, 71]).write(to: image, options: .atomic)
        await session.openProject(root)

        session.searchQuery = "logo.png"
        session.scheduleSearch()
        await session.searchTask?.value
        XCTAssertTrue(session.searchResults.isEmpty)

        session.setShowNonDocumentFiles(true)
        await session.settingsTask?.value
        await session.searchTask?.value
        XCTAssertEqual(session.searchResults.map { $0.url.lastPathComponent }, ["logo.png"])

        session.setShowNonDocumentFiles(false)
        await session.settingsTask?.value
        await session.searchTask?.value
        XCTAssertTrue(session.searchResults.isEmpty)
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

    func testAdditionalExtensionTogglesPersistAndRespectProjectInheritance() async throws {
        let (root, session) = try fixture()
        defer { session.stop(); try? FileManager.default.removeItem(at: root) }
        await session.openProject(root)

        session.setVegaLite(true)
        session.setCitations(true)
        session.setMarkdownExtensions(true)
        await session.settingsTask?.value

        XCTAssertTrue(session.features.vegaLiteEnabled)
        XCTAssertTrue(session.features.citationsEnabled)
        XCTAssertTrue(session.features.markdownExtensionsEnabled)
        let project = try await session.configurations.loadProjectConfiguration(for: root)
        XCTAssertTrue(project.markdown?.vegaLiteEnabled == true)
        XCTAssertTrue(project.markdown?.citationsEnabled == true)
        XCTAssertTrue(project.markdown?.markdownExtensionsEnabled == true)

        session.inheritFeatures(true)
        await session.settingsTask?.value
        XCTAssertNil(session.projectConfiguration.markdown)
        XCTAssertFalse(session.features.vegaLiteEnabled)
        XCTAssertFalse(session.features.citationsEnabled)
        XCTAssertFalse(session.features.markdownExtensionsEnabled)

        session.setVegaLite(true, project: false)
        session.setCitations(true, project: false)
        session.setMarkdownExtensions(true, project: false)
        await session.settingsTask?.value
        XCTAssertTrue(session.features.vegaLiteEnabled)
        XCTAssertTrue(session.features.citationsEnabled)
        XCTAssertTrue(session.features.markdownExtensionsEnabled)
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

    func testReopenWithoutInspectorKeepsBoundSigningProgressFailClosedAfterHeaderRemoval() async throws {
        let credentials = LeonardoSigningCredentialStore(service: "eu.pinedatec.LeonardoMD.tests.signing.\(UUID())")
        let (root, first) = try fixture(signingCredentialStore: credentials)
        defer { first.stop(); try? FileManager.default.removeItem(at: root) }
        let documentURL = root.appendingPathComponent("guided.mdlf")
        let declaration = LeonardoSigningDeclaration(positions: [
            LeonardoSignerPosition(id: "owner", label: "Owner")
        ])
        let v2 = LeonardoDocument(
            body: "Signature: {{field:signature}}",
            metadata: LeonardoMetadata(
                formatVersion: LeonardoFormat.signingVersion,
                document: LeonardoDocumentDescriptor(
                    id: "bound-document", title: "Bound", kind: .form, revision: 1, signing: declaration
                ),
                fields: ["signature": LeonardoFieldDefinition(type: .rubric, signerPosition: "owner")]
            )
        )
        try LeonardoFormatParser.serialize(v2).write(to: documentURL, atomically: true, encoding: .utf8)
        first.authorizePath = { _, _ in }
        await first.openDocument(documentURL)
        XCTAssertTrue(first.guidedSigningReady, first.guidedSigningError ?? "")
        XCTAssertNotNil(first.guidedSigningSession)
        XCTAssertFalse(first.showInspector)
        first.isProtected = false
        let key = LeonardoSigningKeyPair(credentialID: "bound-owner")
        let profile = LeonardoSignerProfile(
            displayName: "Owner",
            identity: LeonardoDeclaredIdentity(
                fullName: "Owner", documentType: .nationalID, documentNumber: "BOUND-1"
            )
        )
        await first.assignGuidedSigner(
            positionID: "owner", profile: profile, credential: key.credential,
            saveOptions: .init(saveIdentityDetails: false, saveRubric: false)
        )
        await first.beginGuidedPosition("owner")
        let target = try XCTUnwrap(first.guidedSigningTargets.first)
        await first.confirmGuidedLocation(
            target: target,
            rubric: LeonardoRubric(strokes: [LeonardoInkStroke(
                color: "#111111", width: 2, style: .solid,
                points: [LeonardoInkPoint(x: 1, y: 1), LeonardoInkPoint(x: 2, y: 2)]
            )]),
            reuse: .new,
            reuseConfirmed: false,
            contextRead: true, renderedPlanMatches: { _, _ in true }
        )
        XCTAssertNotNil(first.guidedSigningSession?.snapshot)

        let legacy = LeonardoDocument(
            body: "Name: {{field:name}}",
            metadata: LeonardoMetadata(
                document: LeonardoDocumentDescriptor(id: "bound-document", title: "Bound", kind: .form),
                fields: ["name": LeonardoFieldDefinition(type: .text, required: true)]
            )
        )
        try LeonardoFormatParser.serialize(legacy).write(to: documentURL, atomically: true, encoding: .utf8)

        let reopened = AppSession(
            preferencesURL: first.globalPreferencesURL,
            signingCredentialStore: credentials
        )
        defer { reopened.stop() }
        reopened.authorizePath = { _, _ in }
        await reopened.openDocument(documentURL)
        reopened.isProtected = false
        reopened.mode = .fill

        XCTAssertFalse(reopened.showInspector)
        XCTAssertNotNil(reopened.guidedSigningSession)
        XCTAssertNotNil(reopened.guidedSigningError)
        XCTAssertTrue(reopened.externalConflict)
        XCTAssertTrue(reopened.guidedSigningCanStartRevision)
        XCTAssertTrue(reopened.guidedSigningContentLocked)
        XCTAssertFalse(reopened.editDocument(expected: reopened.content, replacement: "edited source"))
        XCTAssertNil(reopened.updateLeonardoFields(
            expected: reopened.content,
            changes: ["name": .string("edited form")]
        ))

        await reopened.startGuidedSigningRevision()
        XCTAssertEqual(reopened.guidedSigningSession?.initialRevision, 2)
        XCTAssertNil(reopened.guidedSigningSession?.snapshot)
        XCTAssertTrue(reopened.externalConflict)
        XCTAssertTrue(reopened.guidedSigningStatus?.contains("Save a copy") == true)
        XCTAssertEqual(try LeonardoFormatParser.parse(reopened.content).body, v2.body)
        XCTAssertEqual(try String(contentsOf: documentURL, encoding: .utf8), try LeonardoFormatParser.serialize(legacy))
        let recoveredSession = try XCTUnwrap(reopened.guidedSigningSession)
        await reopened.beginGuidedPosition("owner")
        XCTAssertEqual(reopened.guidedSigningSession, recoveredSession)
        XCTAssertNotNil(reopened.guidedSigningActionProblem)

        let copyURL = root.appendingPathComponent("guided-recovered-copy.mdlf")
        await reopened.saveCopyAndOpen(to: copyURL, sourceURL: documentURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: copyURL.path))
        XCTAssertFalse(reopened.externalConflict)
        reopened.isProtected = false
        await reopened.prepareGuidedSigningIfNeeded()
        await reopened.assignGuidedSigner(
            positionID: "owner", profile: profile, credential: key.credential,
            saveOptions: .init(saveIdentityDetails: false, saveRubric: false)
        )
        await reopened.beginGuidedPosition("owner")
        XCTAssertEqual(reopened.guidedSigningSession?.positions["owner"]?.state, .reviewing)
    }

    func testReopenAfterDiscardingNewRevisionSelectsExactHistoricalSession() async throws {
        let credentials = LeonardoSigningCredentialStore(
            service: "eu.pinedatec.LeonardoMD.tests.signing.revision.\(UUID())"
        )
        let (root, first) = try fixture(signingCredentialStore: credentials)
        defer { first.stop(); try? FileManager.default.removeItem(at: root) }
        let documentURL = root.appendingPathComponent("revision-bound.mdlf")
        let declaration = LeonardoSigningDeclaration(positions: [
            LeonardoSignerPosition(id: "owner", label: "Owner")
        ])
        let original = LeonardoDocument(
            body: "Signature: {{field:signature}}",
            metadata: LeonardoMetadata(
                formatVersion: LeonardoFormat.signingVersion,
                document: LeonardoDocumentDescriptor(
                    id: "revision-bound", title: "Revision bound", kind: .form,
                    revision: 1, signing: declaration
                ),
                fields: [
                    "signature": LeonardoFieldDefinition(type: .rubric, signerPosition: "owner")
                ]
            )
        )
        let originalSource = try LeonardoFormatParser.serialize(original)
        try originalSource.write(to: documentURL, atomically: true, encoding: .utf8)
        first.authorizePath = { _, _ in }
        await first.openDocument(documentURL)
        XCTAssertTrue(first.guidedSigningReady, first.guidedSigningError ?? "")
        let originalSession = try XCTUnwrap(first.guidedSigningSession)
        first.isProtected = false
        first.mode = .fill

        await first.startGuidedSigningRevision()
        XCTAssertEqual(first.guidedSigningSession?.initialRevision, 2)
        let history = try await first.guidedSigningStore.sessions()
        XCTAssertEqual(history.compactMap(\.initialRevision).sorted(), [1, 2])

        // The revision edit is intentionally discarded from the open buffer;
        // the coordinated source on disk is still the original revision.
        let reopened = AppSession(
            preferencesURL: first.globalPreferencesURL,
            signingCredentialStore: credentials
        )
        defer { reopened.stop() }
        reopened.authorizePath = { _, _ in }
        await reopened.openDocument(documentURL)

        XCTAssertEqual(reopened.guidedSigningSession?.id, originalSession.id)
        XCTAssertEqual(reopened.guidedSigningSession?.initialRevision, 1)
        XCTAssertNil(reopened.guidedSigningError)
        XCTAssertTrue(reopened.guidedSigningReady)

        // A discarded revision remains an audit sidecar. Retrying the
        // correction must skip its retained revision rather than colliding
        // with it or mutating the old session.
        reopened.isProtected = false
        reopened.mode = .fill
        await reopened.startGuidedSigningRevision()
        XCTAssertEqual(reopened.guidedSigningSession?.initialRevision, 3)
        XCTAssertEqual(try LeonardoFormatParser.parse(reopened.content).metadata.document.revision, 3)
        let retriedHistory = try await reopened.guidedSigningStore.sessions()
        XCTAssertEqual(retriedHistory.compactMap(\.initialRevision).sorted(), [1, 2, 3])
        XCTAssertTrue(retriedHistory.contains { $0.id == originalSession.id && $0.initialRevision == 1 })
    }

    func testFirstGuidedSealRequiresSavedAuthoritativeBufferAfterFailedSave() async throws {
        let credentials = LeonardoSigningCredentialStore(
            service: "eu.pinedatec.LeonardoMD.tests.signing.first-seal.\(UUID())"
        )
        let (root, session) = try fixture(signingCredentialStore: credentials)
        defer { session.stop(); try? FileManager.default.removeItem(at: root) }
        let documentURL = root.appendingPathComponent("first-seal.mdlf")
        let declaration = LeonardoSigningDeclaration(positions: [
            LeonardoSignerPosition(id: "owner", label: "Owner"),
            LeonardoSignerPosition(id: "witness", label: "Witness")
        ])
        let document = LeonardoDocument(
            body: "Signature: {{field:signature}}\n\nWitness: {{field:witness}}",
            metadata: LeonardoMetadata(
                formatVersion: LeonardoFormat.signingVersion,
                document: LeonardoDocumentDescriptor(
                    id: "first-seal", title: "First seal", kind: .form,
                    revision: 1, signing: declaration
                ),
                fields: [
                    "signature": LeonardoFieldDefinition(type: .rubric, signerPosition: "owner"),
                    "witness": LeonardoFieldDefinition(type: .rubric, signerPosition: "witness")
                ]
            )
        )
        let originalSource = try LeonardoFormatParser.serialize(document)
        try originalSource.write(to: documentURL, atomically: true, encoding: .utf8)
        session.authorizePath = { _, _ in }
        await session.openDocument(documentURL)
        session.isProtected = false

        let key = LeonardoSigningKeyPair(credentialID: "first-seal-owner")
        let profile = LeonardoSignerProfile(
            displayName: "Owner",
            identity: LeonardoDeclaredIdentity(
                fullName: "Owner", documentType: .nationalID, documentNumber: "FIRST-1"
            )
        )
        await session.assignGuidedSigner(
            positionID: "owner", profile: profile, credential: key.credential,
            saveOptions: .init(saveIdentityDetails: false, saveRubric: false)
        )
        await session.beginGuidedPosition("owner")
        let staleTarget = try XCTUnwrap(session.guidedSigningTargets.first)
        let draftSource = originalSource.replacingOccurrences(of: "Signature:", with: "Updated signature:")
        session.content = draftSource
        session.contentChanged()
        await session.beginGuidedPosition("owner")
        let target = try XCTUnwrap(session.guidedSigningTargets.first)
        let rubric = LeonardoRubric(strokes: [LeonardoInkStroke(
            color: "#111111", width: 2, style: .solid,
            points: [LeonardoInkPoint(x: 1, y: 1), LeonardoInkPoint(x: 2, y: 2)]
        )])
        let sessionID = try XCTUnwrap(session.guidedSigningSession?.id)
        let persistedBefore = try await session.guidedSigningStore.session(id: sessionID)
        let before = try XCTUnwrap(persistedBefore)

        await session.confirmGuidedLocation(
            target: target, rubric: rubric, reuse: .new,
            reuseConfirmed: false, contextRead: true, renderedPlanMatches: { _, _ in true }
        )
        XCTAssertTrue(session.isDirty)
        XCTAssertNil(session.guidedSigningSession?.snapshot)
        let afterDirtyConfirm = try await session.guidedSigningStore.session(id: sessionID)
        XCTAssertNil(afterDirtyConfirm?.snapshot)
        XCTAssertEqual(session.guidedSigningActionProblem, L10n.text(
            "Save the document before confirming the first signing location."
        ))

        session.authorizePath = { _, _ in throw SyncError.outsideScope }
        await session.save()
        XCTAssertTrue(session.isDirty)
        XCTAssertEqual(try String(contentsOf: documentURL, encoding: .utf8), originalSource)
        let afterFailedSave = try await session.guidedSigningStore.session(id: sessionID)
        XCTAssertEqual(afterFailedSave, before)

        session.authorizePath = { _, _ in }
        await session.confirmGuidedLocation(
            target: target, rubric: rubric, reuse: .new,
            reuseConfirmed: false, contextRead: true, renderedPlanMatches: { _, _ in true }
        )
        XCTAssertNil(session.guidedSigningSession?.snapshot)
        await session.save()
        XCTAssertFalse(session.isDirty)
        XCTAssertNotEqual(staleTarget, target)
        await session.confirmGuidedLocation(
            target: staleTarget, rubric: rubric, reuse: .new,
            reuseConfirmed: false, contextRead: true, renderedPlanMatches: { _, _ in true }
        )
        XCTAssertNil(session.guidedSigningSession?.snapshot)
        let afterStaleConfirm = try await session.guidedSigningStore.session(id: sessionID)
        XCTAssertEqual(afterStaleConfirm, before)
        XCTAssertNil(session.guidedSigningError)
        XCTAssertEqual(session.guidedSigningActionProblem, L10n.text(
            "The field context changed. Review this occurrence again before confirming."
        ))
        await session.confirmGuidedLocation(
            target: target, rubric: rubric, reuse: .new, reuseConfirmed: false, contextRead: true,
            renderedPlanMatches: { counts, source in
                XCTAssertEqual(counts, ["signature": 1, "witness": 1])
                XCTAssertEqual(source, draftSource)
                return false
            }
        )
        XCTAssertNil(session.guidedSigningSession?.snapshot)
        XCTAssertNil(session.guidedSigningError)

        let changedOnDisk = draftSource.replacingOccurrences(of: "Updated signature:", with: "External edit:")
        await session.confirmGuidedLocation(
            target: target, rubric: rubric, reuse: .new, reuseConfirmed: false, contextRead: true,
            renderedPlanMatches: { _, _ in
                do {
                    try changedOnDisk.write(to: documentURL, atomically: true, encoding: .utf8)
                    return true
                } catch {
                    XCTFail("Could not update the saved source during review: \(error)")
                    return false
                }
            }
        )
        XCTAssertTrue(session.externalConflict)
        XCTAssertNil(session.guidedSigningSession?.snapshot)
        let afterExternalConfirmation = try await session.guidedSigningStore.session(id: sessionID)
        XCTAssertEqual(afterExternalConfirmation, before)

        try draftSource.write(to: documentURL, atomically: true, encoding: .utf8)
        await session.reloadFromDisk()
        XCTAssertFalse(session.externalConflict)
        await session.confirmGuidedLocation(
            target: target, rubric: rubric, reuse: .new,
            reuseConfirmed: false, contextRead: true, renderedPlanMatches: { _, _ in true }
        )
        XCTAssertNotNil(session.guidedSigningSession?.snapshot)
        XCTAssertEqual(try String(contentsOf: documentURL, encoding: .utf8), draftSource)
        let afterSeal = try await session.guidedSigningStore.session(id: sessionID)
        XCTAssertNotNil(afterSeal?.snapshot)

        try await credentials.trustPublicCredential(key.credential)
        await session.signGuidedPosition(positionID: "owner", password: "test-only") { id, _ in
            XCTAssertEqual(id, key.credential.id)
            try changedOnDisk.write(to: documentURL, atomically: true, encoding: .utf8)
            return key
        }
        XCTAssertTrue(session.externalConflict)
        XCTAssertTrue(session.guidedSigningSnapshotChanged)
        XCTAssertTrue(session.guidedSigningVerification.isEmpty)
        let afterExternalSign = try await session.guidedSigningStore.session(id: sessionID)
        XCTAssertEqual(afterExternalSign, afterSeal)
    }

    func testSigningCopyExportAuthorizesPackageSourceAndDestinationBeforeWriting() async throws {
        let credentials = LeonardoSigningCredentialStore(
            service: "eu.pinedatec.LeonardoMD.tests.signing.export-permissions.\(UUID())"
        )
        let (root, session) = try fixture(signingCredentialStore: credentials)
        defer { session.stop(); try? FileManager.default.removeItem(at: root) }
        let original = root.appendingPathComponent("form.mdlf")
        let package = root.appendingPathComponent("form.mdlz")
        let document = LeonardoDocument(
            body: "Signature: {{field:signature}}",
            metadata: LeonardoMetadata(
                formatVersion: LeonardoFormat.signingVersion,
                document: .init(id: "export-permissions", kind: .form, revision: 1,
                    signing: .init(positions: [.init(id: "owner", label: "Owner")])),
                fields: ["signature": .init(type: .rubric, signerPosition: "owner")]
            )
        )
        let source = try LeonardoFormatParser.serialize(document)
        try source.write(to: original, atomically: true, encoding: .utf8)
        try LeonardoPackageTransport.export(documentURL: original, content: source, to: package)
        session.authorizePath = { _, _ in }
        let opened = await session.openLeonardoPackage(package, extractingTo: nil)
        XCTAssertTrue(opened)
        await session.prepareGuidedSigningIfNeeded()
        let workingFile = try XCTUnwrap(session.documentURL).standardizedFileURL
        let destination = root.appendingPathComponent("existing-signing-copy.json").standardizedFileURL
        let existing = Data("Unrelated file already at destination".utf8)
        try existing.write(to: destination)
        let paths = [workingFile, package.standardizedFileURL, destination]

        for (index, denied) in paths.enumerated() {
            var authorized: [URL] = []
            session.authorizePath = { url, intent in
                guard case .document = intent else {
                    XCTFail("Signing copy must request document authorization")
                    throw SyncError.outsideScope
                }
                authorized.append(url.standardizedFileURL)
                if url.standardizedFileURL == denied { throw SyncError.outsideScope }
            }
            await session.exportGuidedSigningExchange { _ in destination }
            XCTAssertEqual(authorized, Array(paths.prefix(index + 1)))
            XCTAssertEqual(try Data(contentsOf: destination), existing)
            XCTAssertNotNil(session.guidedSigningActionProblem)
            XCTAssertFalse(session.guidedSigningContentLocked)
            XCTAssertEqual(session.fileOperationCount, 0)
        }

        session.authorizePath = { _, _ in }
        await session.exportGuidedSigningExchange { _ in destination }
        let exported = try LeonardoSigningExchange.decoded(Data(contentsOf: destination))
        XCTAssertEqual(exported.documentID, "export-permissions")
        XCTAssertNil(session.guidedSigningActionProblem)
    }

    func testSignedCopyImportRequiresSavedSourceAndKeepsDirtyDraftUnsealed() async throws {
        let credentials = LeonardoSigningCredentialStore(
            service: "eu.pinedatec.LeonardoMD.tests.signing.import.\(UUID())"
        )
        let (root, session) = try fixture(signingCredentialStore: credentials)
        defer { session.stop(); try? FileManager.default.removeItem(at: root) }
        let documentURL = root.appendingPathComponent("import.mdlf")
        let exchangeURL = root.appendingPathComponent("signed-copy.json")
        let document = LeonardoDocument(
            body: "Answer: {{field:answer}} · Signature: {{field:signature}}",
            metadata: LeonardoMetadata(
                formatVersion: LeonardoFormat.signingVersion,
                document: .init(id: "saved-copy-import", kind: .form, revision: 1,
                    signing: .init(positions: [.init(id: "owner", label: "Owner")])),
                fields: ["answer": .init(type: .text, required: true),
                         "signature": .init(type: .rubric, signerPosition: "owner")],
                values: ["answer": .string("Original")]
            )
        )
        let original = try LeonardoFormatParser.serialize(document)
        try original.write(to: documentURL, atomically: true, encoding: .utf8)
        session.authorizePath = { _, _ in }
        await session.openDocument(documentURL)

        let initialSession = try XCTUnwrap(session.guidedSigningSession)
        let olderCopy = try LeonardoSigningExchange(document: document, session: initialSession,
                                                    trustedCredentials: [], at: Date())
        try LeonardoSigningExchange.encoded(olderCopy).write(to: exchangeURL)

        let key = LeonardoSigningKeyPair(credentialID: "exchange-owner")
        let profile = LeonardoSignerProfile(displayName: "Owner", identity: .init(
            fullName: "Owner", documentType: .nationalID, documentNumber: "QA-517"))
        await session.assignGuidedSigner(positionID: "owner", profile: profile, credential: key.credential,
                                        saveOptions: .init(saveIdentityDetails: false, saveRubric: false))
        let baseline = try XCTUnwrap(session.guidedSigningSession)
        await session.readGuidedSigningExchange(from: exchangeURL)
        XCTAssertEqual(session.guidedSigningActionProblem,
                       L10n.text("This signing copy does not match the progress saved on this Mac. Use a current copy."))
        XCTAssertFalse(session.guidedSigningContentLocked)
        XCTAssertEqual(session.guidedSigningSession, baseline)
        let afterOlderImport = try await session.guidedSigningStore.session(id: baseline.id)
        XCTAssertEqual(afterOlderImport, baseline)

        let draft = try XCTUnwrap(document.applyingFormValues(["answer": .string("Updated")]))
        let draftSource = try LeonardoFormatParser.serialize(draft)
        var detached = baseline
        _ = try detached.begin(positionID: "owner", document: draft)
        try detached.confirmLocation(positionID: "owner", fieldID: "signature", occurrence: 0,
            document: draft, contextRead: true, rubric: LeonardoRubric(strokes: [
                .init(color: "#112233", width: 2, style: .solid,
                      points: [.init(x: 1, y: 1), .init(x: 2, y: 2)])
            ]), at: Date())
        let trust = try LeonardoSigningTrustRegistry(credentials: [key.credential])
        _ = try detached.sign(positionID: "owner", keyPair: key, document: draft, trustStore: trust, at: Date())
        let exchange = try LeonardoSigningExchange(
            document: draft, session: detached, trustedCredentials: [key.credential], at: Date())
        try LeonardoSigningExchange.encoded(exchange).write(to: exchangeURL)

        session.content = draftSource
        await session.readGuidedSigningExchange(from: exchangeURL)
        XCTAssertEqual(session.guidedSigningActionProblem, L10n.text("Save the document before exchanging a signing copy."))
        XCTAssertNil(session.guidedSigningSession?.snapshot)
        let beforeSave = try await session.guidedSigningStore.session(id: baseline.id)
        XCTAssertEqual(beforeSave, baseline)
        let acceptedBeforeSave = try await credentials.trustedPublicCredentials()
        XCTAssertTrue(acceptedBeforeSave.isEmpty)

        session.authorizePath = { _, _ in throw SyncError.outsideScope }
        await session.save()
        await session.readGuidedSigningExchange(from: exchangeURL)
        XCTAssertEqual(session.guidedSigningSession, baseline)
        session.unsavedChangesDecision = { _ in .discard }
        let discarded = await session.resolveUnsavedChanges()
        XCTAssertTrue(discarded)
        XCTAssertEqual(session.content, original)

        session.authorizePath = { _, _ in }
        session.content = draftSource
        await session.save()
        XCTAssertFalse(session.isDirty)
        try original.write(to: documentURL, atomically: true, encoding: .utf8)
        await session.readGuidedSigningExchange(from: exchangeURL)
        XCTAssertTrue(session.externalConflict)
        XCTAssertEqual(session.guidedSigningSession, baseline)
        let acceptedAfterExternalChange = try await credentials.trustedPublicCredentials()
        XCTAssertTrue(acceptedAfterExternalChange.isEmpty)

        try draftSource.write(to: documentURL, atomically: true, encoding: .utf8)
        await session.reloadFromDisk()
        XCTAssertFalse(session.externalConflict)
        try await credentials.trustPublicCredential(key.credential)
        await session.readGuidedSigningExchange(from: exchangeURL)
        XCTAssertEqual(session.guidedSigningVerification["owner"], .valid)
        let afterImport = try await session.guidedSigningStore.session(id: baseline.id)
        XCTAssertTrue(afterImport?.isComplete == true)

        var changed = try LeonardoFormatParser.parse(draftSource)
        changed.body += "\nExternal edit after signing"
        try LeonardoFormatParser.serialize(changed).write(to: documentURL, atomically: true, encoding: .utf8)
        let reopened = AppSession(preferencesURL: session.globalPreferencesURL, signingCredentialStore: credentials)
        defer { reopened.stop() }
        reopened.authorizePath = { _, _ in }
        await reopened.openDocument(documentURL)

        XCTAssertTrue(reopened.guidedSigningSnapshotChanged)
        XCTAssertTrue(reopened.guidedSigningContentLocked)
        XCTAssertFalse(reopened.guidedSigningWorkflowOperable)
        XCTAssertTrue(reopened.guidedSigningCanStartRevision)
        XCTAssertTrue(reopened.guidedSigningVerification.isEmpty)
        try await credentials.removeTrustedPublicCredential(id: key.credential.id)
    }

    func testColdReopenWithAmbiguousSigningHistoryShowsRestorationOnly() async throws {
        let credentials = LeonardoSigningCredentialStore(
            service: "eu.pinedatec.LeonardoMD.tests.signing.ambiguous.\(UUID())"
        )
        let (root, first) = try fixture(signingCredentialStore: credentials)
        defer { first.stop(); try? FileManager.default.removeItem(at: root) }
        let documentURL = root.appendingPathComponent("ambiguous.mdlf")
        let declaration = LeonardoSigningDeclaration(positions: [
            LeonardoSignerPosition(id: "owner", label: "Owner")
        ])
        let document = LeonardoDocument(
            body: "Signature: {{field:signature}}",
            metadata: LeonardoMetadata(
                formatVersion: LeonardoFormat.signingVersion,
                document: LeonardoDocumentDescriptor(
                    id: "ambiguous", title: "Ambiguous", kind: .form,
                    revision: 1, signing: declaration
                ),
                fields: [
                    "signature": LeonardoFieldDefinition(type: .rubric, signerPosition: "owner")
                ]
            )
        )
        var nextRevision = document
        nextRevision.metadata.document.revision = 2
        let legacy = LeonardoDocument(
            body: "Name: {{field:name}}",
            metadata: LeonardoMetadata(
                document: LeonardoDocumentDescriptor(id: "ambiguous", title: "Ambiguous", kind: .form),
                fields: ["name": LeonardoFieldDefinition(type: .text)]
            )
        )
        try LeonardoFormatParser.serialize(legacy).write(to: documentURL, atomically: true, encoding: .utf8)
        first.authorizePath = { _, _ in }
        var firstHistory = try LeonardoGuidedSigningSession(
            document: document, at: Date(), documentLocation: documentURL.path
        )
        firstHistory.snapshot = try LeonardoSigningSnapshot.capture(document: document, at: Date())
        var secondHistory = try LeonardoGuidedSigningSession(
            document: nextRevision, at: Date(), documentLocation: documentURL.path
        )
        secondHistory.snapshot = try LeonardoSigningSnapshot.capture(document: nextRevision, at: Date())
        try await first.guidedSigningStore.saveSession(firstHistory)
        try await first.guidedSigningStore.saveSession(secondHistory)

        let reopened = AppSession(
            preferencesURL: first.globalPreferencesURL,
            signingCredentialStore: credentials
        )
        defer { reopened.stop() }
        reopened.authorizePath = { _, _ in }
        await reopened.openDocument(documentURL)

        XCTAssertTrue(reopened.isGuidedSigningDocument)
        XCTAssertTrue(reopened.guidedSigningRecoveryBlocked)
        XCTAssertNil(reopened.guidedSigningSession)
        XCTAssertNotNil(reopened.guidedSigningError)
        XCTAssertFalse(reopened.guidedSigningCanStartRevision)
        XCTAssertTrue(reopened.guidedSigningContentLocked)
        XCTAssertTrue(reopened.guidedSigningVerification.isEmpty)
        XCTAssertTrue(reopened.guidedSigningTargets.isEmpty)
    }

    func testSealedExternalChangeKeepsOrdinaryEditsLockedButAllowsExplicitCorrection() async throws {
        let credentials = LeonardoSigningCredentialStore(
            service: "eu.pinedatec.LeonardoMD.tests.signing.external-correction.\(UUID())"
        )
        let (root, session) = try fixture(signingCredentialStore: credentials)
        defer { session.stop(); try? FileManager.default.removeItem(at: root) }
        let documentURL = root.appendingPathComponent("external-correction.mdlf")
        let declaration = LeonardoSigningDeclaration(positions: [
            LeonardoSignerPosition(id: "owner", label: "Owner")
        ])
        let document = LeonardoDocument(
            body: "Signature: {{field:signature}}",
            metadata: LeonardoMetadata(
                formatVersion: LeonardoFormat.signingVersion,
                document: LeonardoDocumentDescriptor(
                    id: "external-correction", title: "External correction", kind: .form,
                    revision: 1, signing: declaration
                ),
                fields: [
                    "signature": LeonardoFieldDefinition(type: .rubric, signerPosition: "owner")
                ]
            )
        )
        try LeonardoFormatParser.serialize(document).write(to: documentURL, atomically: true, encoding: .utf8)
        session.authorizePath = { _, _ in }
        await session.openDocument(documentURL)
        session.isProtected = false

        let key = LeonardoSigningKeyPair(credentialID: "external-owner")
        let profile = LeonardoSignerProfile(
            displayName: "Owner",
            identity: LeonardoDeclaredIdentity(
                fullName: "Owner", documentType: .nationalID, documentNumber: "EXT-1"
            )
        )
        await session.assignGuidedSigner(
            positionID: "owner", profile: profile, credential: key.credential,
            saveOptions: LeonardoProfileSaveOptions(saveIdentityDetails: false, saveRubric: false)
        )
        await session.beginGuidedPosition("owner")
        let target = try XCTUnwrap(session.guidedSigningTargets.first)
        let rubric = LeonardoRubric(strokes: [LeonardoInkStroke(
            color: "#111111", width: 2, style: .solid,
            points: [LeonardoInkPoint(x: 1, y: 1), LeonardoInkPoint(x: 2, y: 2)]
        )])
        await session.confirmGuidedLocation(
            target: target, rubric: rubric, reuse: .new, reuseConfirmed: false,
            contextRead: true, renderedPlanMatches: { _, _ in true }
        )
        XCTAssertNotNil(session.guidedSigningSession?.snapshot)
        let sealedContent = session.content

        var externallyChanged = document
        externallyChanged.body += "\nExternal edit"
        try LeonardoFormatParser.serialize(externallyChanged).write(
            to: documentURL, atomically: true, encoding: .utf8
        )
        await session.reloadFromDisk()

        XCTAssertEqual(session.content, sealedContent)
        XCTAssertTrue(session.externalConflict)
        XCTAssertTrue(session.guidedSigningSnapshotChanged)
        XCTAssertTrue(session.guidedSigningContentLocked)
        XCTAssertFalse(session.editDocument(expected: sealedContent, replacement: "ordinary edit"))

        await session.startGuidedSigningRevision()
        XCTAssertEqual(session.guidedSigningSession?.initialRevision, 2)
        XCTAssertFalse(session.guidedSigningSnapshotChanged)
        XCTAssertNil(session.guidedSigningError)
        XCTAssertFalse(session.guidedSigningContentLocked)
        XCTAssertEqual(try LeonardoFormatParser.parse(session.content).metadata.document.revision, 2)
        XCTAssertFalse(session.canUndoDocument)

        // The corrected buffer is still a conflict draft. It can be edited,
        // but no review/signing transition may commit progress to its old
        // path until Save Copy adopts a coordinated destination.
        let correctedSession = try XCTUnwrap(session.guidedSigningSession)
        await session.beginGuidedPosition("owner")
        XCTAssertEqual(session.guidedSigningSession, correctedSession)
        XCTAssertNotNil(session.guidedSigningActionProblem)

        let copyURL = root.appendingPathComponent("external-correction-copy.mdlf")
        await session.saveCopyAndOpen(to: copyURL, sourceURL: documentURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: copyURL.path))
        XCTAssertFalse(session.externalConflict)
        session.isProtected = false
        await session.prepareGuidedSigningIfNeeded()
        await session.assignGuidedSigner(
            positionID: "owner", profile: profile, credential: key.credential,
            saveOptions: LeonardoProfileSaveOptions(saveIdentityDetails: false, saveRubric: false)
        )
        await session.beginGuidedPosition("owner")
        XCTAssertEqual(session.guidedSigningSession?.positions["owner"]?.state, .reviewing)
    }

    func testGuidedAssignmentRejectsStoreChangeAfterPreparationBaseline() async throws {
        let credentials = LeonardoSigningCredentialStore(
            service: "eu.pinedatec.LeonardoMD.tests.signing.baseline.\(UUID())"
        )
        let (root, session) = try fixture(signingCredentialStore: credentials)
        defer { session.stop(); try? FileManager.default.removeItem(at: root) }
        let documentURL = root.appendingPathComponent("baseline-bound.mdlf")
        let declaration = LeonardoSigningDeclaration(positions: [
            LeonardoSignerPosition(id: "owner", label: "Owner")
        ])
        let document = LeonardoDocument(
            body: "Signature: {{field:signature}}",
            metadata: LeonardoMetadata(
                formatVersion: LeonardoFormat.signingVersion,
                document: LeonardoDocumentDescriptor(
                    id: "baseline-bound", title: "Baseline bound", kind: .form,
                    revision: 1, signing: declaration
                ),
                fields: [
                    "signature": LeonardoFieldDefinition(type: .rubric, signerPosition: "owner")
                ]
            )
        )
        try LeonardoFormatParser.serialize(document).write(
            to: documentURL, atomically: true, encoding: .utf8
        )
        session.authorizePath = { _, _ in }
        await session.openDocument(documentURL)
        let baseline = try XCTUnwrap(session.guidedSigningSession)
        var newer = baseline
        newer.updatedAt = baseline.updatedAt.addingTimeInterval(1)
        try await session.guidedSigningStore.saveSession(newer, replacing: baseline)

        let profile = LeonardoSignerProfile(
            displayName: "Ana",
            identity: LeonardoDeclaredIdentity(
                fullName: "Ana Example", documentType: .nationalID, documentNumber: "BASE-1"
            )
        )
        let credential = LeonardoSigningKeyPair(credentialID: "baseline-credential").credential
        await session.assignGuidedSigner(
            positionID: "owner",
            profile: profile,
            credential: credential,
            saveOptions: .init(saveIdentityDetails: false, saveRubric: false)
        )

        XCTAssertEqual(session.guidedSigningSession, baseline)
        XCTAssertNotNil(session.guidedSigningError)
        let stored = try await session.guidedSigningStore.session(id: baseline.id)
        XCTAssertEqual(stored, newer)
    }

    func testMacGuidedReviewDisablesLiveImagesAndExplainsHowToContinue() async throws {
        let credentials = LeonardoSigningCredentialStore(service: "eu.pinedatec.LeonardoMD.tests.signing.images.\(UUID())")
        let (root, session) = try fixture(signingCredentialStore: credentials)
        defer { session.stop(); try? FileManager.default.removeItem(at: root) }
        session.authorizePath = { _, _ in }
        let ordinary = root.appendingPathComponent("ordinary.md")
        let image = "![Online](https://example.invalid/image.png)"
        try image.write(to: ordinary, atomically: true, encoding: .utf8)
        await session.openDocument(ordinary)
        XCTAssertTrue(session.renderConfiguration.allowsRemoteImages)

        let signer = LeonardoSignerProfile(displayName: "Ana", identity: .init(
            fullName: "Ana Example", documentType: .nationalID, documentNumber: "QA-IMAGES"
        ))
        let credential = LeonardoSigningKeyPair(credentialID: "qa-images").credential
        let invalidImages = [
            (image, "Replace online images with local files before signing."),
            ("![Missing](missing.png)",
             "Use readable local images within the document or its project and within the signing size limits.")
        ]
        for (index, (reference, warning)) in invalidImages.enumerated() {
            let id = "guided-images-\(index)"
            let file = root.appendingPathComponent("\(id).mdlf")
            var document = LeonardoDocument(
                body: reference + "\n\n{{field:signature}}",
                metadata: LeonardoMetadata(
                    formatVersion: LeonardoFormat.signingVersion,
                    document: .init(id: id, title: "Signing example", kind: .form,
                                    revision: 1, signing: .init(positions: [.init(id: "owner", label: "Owner")])),
                    fields: ["signature": .init(type: .rubric, signerPosition: "owner")]
                )
            )
            try LeonardoFormatParser.serialize(document).write(to: file, atomically: true, encoding: .utf8)
            await session.openDocument(file)
            XCTAssertFalse(session.renderConfiguration.allowsRemoteImages)
            XCTAssertFalse(session.guidedSigningContentLocked, session.guidedSigningError ?? "Signing preparation is incomplete")
            XCTAssertEqual(session.guidedSigningActionProblem, L10n.text(warning))
            await session.exportGuidedSigningExchange()
            XCTAssertEqual(session.guidedSigningActionProblem, L10n.text(warning))
            XCTAssertFalse(session.guidedSigningContentLocked)

            let invalidCopy = root.appendingPathComponent("invalid-signing-copy.json")
            try "{".write(to: invalidCopy, atomically: true, encoding: .utf8)
            await session.readGuidedSigningExchange(from: invalidCopy)
            XCTAssertEqual(session.guidedSigningActionProblem, L10n.text("Choose a readable, valid signing copy and try again."))
            XCTAssertFalse(session.guidedSigningContentLocked)

            await session.assignGuidedSigner(
                positionID: "owner", profile: signer, credential: credential,
                saveOptions: .init(saveIdentityDetails: false, saveRubric: false)
            )
            await session.beginGuidedPosition("owner")
            XCTAssertNil(session.guidedSigningSession?.snapshot)
            XCTAssertEqual(session.guidedSigningActionProblem, L10n.text(warning))
            XCTAssertFalse(session.guidedSigningContentLocked)

            session.isProtected = false
            document.body = "{{field:signature}}"
            let corrected = try LeonardoFormatParser.serialize(document)
            XCTAssertTrue(session.editDocument(expected: session.content, replacement: corrected))
            await session.save()
            XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), corrected)
            await session.beginGuidedPosition("owner")
            XCTAssertNil(session.guidedSigningActionProblem)
            XCTAssertEqual(session.guidedSigningSession?.positions["owner"]?.state, .reviewing)
            await session.pauseGuidedPosition(positionID: "owner")
            XCTAssertEqual(session.guidedSigningSession?.positions["owner"]?.state, .paused)
            document.body = reference + "\n\n{{field:signature}}"
            XCTAssertTrue(session.editDocument(expected: session.content,
                                               replacement: try LeonardoFormatParser.serialize(document)))
            await session.resumeGuidedPosition(positionID: "owner")
            XCTAssertEqual(session.guidedSigningActionProblem, L10n.text(warning))
            XCTAssertFalse(session.guidedSigningContentLocked)
            XCTAssertTrue(session.editDocument(expected: session.content, replacement: corrected))
            await session.save()
            await session.resumeGuidedPosition(positionID: "owner")
            XCTAssertNil(session.guidedSigningActionProblem)

            let target = try XCTUnwrap(session.guidedSigningTargets.first)
            await session.confirmGuidedLocation(
                target: target,
                rubric: LeonardoRubric(strokes: [LeonardoInkStroke(
                    color: "#111111", width: 2, style: .solid,
                    points: [LeonardoInkPoint(x: 1, y: 1), LeonardoInkPoint(x: 2, y: 2)]
                )]),
                reuse: .new, reuseConfirmed: false, contextRead: true,
                renderedPlanMatches: { _, _ in true }
            )
            XCTAssertNotNil(session.guidedSigningSession?.snapshot)
            XCTAssertTrue(session.guidedSigningContentLocked)
        }
    }

    func testExternalSigningResourceChangeInvalidatesOpenVerification() async throws {
        let credentials = LeonardoSigningCredentialStore(
            service: "eu.pinedatec.LeonardoMD.tests.signing.resource-change.\(UUID())"
        )
        let (root, session) = try fixture(signingCredentialStore: credentials)
        defer { session.stop(); try? FileManager.default.removeItem(at: root) }
        session.authorizePath = { _, _ in }
        let file = root.appendingPathComponent("sealed.mdlf")
        let image = root.appendingPathComponent("sealed.png")
        let declaration = LeonardoSigningDeclaration(positions: [.init(id: "owner", label: "Owner")])
        let document = LeonardoDocument(
            body: "![Sealed image](sealed.png)\n\n{{field:signature}}",
            metadata: LeonardoMetadata(
                formatVersion: LeonardoFormat.signingVersion,
                document: .init(id: "sealed-image", kind: .form, revision: 1, signing: declaration),
                fields: ["signature": .init(type: .rubric, signerPosition: "owner")]
            )
        )
        let imageBytes = Data([1, 2, 3])
        try imageBytes.write(to: image)
        try LeonardoFormatParser.serialize(document).write(to: file, atomically: true, encoding: .utf8)
        let resources = [LeonardoSigningResource(reference: "sealed.png", bytes: imageBytes)]
        let key = LeonardoSigningKeyPair(credentialID: "sealed-resource-owner")
        let profile = LeonardoSignerProfile(displayName: "Owner", identity: .init(
            fullName: "Owner", documentType: .nationalID, documentNumber: "QA-RESOURCE"))
        let authorization = try LeonardoSigningAuthorization(positionID: "owner", profileID: profile.id,
            credentialID: key.credential.id, confirmedAt: Date(), explicitlyConfirmed: true)
        var sealed = try LeonardoGuidedSigningSession(
            document: document, at: Date(), documentLocation: file.standardizedFileURL.resolvingSymlinksInPath().path
        )
        try sealed.assign(positionID: "owner", profile: profile, credential: key.credential,
                          authorization: authorization, at: Date())
        _ = try sealed.begin(positionID: "owner", document: document, resources: resources)
        try sealed.confirmLocation(positionID: "owner", fieldID: "signature", occurrence: 0,
            document: document, resources: resources, contextRead: true,
            rubric: LeonardoRubric(strokes: [.init(color: "#111111", width: 2, style: .solid,
                points: [.init(x: 1, y: 1), .init(x: 2, y: 2)])]), at: Date())
        try await credentials.trustPublicCredential(key.credential)
        let trust = try await credentials.trustStore()
        _ = try sealed.sign(positionID: "owner", keyPair: key, document: document,
                            resources: resources, trustStore: trust, at: Date())
        try await session.guidedSigningStore.saveSession(sealed, replacing: nil)
        await session.openDocument(file)
        XCTAssertEqual(session.guidedSigningVerification["owner"], .valid)
        session.guidedSigningStatus = L10n.text("All signer positions are signed and verified locally.")

        try Data([1, 2, 4]).write(to: image)
        await session.checkExternalChanges()
        XCTAssertTrue(session.guidedSigningSnapshotChanged)
        XCTAssertTrue(session.guidedSigningVerification.isEmpty)
        XCTAssertNil(session.guidedSigningStatus)
        XCTAssertTrue(session.guidedSigningContentLocked)
        XCTAssertEqual(session.guidedSigningSession, sealed)

        try imageBytes.write(to: image)
        await session.openDocument(file)
        XCTAssertEqual(session.guidedSigningVerification["owner"], .valid)
        let destination = root.appendingPathComponent("stale-export.json")
        var destinationRequested = false
        await session.exportGuidedSigningExchange { _ in
            destinationRequested = true
            do {
                try Data([1, 2, 4]).write(to: image)
            } catch {
                XCTFail("Could not change the image while the destination was being selected: \(error)")
            }
            return destination
        }
        XCTAssertTrue(destinationRequested)
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
        XCTAssertTrue(session.guidedSigningSnapshotChanged)
        XCTAssertTrue(session.guidedSigningVerification.isEmpty)
        XCTAssertEqual(session.guidedSigningSession, sealed)
    }

    func testGuidedReviewClearsWarningAfterRequiredDataIsCorrected() async throws {
        let credentials = LeonardoSigningCredentialStore(service: "eu.pinedatec.LeonardoMD.tests.signing.required.\(UUID())")
        let (root, session) = try fixture(signingCredentialStore: credentials)
        defer { session.stop(); try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("required-guided.mdlf")
        let declaration = LeonardoSigningDeclaration(positions: [.init(id: "owner", label: "Owner")])
        var document = LeonardoDocument(
            body: "Amount: {{field:amount}}. Signature: {{field:signature}}",
            metadata: LeonardoMetadata(
                formatVersion: LeonardoFormat.signingVersion,
                document: .init(id: "required-guided", title: "Required guided form", kind: .form,
                                revision: 1, signing: declaration),
                fields: [
                    "amount": .init(type: .number, label: "Amount", required: true, minimum: 10),
                    "signature": .init(type: .rubric, signerPosition: "owner")
                ],
                values: ["amount": .number(2)]
            )
        )
        try LeonardoFormatParser.serialize(document).write(to: file, atomically: true, encoding: .utf8)
        session.authorizePath = { _, _ in }
        await session.openDocument(file)
        let profile = LeonardoSignerProfile(displayName: "Ana", identity: .init(
            fullName: "Ana Example", documentType: .nationalID, documentNumber: "QA-REQUIRED"))
        let credential = LeonardoSigningKeyPair(credentialID: "required-field-credential").credential
        await session.assignGuidedSigner(positionID: "owner", profile: profile, credential: credential,
                                         saveOptions: .init(saveIdentityDetails: false, saveRubric: false))

        await session.beginGuidedPosition("owner")
        XCTAssertNotNil(session.guidedSigningActionProblem)
        XCTAssertNil(session.guidedSigningSession?.snapshot)
        session.isProtected = false
        document.metadata.values["amount"] = .number(12)
        let corrected = try LeonardoFormatParser.serialize(document)
        XCTAssertTrue(session.editDocument(expected: session.content, replacement: corrected))

        await session.beginGuidedPosition("owner")
        XCTAssertNil(session.guidedSigningActionProblem)
        XCTAssertEqual(session.guidedSigningSession?.positions["owner"]?.state, .reviewing)
    }

    func testCheckboxAppearancesPreserveFillGuardsAndManualSaving() async throws {
        let (root, session) = try fixture()
        defer { session.stop(); try? FileManager.default.removeItem(at: root) }
        for appearance: LeonardoFieldAppearance? in [nil, .checkbox, .switch] {
            let response = root.appendingPathComponent("controls.mdlr")
            let document = LeonardoDocument(body: "{{field:enabled}}", metadata: LeonardoMetadata(
                document: LeonardoDocumentDescriptor(kind: .form),
                fields: [
                    "enabled": LeonardoFieldDefinition(type: .checkbox, appearance: appearance),
                    "locked": LeonardoFieldDefinition(type: .checkbox, appearance: appearance, readOnly: true)
                ], values: ["enabled": .boolean(false), "locked": .boolean(false)]))
            let original = try LeonardoFormatParser.serialize(document)
            try original.write(to: response, atomically: true, encoding: .utf8)
            await session.open(response)
            XCTAssertEqual(session.mode, .fill)
            XCTAssertTrue(session.updateLeonardoCheckbox("enabled", value: true))
            XCTAssertFalse(session.updateLeonardoCheckbox("locked", value: true))
            XCTAssertTrue(session.leonardoFieldBool("enabled"))
            XCTAssertTrue(session.isDirty)
            XCTAssertEqual(try String(contentsOf: response, encoding: .utf8), original)
            await session.save()
            let saved = try LeonardoFormatParser.parse(String(contentsOf: response, encoding: .utf8))
            XCTAssertEqual(saved.metadata.fields["enabled"]?.appearance, appearance)
            XCTAssertEqual(saved.metadata.values["enabled"], .boolean(true))
            await session.setDocumentMode(.preview)
            XCTAssertFalse(session.updateLeonardoCheckbox("enabled", value: false))
        }
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

}
