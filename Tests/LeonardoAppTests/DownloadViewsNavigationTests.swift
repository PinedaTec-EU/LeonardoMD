import XCTest
import LeonardoSync
@testable import LeonardoSyncUI

@MainActor
final class DownloadViewsNavigationTests: XCTestCase {
    func testRefreshPreservesExistingNestedFolder() {
        let catalogue = RemoteProjectCatalogue(
            files: [entry("notes/archive/old.md")],
            directories: ["notes/archive"])

        XCTAssertEqual(SyncCatalogueView.navigationPath(afterRefresh: "notes/archive", in: catalogue), "notes/archive")
    }

    func testRefreshMovesToNearestExistingAncestorWhenFolderDisappears() {
        let catalogue = RemoteProjectCatalogue(files: [entry("notes/current.md")])

        XCTAssertEqual(SyncCatalogueView.navigationPath(afterRefresh: "notes/archive", in: catalogue), "notes")
        XCTAssertEqual(SyncCatalogueView.navigationPath(afterRefresh: "notes/archive", in: RemoteProjectCatalogue(files: [])), "")
    }

    private func entry(_ path: String) -> RemoteFileEntry {
        RemoteFileEntry(path: path, byteCount: 1, revision: "sha256:" + String(repeating: "a", count: 64))
    }
}
