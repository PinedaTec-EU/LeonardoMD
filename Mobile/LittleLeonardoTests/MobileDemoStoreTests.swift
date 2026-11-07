import XCTest
import LeonardoCore
@testable import LittleLeonardo

final class MobileDemoStoreTests: XCTestCase {
    func testBootstrapPreservesAnswersAndResetOnlyAffectsSelectedLocale() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = MobileDemoStore(root: root)
        let spanish = try store.load(.es)
        let english = try store.load(.en)
        let document = try LeonardoFormatParser.parse(spanish)
        let filled = try XCTUnwrap(document.applyingFormValues(["name": .string("Review sample")]))
        let replacement = try LeonardoFormatParser.serialize(filled)
        try store.save(replacement, language: .es)
        XCTAssertEqual(try MobileDemoStore(root: root).load(.es), replacement)
        XCTAssertEqual(try store.load(.en), english)
        XCTAssertEqual(try store.reset(.en), english)
        XCTAssertEqual(try store.load(.es), replacement)
        XCTAssertEqual(try store.reset(.es), spanish)
    }

    func testMalformedPersonalCopyIsNotOverwrittenAtBootstrap() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = MobileDemoStore(root: root)
        _ = try store.load(.en)
        try "retained personal bytes".write(to: store.url(for: .en), atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try store.load(.en))
        XCTAssertEqual(try String(contentsOf: store.url(for: .en), encoding: .utf8), "retained personal bytes")
    }

    func testBothBundledTemplatesHaveRealFieldsAndOfflineExamples() throws {
        let store = MobileDemoStore()
        for language in MobileDemoStore.Language.allCases {
            let source = try store.template(language)
            let document = try LeonardoFormatParser.parse(source)
            XCTAssertEqual(document.metadata.fields.count, 4)
            XCTAssertTrue(source.contains("```mermaid"))
            XCTAssertTrue(source.contains("```vega-lite"))
            XCTAssertTrue(source.contains("\\tag{1}"))
            XCTAssertTrue(FileManager.default.fileExists(atPath: store.resources.appendingPathComponent("assets/demo.png").path))
        }
    }
}
