import XCTest
@testable import LeonardoCore

final class LeonardoMarkdownMigrationTests: XCTestCase {
    func testConversionRetainsCompleteMetadataAndEditedBodyByteForByte() throws {
        for newline in ["\n", "\r\n"] {
            let header = ["---", "title: \"🎓 Article\"", "author: José", "tags: [Swift, docs]",
                          "# Preserve this comment", "custom:", "  nested: [1, true]", "description: |",
                          "  First line", "  Second line", "source_url: https://example.com/article", "...", ""].joined(separator: newline)
            let body = newline + "# 🎓 Article" + newline + "Edited text,  " + newline + "---" + newline
            let source = header + body
            let document = LeonardoMarkdownMigration.convert(source, fallbackTitle: "filename")
            XCTAssertEqual(Data(document.body.utf8), Data(body.utf8))
            XCTAssertEqual(document.metadata.document.title, "🎓 Article")
            XCTAssertEqual(document.metadata.values[LeonardoMarkdownMigration.frontMatterValueKey], .string(header))
            let saved = try LeonardoFormatParser.parse(LeonardoFormatParser.serialize(document))
            XCTAssertEqual(saved, document)
            let metadata = LeonardoMarkdownMigration.previewMetadata(for: saved)
            XCTAssertEqual(metadata.frontMatter["author"], "José")
            XCTAssertEqual(metadata.tags, ["Swift", "docs"])
        }
    }

    func testNoEnvelopeAndUnclosedEnvelopeRemainUntouched() {
        for source in ["# Body\r\nText  \r\n", "---\ntitle: incomplete\n# Body", "---"] {
            let document = LeonardoMarkdownMigration.convert(source, fallbackTitle: "filename")
            XCTAssertEqual(document.body, source)
            XCTAssertTrue(document.metadata.values.isEmpty)
            XCTAssertEqual(document.metadata.document.title, "filename")
        }
    }

    func testEnvelopeEndingAtEOFAndEmptyBody() {
        for source in ["---\ntitle: Note\n---", "---\ntitle: Note\n---\n"] {
            let document = LeonardoMarkdownMigration.convert(source, fallbackTitle: "filename")
            XCTAssertEqual(document.body, "")
            XCTAssertEqual(document.metadata.values[LeonardoMarkdownMigration.frontMatterValueKey], .string(source))
            XCTAssertEqual(document.metadata.document.title, "Note")
        }
    }
}
