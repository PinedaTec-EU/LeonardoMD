import XCTest
@testable import LeonardoSync

final class RemoteProjectCatalogueTests: XCTestCase {
    func testImmediateChildrenKeepCatalogueNavigationAtOneLevel() {
        let files = [
            RemoteFileEntry(path: "notes/agenda.md", byteCount: 1, revision: revision),
            RemoteFileEntry(path: "notes/archive/old.md", byteCount: 1, revision: revision),
            RemoteFileEntry(path: "assets/icon.png", byteCount: 1, revision: revision),
            RemoteFileEntry(path: "root.md", byteCount: 1, revision: revision)
        ]
        let catalogue = RemoteProjectCatalogue(files: files, directories: ["empty", "notes/archive"])

        XCTAssertEqual(catalogue.immediateFolders(at: ""), ["assets", "empty", "notes"])
        XCTAssertEqual(catalogue.immediateFiles(at: "").map(\.path), ["root.md"])
        XCTAssertEqual(catalogue.immediateFolders(at: "notes"), ["notes/archive"])
        XCTAssertEqual(catalogue.immediateFiles(at: "notes").map(\.path), ["notes/agenda.md"])
        XCTAssertEqual(catalogue.immediateFiles(at: "notes/archive").map(\.path), ["notes/archive/old.md"])
    }

    func testImmediateChildrenIncludeDeclaredEmptyFolders() {
        let catalogue = RemoteProjectCatalogue(files: [], directories: ["assets/empty"])

        XCTAssertEqual(catalogue.immediateFolders(at: ""), ["assets"])
        XCTAssertEqual(catalogue.immediateFolders(at: "assets"), ["assets/empty"])
        XCTAssertTrue(catalogue.immediateFiles(at: "assets/empty").isEmpty)
    }

    private let revision = "sha256:" + String(repeating: "a", count: 64)
}
