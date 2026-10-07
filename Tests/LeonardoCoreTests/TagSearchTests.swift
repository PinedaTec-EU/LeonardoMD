import Foundation
import XCTest
@testable import LeonardoCore

final class TagSearchTests: XCTestCase {
    func testInlineAndBlockTagsShareNormalizedValues() {
        let inline = MarkdownDocumentParser.parse("---\ntags: [Swift, 'Design Systems', SWIFT, \"comma, tag\", 'team''s notes'] # comment\n---\n# Body")
        let block = MarkdownDocumentParser.parse("---\ntags:\n  - Swift\n  - 'Design Systems'\n  - SWIFT\n  - \"comma, tag\"\n  - 'team''s notes' # comment\ntitle: Note\n---\n# Body")
        XCTAssertEqual(inline.tags, ["Swift", "Design Systems", "comma, tag", "team's notes"])
        XCTAssertEqual(inline.tags, block.tags)
        XCTAssertEqual(MarkdownDocumentParser.parse("---\ntags: ['team''s, notes', docs]\n---\n").tags, ["team's, notes", "docs"])
        XCTAssertEqual(inline.body, "# Body")
        XCTAssertEqual(block.frontMatter["title"], "Note")
    }

    func testTagsIgnoreNestedFieldsMissingDelimitersAndMalformedLists() {
        for source in ["# tags: [Swift]", "---\ntags: [Swift]\n# Body", "---\nother:\n  tags: [Swift]\n---\nBody", "---\ntags: [Swift\n---\nBody"] {
            XCTAssertTrue(MarkdownDocumentParser.parse(source).tags.isEmpty, source)
        }
        XCTAssertEqual(MarkdownDocumentParser.parse("---\ntags:\n- Swift\n- 'design'\n---\nBody").tags, ["Swift", "design"])
        XCTAssertEqual(MarkdownDocumentParser.parse("---\ntags: [team's notes, docs]\n---\n").tags, ["team's notes", "docs"])
        XCTAssertEqual(MarkdownDocumentParser.parse("---\ntags: \"say \\\"hi\\\"\" # note\n---\n").tags, ["say \"hi\""])
    }

    func testGeneratedQueriesRoundTripArbitraryTagStrings() {
        for tag in ["Swift", "Design Systems", "say \"hi\"", "path\\name", "line\nbreak", "team's notes"] {
            XCTAssertEqual(ProjectSearchQuery.tagValue(ProjectSearchQuery.query(forTag: tag)), tag)
        }
        XCTAssertEqual(ProjectSearchQuery.tagValue("TAG:swift"), "swift")
        XCTAssertEqual(ProjectSearchQuery.tagValue("tag:'Design Systems'"), "Design Systems")
        XCTAssertEqual(ProjectSearchQuery.tagValue("tag:\"unclosed"), "")
        XCTAssertNil(ProjectSearchQuery.tagValue("normal text"))
    }

    func testExactTagSearchAndStreamingPreserveTextSearchAndBoundaries() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = LocalProjectRepository()
        let project = try await repository.project(at: root)
        let files = [
            "inline.md": "---\ntags: [Swift, 'Design Systems', swift]\n---\n# Note",
            "block.md": "---\ntags:\n - SWIFT\n - 'Design Systems'\n---\n# Note",
            "partial.md": "---\ntags: [SwiftUI]\n---\n# Note",
            "incidental.md": "# Swift\nMention Design Systems and tag:swift in text",
            "tag:swift.txt": "ordinary text",
            ".hidden.md": "---\ntags: Swift\n---\n# Hidden"
        ]
        for (name, content) in files {
            try content.write(to: root.appendingPathComponent(name), atomically: true, encoding: .utf8)
        }
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("alias.md"), withDestinationURL: root.appendingPathComponent("inline.md"))
        for query in ["tag:sWiFt", "tag:\"Design Systems\""] {
            let matches = try await repository.search(in: project, query: query)
            XCTAssertEqual(Set(matches.map(\.relativePath)), ["inline.md", "block.md"])
            XCTAssertEqual(matches.count, 2)
            var streamed: [SearchMatch] = []
            for try await batch in await repository.searchStream(in: project, query: query) { streamed += batch }
            XCTAssertEqual(Set(streamed.map(\.relativePath)), Set(matches.map(\.relativePath)))
        }
        let hidden = try await repository.search(in: project, query: "tag:swift", showHidden: true)
        XCTAssertEqual(hidden.count, 3)
        let ordinary = try await repository.search(in: project, query: "Swift")
        XCTAssertTrue(ordinary.contains { $0.relativePath == "incidental.md" && $0.lineNumber == 1 })
        XCTAssertTrue(ordinary.contains { $0.relativePath == "tag:swift.txt" && $0.matchedInFileName })
        for query in ["tag:", "tag:\"broken", "tag:Design Systems"] {
            let matches = try await repository.search(in: project, query: query)
            XCTAssertTrue(matches.isEmpty)
        }
    }
}
