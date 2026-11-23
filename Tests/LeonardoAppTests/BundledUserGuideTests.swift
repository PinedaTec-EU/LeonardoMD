import AppKit
import SwiftUI
import WebKit
import XCTest
import LeonardoCore
@testable import LeonardoApp

@MainActor
final class BundledUserGuideTests: XCTestCase {
    func testLocalizedResourcesOpenNativelyAndWorkingCopiesPreserveSavedAnswers() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let englishResource = try BundledUserGuide.resourceURL(language: .english)
        let revisionParts = englishResource.deletingPathExtension().lastPathComponent.split(separator: "-")
        XCTAssertEqual(revisionParts.count, 3)
        let currentRevision = try XCTUnwrap(Int(revisionParts[1].dropFirst()))
        let oldCopies = (2..<currentRevision).flatMap { revision in
            AppLanguage.allCases.map { language in
                root.appendingPathComponent("User Guides/v\(revision)/\(language.rawValue)/Guide-v\(revision)-\(language.rawValue).mdlz")
            }
        }
        let oldAnswers = Data("previous guide and saved answers".utf8)
        for oldCopy in oldCopies {
            try FileManager.default.createDirectory(at: oldCopy.deletingLastPathComponent(), withIntermediateDirectories: true)
            try oldAnswers.write(to: oldCopy)
        }
        defer { for oldCopy in oldCopies { XCTAssertEqual(try? Data(contentsOf: oldCopy), oldAnswers) } }
        for language in AppLanguage.allCases {
            let original = try BundledUserGuide.resourceURL(language: language)
            let originalBytes = try Data(contentsOf: original)
            let copy = try BundledUserGuide.workingCopy(language: language, supportDirectory: root)
            XCTAssertNotEqual(copy, original)
            XCTAssertTrue(copy.path.contains("User Guides/v\(currentRevision)/"))
            XCTAssertEqual(try Data(contentsOf: copy), originalBytes)
            let legacyImport = root.appendingPathComponent("Agent Import Guides/v2/\(language.rawValue)/AgentImport-v2-\(language.rawValue).mdlz")
            try FileManager.default.createDirectory(at: legacyImport.deletingLastPathComponent(), withIntermediateDirectories: true)
            try oldAnswers.write(to: legacyImport)
            let importCopy = try BundledUserGuide.workingCopy(language: language, supportDirectory: root, topic: .agentImport)
            XCTAssertTrue(importCopy.path.contains("Agent Import Guides/v3/"))
            XCTAssertEqual(try Data(contentsOf: legacyImport), oldAnswers)
            var workspace = try LeonardoPackageTransport.open(copy)
            defer { LeonardoPackageTransport.discard(workspace) }
            let source = try String(contentsOf: workspace.documentURL, encoding: .utf8)
            XCTAssertTrue(source.contains("[LL1 op=snapshot"), "The combined guide must retain the HTTPS diagnostic example")
            let mobileFormatGuidance = language == .english
                ? "Valid `.mdlf` and `.mdlr` files open in Little Leonardo's Leonardo-aware reader"
                : "Los archivos `.mdlf` y `.mdlr` válidos se abren en el lector compatible con Leonardo de Little Leonardo"
            let readOnlyGuidance = language == .english
                ? "Their saved text and form values are read-only"
                : "El texto y las respuestas guardadas son de solo lectura"
            XCTAssertTrue(source.contains(mobileFormatGuidance), "The guide must explain which Leonardo formats Little Leonardo reads")
            XCTAssertTrue(source.contains(readOnlyGuidance), "The guide must state that received mobile forms remain read-only")
            let accessDenialGuidance = language == .english
                ? "An explicit access denial does not open that stale version."
                : "Una denegación de acceso explícita no abre esa versión desactualizada."
            XCTAssertTrue(source.contains(accessDenialGuidance), "The guide must distinguish denials from temporary failures")
            XCTAssertTrue(source.contains("Demo-es.mdlr") && source.contains("Demo-en.mdlr"), "The combined guide must explain the demo project documents")
            XCTAssertTrue(source.contains("Recuperar demo / Restore demo"), "Both guides must explain demo recovery")
            let document = try LeonardoFormatParser.parse(source)
            XCTAssertFalse(document.isForm)
            XCTAssertEqual(document.metadata.fields.count, 0)
            let expectedImageCount = language == .spanish ? 23 : 22
            XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath:
                workspace.directoryURL.appendingPathComponent("assets").path).count, expectedImageCount)
            let artwork = language == .english ? ["journey", "package", "import", "export"] : ["recorrido", "paquete", "importar", "exportar"]
            for name in artwork {
                let imageURL = workspace.directoryURL.appendingPathComponent("assets/\(name).png")
                let bitmap = try XCTUnwrap(NSBitmapImageRep(data: Data(contentsOf: imageURL)))
                XCTAssertTrue(bitmap.hasAlpha, name)
                XCTAssertEqual(bitmap.pixelsWide, 1200)
                XCTAssertEqual(bitmap.pixelsHigh, 400)
                XCTAssertEqual(try XCTUnwrap(bitmap.colorAt(x: 0, y: 0)).alphaComponent, 0, name)
            }
            // Personal annotations remain independent of the bundled template.
            try (source + "\nPersonal note: Ada\n").write(to: workspace.documentURL, atomically: true, encoding: .utf8)
            workspace = try LeonardoPackageTransport.save(workspace)
            XCTAssertEqual(try BundledUserGuide.workingCopy(language: language, supportDirectory: root), copy)
            let reopened = try LeonardoPackageTransport.open(copy)
            defer { LeonardoPackageTransport.discard(reopened) }
            let saved = try String(contentsOf: reopened.documentURL, encoding: .utf8)
            XCTAssertTrue(saved.contains("Personal note: Ada"))
            XCTAssertEqual(try Data(contentsOf: original), originalBytes)
        }
    }

    func testGuidePackageOverrideDoesNotChangeOrdinaryOpeningPreference() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let tabs = DocumentTabs(preferencesURL: root.appendingPathComponent("preferences.json"))
        defer { tabs.stop() }
        let session = tabs.activeSession
        session.authorizePath = { _, _ in }
        let previous = session.packageOpenPreference
        defer { session.packageOpenPreference = previous }
        session.packageOpenPreference = .ask
        var requested: [LeonardoPackageOpenPreference] = []
        session.openPackageDocument = { _, preference in requested.append(preference); return false }
        let copy = try BundledUserGuide.workingCopy(language: .english, supportDirectory: root)
        await session.open(copy, packagePreference: .package)
        await session.open(copy)
        XCTAssertEqual(requested, [.package, .ask])
        XCTAssertEqual(session.packageOpenPreference, .ask)
    }

    func testHelpMenuExposesLocalizedGuideAction() {
        _ = NSApplication.shared
        let previousLanguage = LanguageSettings.shared.language
        let previousMenu = NSApp.mainMenu
        let previousHelp = NSApp.helpMenu
        defer {
            LanguageSettings.shared.language = previousLanguage
            NSApp.mainMenu = previousMenu
            NSApp.helpMenu = previousHelp
        }
        let delegate = ApplicationDelegate(diagnostics: StartupDiagnostics(),
            instance: SingleInstance(name: "GuideMenuTests"), role: .primary)
        for language in AppLanguage.allCases {
            LanguageSettings.shared.language = language
            delegate.configureMenu()
            XCTAssertEqual(NSApp.helpMenu?.title, language == .english ? "Help" : "Ayuda")
            XCTAssertEqual(NSApp.helpMenu?.items.first?.title,
                           language == .english ? "Leonardo user guide…" : "Guía de Leonardo…")
            XCTAssertEqual(NSApp.helpMenu?.items.first?.action, NSSelectorFromString("openUserGuide"))
            let file = NSApp.mainMenu?.items.compactMap(\.submenu).first {
                $0.title == (language == .english ? "File" : "Archivo")
            }
            let item = file?.items.first { $0.action == NSSelectorFromString("openAgentImportGuide") }
            XCTAssertEqual(item?.title, language == .english ? "Import with your agent…" : "Importar con tu agente…")
        }
    }

    func testNativeReadingGuideImagesAndActionRenderInBothLanguages() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let previousLanguage = LanguageSettings.shared.language
        defer {
            LanguageSettings.shared.language = previousLanguage
            try? FileManager.default.removeItem(at: root)
        }
        for language in AppLanguage.allCases {
            LanguageSettings.shared.language = language
            let tabs = DocumentTabs(preferencesURL: root.appendingPathComponent("preferences.json"))
            defer { tabs.stop() }
            let session = tabs.activeSession
            session.authorizePath = { _, _ in }
            let copy = try BundledUserGuide.workingCopy(language: language, supportDirectory: root)
            await session.open(copy, packagePreference: .package)
            XCTAssertEqual(session.documentStorage, .package)
            XCTAssertNil(session.errorMessage)
            session.setPalette(PaletteID.leonardoClassic.rawValue, project: false)
            session.setMermaid(true, project: false)
            session.setMath(true, project: false)
            session.setVegaLite(true, project: false)
            await session.settingsTask?.value
            session.mode = .preview
            let hosting = NSHostingView(rootView: WorkspaceView(session: session))
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 850),
                                  styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = hosting
            window.orderFront(nil)
            defer { window.close() }
            let web = try await findWebView(in: hosting)
            let expectedImageCount = language == .spanish ? 23 : 22
            try await waitFor("document.images.length === \(expectedImageCount)", in: web)
            for index in 0..<expectedImageCount {
                _ = try await web.evaluateJavaScript("document.images[\(index)].scrollIntoView({block:'center'})")
                try await waitFor("document.images[\(index)].naturalWidth > 0", in: web)
            }
            try await waitFor("document.querySelectorAll('[data-field-input]').length === 0 && document.querySelector('a[href$=\"/practice.mdlr\"]') !== null", in: web)
            try await waitFor("document.querySelectorAll('.katex-display').length === 4 && document.querySelectorAll('.katex svg path[d]').length >= 4 && document.querySelector('.katex svg line') !== null && document.querySelector('.katex-error') === null && document.querySelector('.katex-tag') !== null", in: web)
            let guidanceNeedle = language == .english
                ? "Check that these examples display as equations"
                : "Comprueba que estos ejemplos aparecen como ecuaciones"
            let encodedGuidanceNeedle = try XCTUnwrap(String(data: JSONEncoder().encode(guidanceNeedle), encoding: .utf8))
            let guidanceScript = "Array.from(document.querySelectorAll('p')).find(node => node.textContent.includes(\(encodedGuidanceNeedle)))?.textContent || ''"
            let guidanceValue = try await web.evaluateJavaScript(guidanceScript)
            let guidanceText = try XCTUnwrap(guidanceValue as? String)
            XCTAssertTrue(guidanceText.contains(guidanceNeedle))
            XCTAssertFalse(guidanceText.contains("$$"),
                           "Display-math markers should not appear in ordinary prose when Math is enabled")
            let regression = try XCTUnwrap(session.headings.first { $0.title.contains("regression examples") || $0.title.contains("ejemplos de regresión") })
            session.jumpToHeading(regression.line)
            try await waitFor("Math.abs(window.LeonardoTables.headingForSourceLine(document.querySelector('#leonardo-markdown'), \(regression.line)).getBoundingClientRect().top) < 2", in: web)
            try await waitFor("document.querySelector('.vega-lite-placeholder svg') !== null", in: web)
            try await waitFor("Array.from(document.querySelectorAll('p')).some(node => node.textContent.includes('[LL1 op=snapshot'))", in: web)
            _ = try await web.evaluateJavaScript("document.querySelector('.mermaid-placeholder').scrollIntoView({block:'center'})")
            try await waitFor("document.querySelector('.mermaid-placeholder svg') !== null", in: web)
            _ = try await web.evaluateJavaScript("window.scrollTo(0,0)")
            // WKWebView snapshots are a separate opt-in from broad native
            // component captures. Keep long-running snapshot teardown out of
            // ordinary CI rendering while retaining both locale assertions.
        }
    }

    func testAgentImportGuideOpensAndRendersBothLocalesWithoutReplacingDocuments() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let previousLanguage = LanguageSettings.shared.language
        defer {
            LanguageSettings.shared.language = previousLanguage
            try? FileManager.default.removeItem(at: root)
        }
        for language in AppLanguage.allCases {
            LanguageSettings.shared.language = language
            let tabs = DocumentTabs(preferencesURL: root.appendingPathComponent("preferences-\(language.rawValue).json"))
            defer { tabs.stop() }
            let original = tabs.activeSession
            original.authorizePath = { _, _ in }
            await tabs.openUserGuide(language: language, supportDirectory: root, topic: .agentImport)
            let session = tabs.activeSession
            XCTAssertFalse(session === original)
            XCTAssertNil(session.errorMessage)
            XCTAssertEqual(session.mode, .preview)
            XCTAssertEqual(session.displayDocumentURL?.lastPathComponent, "AgentImport-v3-\(language.rawValue).mdlz")
            XCTAssertTrue(session.displayDocumentURL?.path.contains("Agent Import Guides/v3/") == true)
            XCTAssertFalse(session.leonardoDocument?.isForm ?? true)
            let copy = try XCTUnwrap(session.displayDocumentURL)
            let bytes = try Data(contentsOf: copy)
            let tabCount = tabs.tabs.count
            await tabs.openUserGuide(language: language, supportDirectory: root, topic: .agentImport)
            XCTAssertEqual(tabs.tabs.count, tabCount)
            XCTAssertTrue(tabs.activeSession === session)
            XCTAssertEqual(try Data(contentsOf: copy), bytes)
            XCTAssertTrue(tabs.tabs.contains { $0.session === original })

            let hosting = NSHostingView(rootView: WorkspaceView(session: session))
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 850),
                                  styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = hosting
            window.orderFront(nil)
            defer { window.close() }
            let web = try await findWebView(in: hosting)
            try await waitFor("document.querySelector('h1') !== null && document.images.length === 1 && document.images[0].naturalWidth > 0", in: web)
            let renderedText = try await web.evaluateJavaScript("document.body.innerText")
            let text = try XCTUnwrap(renderedText as? String)
            XCTAssertTrue(text.contains(language == .english ? "Import with your agent" : "Importar con tu agente"))
            XCTAssertTrue(text.contains("leonardo-format"))
            XCTAssertTrue(text.contains(language == .english ? "Request to copy" : "Encargo que puedes copiar"))
        }
    }

    private func findWebView(in view: NSView) async throws -> WKWebView {
        func find(_ node: NSView) -> WKWebView? {
            if let web = node as? WKWebView { return web }
            return node.subviews.lazy.compactMap { find($0) }.first
        }
        for _ in 0..<100 {
            if let web = find(view) { return web }
            try await Task.sleep(for: .milliseconds(30))
        }
        throw NSError(domain: "BundledUserGuideTests.missingWebView", code: 1)
    }

    private func waitFor(_ expression: String, in web: WKWebView) async throws {
        for _ in 0..<150 {
            if (try? await web.evaluateJavaScript(expression)) as? Bool == true { return }
            try await Task.sleep(for: .milliseconds(30))
        }
        XCTFail("Guide rendering condition failed: \(expression)")
        throw NSError(domain: "BundledUserGuideTests.rendering", code: 1)
    }
}
