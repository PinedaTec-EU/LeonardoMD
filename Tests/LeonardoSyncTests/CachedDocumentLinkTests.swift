import XCTest
@testable import LeonardoSync

final class CachedDocumentLinkTests: XCTestCase {
    func testCachedSiblingAndEncodedAnchorResolveWithoutFilesystemAccess() throws {
        let root = URL(fileURLWithPath: "/LittleLeonardoCorpus", isDirectory: true)
        let file = CorpusFile(path: "docs/next note.md", content: Data("# Next".utf8))
        let target = CachedDocumentLink(url: try XCTUnwrap(URL(string: "file:///LittleLeonardoCorpus/docs/next%20note.md#next%20heading")),
            virtualRoot: root, scope: try CorpusScope(folder: "docs"), files: [file])
        XCTAssertEqual(target?.file, file)
        XCTAssertEqual(target?.anchor, "next heading")
    }

    func testTraversalRootAliasesExternalAndUncachedLinksAreDenied() throws {
        let root = URL(fileURLWithPath: "/LittleLeonardoCorpus", isDirectory: true)
        let scope = try CorpusScope(folder: "docs")
        let files = [CorpusFile(path: "docs/note.md", content: Data("note".utf8)),
                     CorpusFile(path: "other/note.md", content: Data("other".utf8))]
        for value in ["file:///LittleLeonardoCorpus/docs/../../note.md", "file:///LittleLeonardoCorpusOther/docs/note.md",
                      "file:///LittleLeonardoCorpus/other/note.md", "file:///LittleLeonardoCorpus/docs/missing.md",
                      "file://remote/LittleLeonardoCorpus/docs/note.md", "https://example.org/docs/note.md",
                      "file:///LittleLeonardoCorpus/docs/note.md?download=true"] {
            XCTAssertNil(CachedDocumentLink(url: try XCTUnwrap(URL(string: value)), virtualRoot: root,
                                             scope: scope, files: files), value)
        }
    }

    func testImagesAndInvalidUTF8CannotBecomeEditableDocuments() throws {
        let root = URL(fileURLWithPath: "/LittleLeonardoCorpus", isDirectory: true)
        let scope = try CorpusScope(folder: "docs")
        let files = [CorpusFile(path: "docs/image.png", content: Data([1, 2, 3])),
                     CorpusFile(path: "docs/binary.md", content: Data([0xff]))]
        for file in files {
            XCTAssertNil(CachedDocumentLink(url: root.appendingPathComponent(file.path), virtualRoot: root,
                                             scope: scope, files: files))
        }
    }
}
