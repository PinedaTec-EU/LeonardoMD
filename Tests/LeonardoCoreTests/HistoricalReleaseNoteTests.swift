import XCTest
import LeonardoCore

final class HistoricalReleaseNoteTests: XCTestCase {
    func testBundledHistoryIncludesAllMergedPRsThrough207() {
        let notes = HistoricalReleaseNote.all
        let expected: Set<Int> = [
            8, 17, 19, 21, 24, 28, 30, 32, 36, 37, 40, 42, 43, 48, 50, 52, 54, 56, 58,
            59, 62, 63, 64, 66, 67, 71, 76, 79, 82, 87, 89, 93, 124, 127, 129, 131, 134,
            138, 139, 141, 143, 145, 147, 155, 157, 159, 161, 162, 164, 168, 174, 179,
            184, 186, 190, 192, 197, 199, 205, 207,
        ]
        XCTAssertEqual(Set(notes.map(\.pr)), expected)
        XCTAssertEqual(notes.count, expected.count)
        XCTAssertTrue(notes.allSatisfy { !$0.en.isEmpty && !$0.es.isEmpty })
        XCTAssertEqual(HistoricalReleaseNote.byPR[207]?.url.absoluteString,
                       "https://github.com/PinedaTec-EU/LeonardoMD/pull/207")
    }
}
