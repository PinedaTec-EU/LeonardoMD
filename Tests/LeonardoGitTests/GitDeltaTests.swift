import XCTest
@testable import LeonardoGit

final class GitDeltaTests: XCTestCase {
    func testCopyAndInsertWithNonzeroDataIndices() throws {
        let base = Data("prefixHello world".utf8).dropFirst(6)
        let delta = Data([99, 11, 11, 0x90, 6, 5] + Array("Swift".utf8)).dropFirst()
        XCTAssertEqual(try GitDelta.apply(delta, to: base), Data("Hello Swift".utf8))
    }

    func testImplicitCopySizeAndOmittedOffsetBytes() throws {
        let base = Data(repeating: 42, count: 65_537)
        let implicit = size(base.count) + size(65_536) + Data([0x80])
        XCTAssertEqual(try GitDelta.apply(implicit, to: base), Data(repeating: 42, count: 65_536))
        // offset3 remains bits 16–23 even when offset1/offset2 are omitted.
        let highOffset = size(base.count) + size(1) + Data([0x94, 1, 1])
        XCTAssertEqual(try GitDelta.apply(highOffset, to: base), Data([42]))
    }

    func testMalformedDeltaCannotOverreadOrExceedDeclaredResult() {
        let base = Data("abc".utf8)
        for bytes: [UInt8] in [[3, 1, 0], [3, 2, 1, 65], [3, 1, 2, 65, 66],
                              [3, 1, 0x91, 3, 1], [3, 1, 0x91], [4, 1, 1, 65],
                              [3, 1, 0x80], [3, 0, 1, 65]] {
            XCTAssertThrowsError(try GitDelta.apply(Data(bytes), to: base))
        }
        XCTAssertThrowsError(try GitDelta.apply(Data(repeating: 0xff, count: 20), to: base))
        XCTAssertThrowsError(try GitDelta.apply(size(3) + size(100), to: base, maximumResultBytes: 10))
    }

    private func size(_ value: Int) -> Data {
        var value = value
        var bytes = Data()
        repeat {
            var byte = UInt8(value & 0x7f)
            value >>= 7
            if value != 0 { byte |= 0x80 }
            bytes.append(byte)
        } while value != 0
        return bytes
    }
}
