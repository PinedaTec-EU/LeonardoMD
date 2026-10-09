import XCTest
@testable import LeonardoGit
import LeonardoSync

final class GitTreeTests: XCTestCase {
    private let id = String(repeating: "a", count: 40)

    private func tree(_ entries: [(String, String)], trailing: Data = Data()) -> GitObject {
        let bytes = entries.reduce(into: Data()) { result, entry in
            result += Data("\(entry.0) \(entry.1)\0".utf8) + Data(repeating: 1, count: 20)
        } + trailing
        return GitObject(id: id, kind: .tree, data: bytes)
    }

    func testBinaryTreeModesAndUnicodeNames() throws {
        let entries = try GitTree.entries(in: tree([("40000", "documentación"), ("100644", "readme.md"),
            ("100755", "script.txt"), ("120000", "link"), ("160000", "dependency")]))
        XCTAssertEqual(entries.map(\.kind), [.folder, .file, .file, .symbolicLink, .submodule])
        XCTAssertTrue(entries[2].executable)
        XCTAssertEqual(entries[0].name, "documentación")
        XCTAssertEqual(entries[0].objectID, String(repeating: "01", count: 20))
    }

    func testMalformedNamesModesAliasesAndTruncationFail() throws {
        for name in ["", ".", "..", "a/b", "a\\b", "a:b", "a\n"] {
            XCTAssertThrowsError(try GitTree.entries(in: tree([("100644", name)])))
        }
        XCTAssertThrowsError(try GitTree.entries(in: tree([("100600", "note.md")])))
        XCTAssertThrowsError(try GitTree.entries(in: tree([("100644", "A.md"), ("100644", "a.md")])))
        XCTAssertThrowsError(try GitTree.entries(in: tree([("100644", "é.md"), ("100644", "e\u{301}.md")])))
        XCTAssertThrowsError(try GitTree.entries(in: tree([], trailing: Data("100644 note.md\0abc".utf8))))
        XCTAssertThrowsError(try GitTree.entries(in: tree([("100644", "note.md")]), maximumEntries: 0))
    }

    func testFolderScopeOmitsLinksSubmodulesAndUnsupportedFiles() throws {
        let root = tree([("100644", "note.md"), ("100644", "code.swift"), ("120000", "outside.md"), ("160000", "other")])
        let commit = GitObject(id: String(repeating: "b", count: 40), kind: .commit, data: Data("tree \(id)\n\nFixture\n".utf8))
        let index = try GitFolderIndex(objects: [root, commit], commitID: commit.id)
        XCTAssertEqual(try index.files(in: CorpusScope(folder: "")).map(\.path), ["note.md"])
        XCTAssertThrowsError(try index.files(in: CorpusScope(folder: "outside.md")))
        XCTAssertThrowsError(try index.files(in: CorpusScope(folder: ""), maximumFiles: 0))
    }
}
