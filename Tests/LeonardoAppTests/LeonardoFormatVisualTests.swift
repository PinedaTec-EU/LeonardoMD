#if os(macOS)
import AppKit
import SwiftUI
import XCTest
import LeonardoCore
@testable import LeonardoApp

/// Optional native evidence for the Leonardo document chrome. The fixture uses
/// the real WorkspaceView and transport so the format and storage indicators
/// are exercised together with the native form panel.
@MainActor
final class LeonardoFormatVisualTests: XCTestCase {
    func testCaptureLeonardoChromeFillPackageAndExtractedStates() async throws {
        guard let evidencePath = ProcessInfo.processInfo.environment["LEONARDO_VISUAL_EVIDENCE"] else {
            throw XCTSkip("Set LEONARDO_VISUAL_EVIDENCE to export Leonardo native captures")
        }
        let destination = URL(fileURLWithPath: evidencePath, isDirectory: true)
            .appendingPathComponent("leonardo-format", isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)

        let fixture = FileManager.default.temporaryDirectory.appendingPathComponent("LeonardoFormatVisual-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: fixture, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: fixture) }

        let templateURL = fixture.appendingPathComponent("request.mdlf")
        let packageURL = fixture.appendingPathComponent("request.mdlz")
        let document = LeonardoDocument(
            body: "# Request\n\nName: {{field:name}}\n\n{{field:details}}",
            metadata: LeonardoMetadata(
                document: LeonardoDocumentDescriptor(title: "Request", kind: .form),
                fields: [
                    "name": LeonardoFieldDefinition(label: "Name", required: true, placeholder: "Your name"),
                    "details": LeonardoFieldDefinition(type: .multiline, label: "Details", helpText: "Add context for the owner.")
                ]
            )
        )
        let source = try LeonardoFormatParser.serialize(document)
        try source.write(to: templateURL, atomically: true, encoding: .utf8)
        try LeonardoPackageTransport.export(documentURL: templateURL, content: source, to: packageURL)

        let tabs = DocumentTabs(preferencesURL: fixture.appendingPathComponent("preferences.json"))
        defer { tabs.stop() }
        let session = tabs.activeSession
        let previousLanguage = LanguageSettings.shared.language
        let preferenceKey = LeonardoPackageOpenPreference.defaultsKey
        let previousPackagePreference = UserDefaults.standard.object(forKey: preferenceKey)
        let previousMigration = session.migrateMarkdownOnSave
        defer {
            LanguageSettings.shared.language = previousLanguage
            session.migrateMarkdownOnSave = previousMigration
            if let previousPackagePreference {
                UserDefaults.standard.set(previousPackagePreference, forKey: preferenceKey)
            } else {
                UserDefaults.standard.removeObject(forKey: preferenceKey)
            }
        }

        for language in AppLanguage.allCases {
            LanguageSettings.shared.language = language
            let preferences = NSHostingView(rootView: PreferencesView(session: session)
                .modifier(SessionAppearance(session: session)))
            for (choice, migration) in [(LeonardoPackageOpenPreference.package, false), (.ask, true), (.extracted, false)] {
                session.packageOpenPreference = choice
                session.migrateMarkdownOnSave = migration
                try await NativeViewCaptureSupport.capture(preferences,
                    size: NSSize(width: 580, height: 620),
                    to: destination.appendingPathComponent("format-preferences-\(language.rawValue)-\(choice.rawValue)-migration-\(migration).png"),
                    title: "Leonardo Format Preferences QA")
            }

            await session.openDocument(templateURL)
            await session.setDocumentMode(.fill)
            session.showInspector = true
            try await capture(session: session, state: "mdlf-fill", language: language, destination: destination)

            session.packageOpenPreference = .package
            await session.open(packageURL)
            await session.setDocumentMode(.fill)
            session.showInspector = true
            try await capture(session: session, state: "mdlz-package-fill", language: language, destination: destination)

            session.discardPackageWorkspace()
            let extractionParent = fixture.appendingPathComponent("extracted", isDirectory: true)
            try FileManager.default.createDirectory(at: extractionParent, withIntermediateDirectories: true)
            let extractionURL = extractionParent.appendingPathComponent(language.rawValue, isDirectory: true)
            let workspace = try LeonardoPackageTransport.open(packageURL, extractingTo: extractionURL)
            let loaded = try await session.documents.read(workspace.documentURL)
            session.packageWorkspace = workspace
            session.documentURL = workspace.documentURL
            session.documentSourceURL = packageURL
            session.documentKind = .leonardoTemplate
            session.documentStorage = .extracted
            session.leonardoFormatWarning = false
            session.snapshot = loaded
            session.content = loaded.content
            session.isProtected = true
            session.saveStatus = "Saved · extracted folder"
            session.mode = .fill
            session.showInspector = true
            session.updateTitle()
            try await capture(session: session, state: "mdlz-extracted-fill", language: language, destination: destination)
        }

        try "Surface: WorkspaceView with the native Leonardo form inspector\nStates: local MDLF, MDLZ package workspace, explicitly extracted MDLZ workspace; General preferences with all three package choices and migration off/on/off on the same hosting view at 580x620\nView size: 1260x850 points\nLanguages: en, es\nFixture: synthetic form with text and multiline fields; package transport creates the MDLZ\nLimit: opt-in NSHostingView bitmap evidence, no claim about a fresh packaged process\n".write(
            to: destination.appendingPathComponent("capture-context.txt"), atomically: true, encoding: .utf8)
    }

    private func capture(
        session: AppSession,
        state: String,
        language: AppLanguage,
        destination: URL
    ) async throws {
        let host = NSHostingView(
            rootView: WorkspaceView(session: session)
                .modifier(SessionAppearance(session: session))
                .background(Color(nsColor: .windowBackgroundColor))
        )
        try await NativeViewCaptureSupport.capture(
            host,
            size: NSSize(width: 1260, height: 850),
            to: destination.appendingPathComponent("\(state)-\(language.rawValue).png"),
            settlingMilliseconds: 600,
            title: "Leonardo Format QA"
        )
    }
}
#endif
