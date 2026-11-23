import XCTest
@testable import LeonardoSync

final class CorpusRevisionTests: XCTestCase {
    func testContentIdentityIsStableAcrossOrderingAndChangesForPathsBytesAndDraftOwnership() {
        let first = CorpusFile(path: "a.md", content: Data([0, 1, 2]))
        let second = CorpusFile(path: "b.md", content: Data("text".utf8))
        let revision = CorpusRevision.make(files: [first, second])
        XCTAssertEqual(revision, CorpusRevision.make(files: [second, first]))
        XCTAssertNotEqual(revision, CorpusRevision.make(files: [first]))
        XCTAssertNotEqual(revision, CorpusRevision.make(files: [first, CorpusFile(path: "c.md", content: second.content)]))
        XCTAssertNotEqual(revision, CorpusRevision.make(files: [first, CorpusFile(path: second.path, content: Data("changed".utf8))]))
        XCTAssertNotEqual(revision, CorpusRevision.make(files: [first, CorpusFile(path: second.path, content: second.content, isUnsavedBuffer: true)]))
        XCTAssertNotEqual(CorpusRevision.make(files: [CorpusFile(path: "ab", content: Data("c".utf8))]),
                          CorpusRevision.make(files: [CorpusFile(path: "a", content: Data("bc".utf8))]))
    }
}
