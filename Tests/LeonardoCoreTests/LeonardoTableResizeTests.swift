import XCTest
@testable import LeonardoCore

final class LeonardoTableResizeTests: XCTestCase {
    func testRoundTripPreservesBodyMetadataAndOtherTable() throws {
        var original = LeonardoMarkdownMigration.convert("# Report\r\n\r\n| A | B |\r\n| --- | --- |\r\n| One | Two |\r\n", fallbackTitle: "Report")
        original.metadata.values["custom"] = .object(["nested": .boolean(true)])
        original.metadata.layout = LeonardoLayout(tables: [LeonardoTableLayout(occurrence: 2, width: .init(value: 80, unit: .percent))])
        let resized = try LeonardoTableResize(occurrence: 1, source: "| A | B |\n| --- | --- |\n| One | Two |\n", widths: [100, 200], heights: [30, 60]).applying(to: original)
        let loaded = try LeonardoFormatParser.parse(LeonardoFormatParser.serialize(resized))
        XCTAssertEqual(loaded, resized)
        XCTAssertEqual(loaded.body, original.body)
        XCTAssertEqual(loaded.metadata.values, original.metadata.values)
        XCTAssertEqual(loaded.metadata.layout?.tables[0], original.metadata.layout?.tables[0])
        XCTAssertEqual(loaded.metadata.layout?.tables[1].height?.value, 90)
        XCTAssertEqual(loaded.metadata.layout?.tables[1].rowHeights, [30, 60])
    }

    func testRejectsInvalidGeometryAndUnsupportedHeightUnits() throws {
        let doc = LeonardoMarkdownMigration.convert("body", fallbackTitle: "test")
        for widths in [[], [0], [-1], [.infinity], [.nan], [6000, 6000]] as [[Double]] {
            XCTAssertThrowsError(try LeonardoTableResize(occurrence: 1, source: "table", widths: widths, heights: [30]).applying(to: doc))
        }
        for heights in [[], [0], [-1], [.infinity], [.nan], [6000, 6000]] as [[Double]] {
            XCTAssertThrowsError(try LeonardoTableResize(occurrence: 1, source: "table", widths: [100], heights: heights).applying(to: doc))
        }
        let raw = "---\n{\"format\":\"mdlf\",\"formatVersion\":1,\"layout\":{\"tables\":[{\"occurrence\":1,\"height\":{\"value\":50,\"unit\":\"percent\"}}]}}\n---\nTable"
        XCTAssertThrowsError(try LeonardoFormatParser.parse(raw))
    }
}
