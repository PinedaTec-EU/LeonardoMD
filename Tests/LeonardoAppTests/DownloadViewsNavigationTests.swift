import XCTest
import LeonardoSync
import LeonardoCore
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

    func testRemoteCatalogueHidesNonDocumentRowsByDefaultPerSurface() {
        let view = SyncCatalogueView(
            library: DownloadLibrary(cache: OnDemandCache(root: FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString))),
            projectID: UUID()
        ) { _ in }
        XCTAssertFalse(view.showNonDocumentFiles)

        let catalogue = RemoteProjectCatalogue(files: [
            entry("notes/readme.md"),
            entry("notes/package.mdlz"),
            entry("notes/diagram.png")
        ])
        let files = catalogue.immediateFiles(at: "notes")

        XCTAssertEqual(
            SyncCatalogueView.visibleFiles(files, showNonDocumentFiles: false, on: .macOS).map(\.path),
            ["notes/readme.md", "notes/package.mdlz"]
        )
        XCTAssertEqual(
            SyncCatalogueView.visibleFiles(files, showNonDocumentFiles: false, on: .littleLeonardo).map(\.path),
            ["notes/readme.md"]
        )
        XCTAssertEqual(
            SyncCatalogueView.visibleFiles(files, showNonDocumentFiles: true, on: .littleLeonardo).map(\.path),
            ["notes/readme.md", "notes/package.mdlz", "notes/diagram.png"]
        )
    }

    private func entry(_ path: String) -> RemoteFileEntry {
        RemoteFileEntry(path: path, byteCount: 1, revision: "sha256:" + String(repeating: "a", count: 64))
    }
}
