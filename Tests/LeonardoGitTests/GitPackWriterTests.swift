import XCTest
@testable import LeonardoGit

final class GitPackWriterTests: XCTestCase {
    func testPackRoundTripsEmptyAndLargeObjectsWithDeduplication() throws {
        for sha256 in [false, true] {
            let objects = [GitObject.create(kind: .blob, data: Data(), sha256: sha256),
                           GitObject.create(kind: .blob, data: Data(repeating: 17, count: 30_000), sha256: sha256)]
            let pack = try GitPackWriter.encode(objects: objects + objects, sha256: sha256)
            let format = sha256 ? "sha256" : "sha1"
            var advertisement = Data()
            for text in ["version 2", "ls-refs", "fetch=shallow filter", "object-format=\(format)"] {
                advertisement += try GitPacket.data(Data((text + "\n").utf8)).encoded()
            }
            advertisement += try GitPacket.flush.encoded()
            let caps = try GitV2Capabilities(advertisement: advertisement)
            let wire = try GitPacket.data(Data("packfile\n".utf8)).encoded()
                + GitPacket.data(Data([1]) + pack).encoded() + GitPacket.flush.encoded()
            XCTAssertEqual(try GitPack.decode(GitFetchResponse(response: wire, capabilities: caps), sha256: sha256), objects)
        }
    }

    func testObjectPackAndIdentifierBoundsFail() throws {
        let object = GitObject.create(kind: .blob, data: Data(repeating: 1, count: 100))
        XCTAssertThrowsError(try GitPackWriter.encode(objects: [object], maximumObjectBytes: 99))
        XCTAssertThrowsError(try GitPackWriter.encode(objects: [object], maximumBytes: 32))
        XCTAssertThrowsError(try GitPackWriter.encode(objects: [object], maximumObjectBytes: -1))
        let corrupted = GitObject(id: String(repeating: "a", count: 40), kind: .blob, data: object.data)
        XCTAssertThrowsError(try GitPackWriter.encode(objects: [corrupted]))
        XCTAssertThrowsError(try GitPackWriter.encode(objects: [object], sha256: true))
    }
}
