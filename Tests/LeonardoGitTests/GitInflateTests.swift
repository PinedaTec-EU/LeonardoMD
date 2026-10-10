import XCTest
@testable import LeonardoGit

final class GitInflateTests: XCTestCase {
    func testStreamConsumptionDoesNotIncludeFollowingObject() throws {
        // zlib-compressed "hello", followed by unrelated next-object bytes.
        let compressed = Data([120, 156, 203, 72, 205, 201, 201, 7, 0, 6, 44, 2, 21])
        let decoded = try GitInflate.decode(compressed + Data([1, 2, 3]), expectedBytes: 5, maximumBytes: 10)
        XCTAssertEqual(decoded.data, Data("hello".utf8))
        XCTAssertEqual(decoded.consumed, compressed.count)
        XCTAssertThrowsError(try GitInflate.decode(compressed.dropLast(), expectedBytes: 5, maximumBytes: 10))
        XCTAssertThrowsError(try GitInflate.decode(compressed, expectedBytes: 4, maximumBytes: 10))
        XCTAssertThrowsError(try GitInflate.decode(compressed, expectedBytes: 6, maximumBytes: 10))
        XCTAssertThrowsError(try GitInflate.decode(compressed, expectedBytes: 5, maximumBytes: 4))
    }

    func testEmptyObjectStreamIsValid() throws {
        let compressed = Data([120, 156, 3, 0, 0, 0, 0, 1])
        let decoded = try GitInflate.decode(compressed, expectedBytes: 0, maximumBytes: 0)
        XCTAssertTrue(decoded.data.isEmpty)
        XCTAssertEqual(decoded.consumed, compressed.count)
    }
}
