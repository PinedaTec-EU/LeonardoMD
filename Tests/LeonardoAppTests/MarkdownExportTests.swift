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
            fields: ["name": .init()], values: ["name": .string("Ada")]))))
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

    func testWarningExplainsLossAndAllowsCancellation() {
        let alert = AppSession.markdownExportWarning()
        XCTAssertEqual(alert.alertStyle, .warning)
        XCTAssertEqual(alert.buttons.count, 2)
        XCTAssertEqual(alert.buttons[1].title, L10n.text("Cancel"))
        XCTAssertFalse(alert.informativeText.isEmpty)
    }
}
#endif
