import XCTest
import Sparkle

final class UpdateVersionTests: XCTestCase {
    func testBuildNumbersOrderAcrossBetaAndStableDisplayVersions() {
        let comparator = SUStandardVersionComparator.default
        XCTAssertEqual(comparator.compareVersion("9", toVersion: "10"), .orderedAscending)
        XCTAssertEqual(comparator.compareVersion("10", toVersion: "10"), .orderedSame)
        XCTAssertEqual(comparator.compareVersion("11", toVersion: "10"), .orderedDescending)
    }
}
