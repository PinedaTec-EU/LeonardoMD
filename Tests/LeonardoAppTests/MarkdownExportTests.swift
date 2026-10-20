#if os(macOS)
import AppKit
import XCTest
import LeonardoCore
@testable import LeonardoApp

@MainActor
final class MarkdownExportTests: XCTestCase {
    func testExportPreservesSourceAndUsesCurrentValues() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("form.mdlf")
        let output = directory.appendingPathComponent("copy.md")
        let original = try LeonardoFormatParser.serialize(.init(body: "Hello {{field:name}}", metadata: .init(
            fields: ["name": .init()], values: ["name": .string("Ada")])))
        try original.write(to: source, atomically: true, encoding: .utf8)
        let session = AppSession(preferencesURL: directory.appendingPathComponent("preferences.json"))
        defer { session.stop() }
        var authorized: [URL] = []
        session.authorizePath = { url, _ in authorized.append(url) }
        await session.openDocument(source)
        authorized.removeAll()
        await session.exportMarkdown(to: output, documentURL: source)
        XCTAssertEqual(try String(contentsOf: output, encoding: .utf8), "Hello Ada")
        XCTAssertEqual(try String(contentsOf: source, encoding: .utf8), original)
        XCTAssertEqual(session.documentURL, source)
        XCTAssertTrue(authorized.contains(source))
        XCTAssertTrue(authorized.contains(output))
        XCTAssertEqual(session.fileOperationCount, 0)
        XCTAssertFalse(session.busy)
    }

    func testPackageAuthorizationAndIdentityChangesPreventWrites() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("form.mdlr")
        let package = directory.appendingPathComponent("form.mdlz")
        let output = directory.appendingPathComponent("copy.md")
        let original = try LeonardoFormatParser.serialize(.init(body: "{{field:a}}", metadata: .init(
            fields: ["a": .init(defaultValue: .string("Value"))])))
        try original.write(to: source, atomically: true, encoding: .utf8)
        try LeonardoPackageTransport.export(documentURL: source, content: original, to: package)
        let session = AppSession(preferencesURL: directory.appendingPathComponent("preferences.json"))
        defer { session.stop() }
        session.authorizePath = { _, _ in }
        let opened = await session.openLeonardoPackage(package, extractingTo: nil)
        XCTAssertTrue(opened)
        let workingURL = try XCTUnwrap(session.documentURL)
        struct Denied: Error {}
        session.authorizePath = { url, _ in if url == package { throw Denied() } }
        await session.exportMarkdown(to: output, documentURL: workingURL)
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
        session.authorizePath = { url, _ in if url == output { session.content += "changed" } }
        await session.exportMarkdown(to: output, documentURL: workingURL)
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
        session.authorizePath = { _, _ in }
        await session.exportMarkdown(to: output, documentURL: workingURL)
        XCTAssertEqual(try String(contentsOf: output, encoding: .utf8), "Valuechanged")
        XCTAssertEqual(session.documentStorage, .package)
        XCTAssertEqual(session.fileOperationCount, 0)
    }

    func testCaptureMarkdownWarningInBothLanguages() async throws {
        guard let path = ProcessInfo.processInfo.environment["LEONARDO_VISUAL_EVIDENCE"] else {
            throw XCTSkip("Set LEONARDO_VISUAL_EVIDENCE for native warning captures")
        }
        let directory = URL(fileURLWithPath: path).appendingPathComponent("markdown-export")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let previous = LanguageSettings.shared.language
        defer { LanguageSettings.shared.language = previous }
        for language in AppLanguage.allCases {
            LanguageSettings.shared.language = language
            let alert = AppSession.markdownExportWarning()
            alert.layout()
            let window = alert.window
            window.orderFront(nil)
            defer { window.orderOut(nil) }
            try await Task.sleep(for: .milliseconds(150))
            let view = try XCTUnwrap(window.contentView)
            view.displayIfNeeded()
            let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
            view.cacheDisplay(in: view.bounds, to: bitmap)
            let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            let output = directory.appendingPathComponent("warning-\(language.rawValue).png")
            try png.write(to: output)
            let capture = Process()
            capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            capture.arguments = ["-x", "-l", String(window.windowNumber), output.path]
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                capture.terminationHandler = { _ in continuation.resume() }
                do { try capture.run() } catch { continuation.resume(throwing: error) }
            }

        }
    }

    func testWarningExplainsLossAndAllowsCancellation() {
        let alert = AppSession.markdownExportWarning()
        XCTAssertEqual(alert.alertStyle, .warning)
        XCTAssertEqual(alert.buttons.count, 2)
        XCTAssertEqual(alert.buttons[1].title, L10n.text("Cancel"))
        XCTAssertFalse(alert.informativeText.isEmpty)
    }
}
#endif
