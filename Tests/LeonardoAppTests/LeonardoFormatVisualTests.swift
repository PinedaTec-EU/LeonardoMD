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
    func testCaptureBooleanFieldAppearances() async throws {
        guard let evidencePath = ProcessInfo.processInfo.environment["LEONARDO_VISUAL_EVIDENCE"] else {
            throw XCTSkip("Set LEONARDO_VISUAL_EVIDENCE to export boolean field captures")
        }
        let destination = URL(fileURLWithPath: evidencePath, isDirectory: true)
            .appendingPathComponent("form-appearance", isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let fixture = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: fixture, withIntermediateDirectories: true)
        let session = AppSession(preferencesURL: fixture.appendingPathComponent("preferences.json"))
        defer { session.stop(); try? FileManager.default.removeItem(at: fixture) }
        let document = LeonardoDocument(body: "# Controls", metadata: LeonardoMetadata(
            document: LeonardoDocumentDescriptor(kind: .form), fields: [
                "a": LeonardoFieldDefinition(type: .checkbox, label: "Default checkbox"),
                "b": LeonardoFieldDefinition(type: .checkbox, appearance: .checkbox, label: "Explicit checkbox"),
                "c": LeonardoFieldDefinition(type: .checkbox, appearance: .switch, label: "Switch"),
                "d": LeonardoFieldDefinition(type: .checkbox, appearance: .switch, label: "Read-only switch", readOnly: true)
            ]))
        let url = fixture.appendingPathComponent("controls.mdlr")
        try LeonardoFormatParser.serialize(document).write(to: url, atomically: true, encoding: .utf8)
        await session.open(url)
        for on in [false, true] {
            await session.setDocumentMode(.fill)
            for field in ["a", "b", "c"] { XCTAssertTrue(session.updateLeonardoCheckbox(field, value: on)) }
            for mode: DocumentMode in [.fill, .preview] {
                await session.setDocumentMode(mode)
                for scheme: ColorScheme in [.light, .dark] {
                    let view = NSHostingView(rootView: DocumentInspector(session: session)
                        .preferredColorScheme(scheme))
                    let name = "controls-\(on ? "on" : "off")-\(mode == .fill ? "fill" : "preview")-\(scheme == .light ? "light" : "dark").png"
                    try await NativeViewCaptureSupport.capture(view, size: NSSize(width: 320, height: 500),
                        to: destination.appendingPathComponent(name), title: "Form Appearance QA")
                }
            }
        }
        let sha = ProcessInfo.processInfo.environment["EVIDENCE_SHA"] ?? "local-working-tree"
        try "Head: \(sha)\nSurface: native DocumentInspector, NSHostingView, 320x500 points\nStates: default checkbox, explicit checkbox, switch, read-only switch; on/off, fill/preview, light/dark\nFixture: synthetic boolean form; no fresh packaged startup claim\n".write(
            to: destination.appendingPathComponent("provenance.txt"), atomically: true, encoding: .utf8)
    }

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
        let responseURL = fixture.appendingPathComponent("request.mdlr")
        let document = LeonardoDocument(
            body: "# Request\n\nName: {{field:name}}\n\n{{field:details}}",
            metadata: LeonardoMetadata(
                document: LeonardoDocumentDescriptor(title: "Request", kind: .form),
                fields: [
                    "checkbox": LeonardoFieldDefinition(type: .checkbox, appearance: .checkbox, label: "Checkbox"),
                    "default": LeonardoFieldDefinition(type: .checkbox, label: "Default checkbox"),
                    "switch": LeonardoFieldDefinition(type: .checkbox, appearance: .switch, label: "Switch"),
                    "name": LeonardoFieldDefinition(label: "Name", required: true, placeholder: "Your name"),
                    "details": LeonardoFieldDefinition(type: .multiline, label: "Details", helpText: "Add context for the owner.")
                ],
                values: ["checkbox": .boolean(true), "default": .boolean(false), "switch": .boolean(true)]
            )
        )
        let source = try LeonardoFormatParser.serialize(document)
        try source.write(to: templateURL, atomically: true, encoding: .utf8)
        try source.write(to: responseURL, atomically: true, encoding: .utf8)
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
            XCTAssertEqual(session.mode, .preview)
            try await capture(session: session, state: "mdlf-initial-preview", language: language, destination: destination)
            await session.setDocumentMode(.fill)
            session.showInspector = true
            try await capture(session: session, state: "mdlf-fill", language: language, destination: destination)

            await session.openDocument(responseURL)
            XCTAssertEqual(session.mode, .fill)
            try await capture(session: session, state: "mdlr-initial-fill", language: language, destination: destination)

            session.packageOpenPreference = .package
            await session.open(packageURL)
            XCTAssertEqual(session.mode, .preview)
            try await capture(session: session, state: "mdlz-initial-preview", language: language, destination: destination)
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

        try "Surface: WorkspaceView with the native Leonardo form inspector\nStates: local MDLF initial preview/fill, MDLR initial fill, MDLZ initial preview, MDLZ package fill workspace, explicitly extracted MDLZ workspace; General preferences with all three package choices and migration off/on/off on the same hosting view at 580x620\nView size: 1260x850 points\nLanguages: en, es\nFixture: synthetic form with text, multiline, explicit/default checkbox and switch fields; package transport creates the MDLZ\nLimit: opt-in NSHostingView bitmap evidence, no claim about a fresh packaged process\n".write(
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
