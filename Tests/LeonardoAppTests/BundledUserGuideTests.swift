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
        let oldCopies = (2..<35).flatMap { revision in
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
            XCTAssertTrue(copy.path.contains("User Guides/v35/"))
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
            XCTAssertTrue(source.contains("Demo-es.mdlr") && source.contains("Demo-en.mdlr"), "The combined guide must explain the demo project documents")
            XCTAssertTrue(source.contains("Recuperar demo / Restore demo"), "Both guides must explain demo recovery")
            let document = try LeonardoFormatParser.parse(source)
            XCTAssertFalse(document.isForm)
            XCTAssertEqual(document.metadata.fields.count, 0)
            let expectedImageCount = language == .spanish ? 20 : 19
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
            let expectedImageCount = language == .spanish ? 20 : 19
            try await waitFor("document.images.length === \(expectedImageCount)", in: web)
            for index in 0..<expectedImageCount {
                _ = try await web.evaluateJavaScript("document.images[\(index)].scrollIntoView({block:'center'})")
                try await waitFor("document.images[\(index)].naturalWidth > 0", in: web)
            }
            try await waitFor("document.querySelectorAll('[data-field-input]').length === 0 && document.querySelector('a[href$=\"/practice.mdlr\"]') !== null", in: web)
            try await waitFor("document.querySelectorAll('.katex-display').length === 4 && document.querySelectorAll('.katex svg path[d]').length >= 4 && document.querySelector('.katex svg line') !== null && document.querySelector('.katex-error') === null && document.querySelector('.katex-tag') !== null", in: web)
            let regression = try XCTUnwrap(session.headings.first { $0.title.contains("regression examples") || $0.title.contains("ejemplos de regresión") })
            session.jumpToHeading(regression.line)
            try await waitFor("Math.abs(window.LeonardoTables.headingForSourceLine(document.querySelector('#leonardo-markdown'), \(regression.line)).getBoundingClientRect().top) < 2", in: web)
            try await waitFor("document.querySelector('.vega-lite-placeholder svg') !== null", in: web)
            try await waitFor("Array.from(document.querySelectorAll('p')).some(node => node.textContent.includes('[LL1 op=snapshot'))", in: web)
            _ = try await web.evaluateJavaScript("document.querySelector('.mermaid-placeholder').scrollIntoView({block:'center'})")
            try await waitFor("document.querySelector('.mermaid-placeholder svg') !== null", in: web)
            _ = try await web.evaluateJavaScript("window.scrollTo(0,0)")
            if let output = ProcessInfo.processInfo.environment["LEONARDO_VISUAL_EVIDENCE"] {
                let directory = URL(fileURLWithPath: output).appendingPathComponent("user-guide")
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let encodedSource = try XCTUnwrap(String(data: JSONEncoder().encode(session.content), encoding: .utf8))
                try await waitFor("window.LeonardoEditing.currentSource() === \(encodedSource)", in: web)
                for (name, selector) in [("diagram", ".mermaid-placeholder"), ("math", ".katex"), ("math-regression", ".math-rendered:has(.katex-tag)"), ("chart", ".vega-lite-placeholder")] {
                    _ = try await web.evaluateJavaScript("document.querySelector('\(selector)').scrollIntoView({block:'center'})")
                    let readySelector = name.hasPrefix("math") ? selector : selector + " svg"
                    try await waitFor("document.querySelector('\(readySelector)') !== null", in: web)
                    try await GuideCaptureSupport.capture(web, to: directory.appendingPathComponent("\(name)-\(language.rawValue).png"),
                        language: language.rawValue, state: "Live \(name) example; built-in extension enabled")
                }
                for name in ["palette", "activation", "sync-sharing-v12"] {
                    _ = try await web.evaluateJavaScript("document.querySelector('img[src$=\"/\(name).png\"]').scrollIntoView({block:'center'})")
                    try await GuideCaptureSupport.capture(web, to: directory.appendingPathComponent("section-\(name)-\(language.rawValue).png"),
                        language: language.rawValue, state: "Detailed chapter with original \(name) screenshot; all images loaded")
                }
                _ = try await web.evaluateJavaScript("Array.from(document.querySelectorAll('p')).find(node => node.textContent.includes('[LL1 op=snapshot')).scrollIntoView({block:'center'})")
                try await GuideCaptureSupport.capture(web, to: directory.appendingPathComponent("transport-diagnostic-\(language.rawValue).png"),
                    language: language.rawValue, state: "Interrupted HTTPS response guidance; diagnostic code contains no request identifiers")
                let illustrations = language == .english ? ["journey", "package", "import", "export"] : ["recorrido", "paquete", "importar", "exportar"]
                for name in illustrations {
                    _ = try await web.evaluateJavaScript("document.querySelector('img[src$=\"/\(name).png\"]').scrollIntoView({block:'center'})")
                    let imageCount = language == .spanish ? 20 : 19
                    try await GuideCaptureSupport.capture(web, to: directory.appendingPathComponent("premium-\(name)-\(language.rawValue).png"),
                        language: language.rawValue, state: "Main guide; generated premium \(name) illustration; all \(imageCount) images admitted under standard limits")
                }
                _ = try await web.evaluateJavaScript("window.scrollTo(0,0)")
                try await GuideCaptureSupport.capture(web, to: directory.appendingPathComponent("guide-\(language.rawValue).png"),
                    language: language.rawValue, state: "Guide preview; all local images loaded")
                _ = try await web.evaluateJavaScript("document.querySelector('a[href$=\"/practice.mdlr\"]').scrollIntoView({block:'center'})")
                try await GuideCaptureSupport.capture(web, to: directory.appendingPathComponent("guide-action-\(language.rawValue).png"),
                    language: language.rawValue, state: "Reading guide; separate-practice action; no inline controls")
                let welcome = NSHostingView(rootView: WelcomeView(session: session))
                try await GuideCaptureSupport.captureWelcome(welcome, size: NSSize(width: 1100, height: 850),
                    to: directory.appendingPathComponent("welcome-\(language.rawValue).png"), language: language.rawValue)
                let provenance = "Head: \(ProcessInfo.processInfo.environment["EVIDENCE_SHA"] ?? "local")\nNative NSHostingView / WKWebView, 1100x850 points; synthetic practice data; language \(language.rawValue). Component test, not a fresh product process.\n"
                try provenance.write(to: directory.appendingPathComponent("provenance-\(language.rawValue).txt"), atomically: true, encoding: .utf8)
            }
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
            if let output = ProcessInfo.processInfo.environment["LEONARDO_VISUAL_EVIDENCE"] {
                let directory = URL(fileURLWithPath: output).appendingPathComponent("agent-import")
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                try await GuideCaptureSupport.capture(web, to: directory.appendingPathComponent("overview-\(language.rawValue).png"),
                    language: language.rawValue, state: "Agent import guide; original illustrative PNG loaded; no PDF selected or sent")
                _ = try await web.evaluateJavaScript("document.querySelector('pre').scrollIntoView({block:'start'})")
                try await GuideCaptureSupport.capture(web, to: directory.appendingPathComponent("prompt-\(language.rawValue).png"),
                    language: language.rawValue, state: "Agent import guide; copyable conversion request")
            }
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
