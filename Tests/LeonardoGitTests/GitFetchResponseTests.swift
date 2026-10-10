import XCTest
import CryptoKit
@testable import LeonardoGit

final class GitFetchResponseTests: XCTestCase {
    func testProgressDoesNotEnterPackAndStatelessEndIsSupported() throws {
        for format in ["sha1", "sha256"] {
            let caps = try capabilities(format)
            let pack = emptyPack(format)
            let response = try wire([.data(Data("packfile\n".utf8)), .data(Data([2]) + Data("Untrusted progress".utf8)),
                                     .data(Data([1]) + pack.prefix(9)), .data(Data([1]) + pack.dropFirst(9)), .flush, .responseEnd])
            let parsed = try GitFetchResponse(response: response, capabilities: caps)
            XCTAssertEqual(parsed.pack, pack)
            XCTAssertEqual(parsed.objectCount, 0)
            XCTAssertTrue(parsed.shallowCommits.isEmpty)
        }
    }

    func testCorruptionFatalSidebandAndUnrequestedSectionsFail() throws {
        let caps = try capabilities("sha1")
        var corrupted = emptyPack("sha1")
        corrupted[corrupted.count - 1] ^= 1
        for packets: [GitPacket] in [
            [.data(Data("packfile\n".utf8)), .data(Data([1]) + corrupted), .flush],
            [.data(Data("packfile\n".utf8)), .data(Data([3]) + Data("remote failure".utf8)), .flush],
            [.data(Data("packfile-uris\n".utf8)), .data(Data("https://untrusted.invalid/pack".utf8)), .flush],
            [.data(Data("packfile\n".utf8)), .data(Data([4, 1])), .flush],
            [.data(Data("packfile\n".utf8)), .data(Data([1]) + emptyPack("sha1")), .delimiter, .flush]
        ] {
            XCTAssertThrowsError(try GitFetchResponse(response: wire(packets), capabilities: caps))
        }
        let valid = try wire([.data(Data("packfile\n".utf8)), .data(Data([1]) + emptyPack("sha1")), .flush])
        XCTAssertThrowsError(try GitFetchResponse(response: valid, capabilities: caps, maximumPackBytes: 10))
        XCTAssertThrowsError(try GitFetchResponse(response: valid, capabilities: caps, maximumWireBytes: 10))
    }

    private func emptyPack(_ format: String) -> Data {
        let header = Data([80, 65, 67, 75, 0, 0, 0, 2, 0, 0, 0, 0])
        return header + (format == "sha256" ? Data(SHA256.hash(data: header)) : Data(Insecure.SHA1.hash(data: header)))
    }

    private func capabilities(_ format: String) throws -> GitV2Capabilities {
        try GitV2Capabilities(advertisement: wire([.data(Data("version 2\n".utf8)), .data(Data("ls-refs\n".utf8)),
            .data(Data("fetch=shallow filter\n".utf8)), .data(Data("object-format=\(format)\n".utf8)), .flush]))
    }

    private func wire(_ packets: [GitPacket]) throws -> Data {
        try packets.reduce(into: Data()) { $0 += try $1.encoded() }
    }
}
