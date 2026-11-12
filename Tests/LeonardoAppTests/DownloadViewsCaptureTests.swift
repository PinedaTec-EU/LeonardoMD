import AppKit
import SwiftUI
import XCTest
import LeonardoSync
import LeonardoSyncUI
@testable import LeonardoApp

@MainActor final class DownloadViewsCaptureTests: XCTestCase {
    func testCaptureCacheAndRetentionStatesInBothLanguages() async throws {
        guard let path = ProcessInfo.processInfo.environment["LEONARDO_DOWNLOAD_EVIDENCE"] else {
            throw XCTSkip("Requires an explicit native component capture destination")
        }
        let destination = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let cache = OnDemandCache(root: root)
        let library = DownloadLibrary(cache: cache)
        let descriptor = SharedProjectDescriptor(id: UUID(), name: "Example project", scope: try CorpusScope(folder: ""))
        let files = ["notes/agenda.md", "notes/decisions.md", "reference/readme.md", "reference/remote.md"].map {
            CorpusFile(path: $0, content: Data("# Example\nSynthetic, non-sensitive content.".utf8))
        }
        try await library.update(id: descriptor.id, descriptor: descriptor, catalogue: RemoteProjectCatalogue(files: files.map(RemoteFileEntry.init)))
        library.fetch = { _, entry in
            if entry.path == files[1].path { throw SyncError.publicationPending }
            return files.first { $0.path == entry.path }!
        }
        _ = try await library.open(id: descriptor.id, path: files[2].path)
        await library.retain(id: descriptor.id, path: "notes", isFolder: true, keep: true)
        XCTAssertEqual(library.usage.pendingOfflineFiles, 1)
        for spanish in [false, true] {
            let view = NSHostingView(rootView: HStack(alignment: .top) {
                SyncCatalogueView(library: library, projectID: descriptor.id, spanish: spanish) { _ in }.frame(width: 620)
                Form { SyncCacheSettingsView(library: library, spanish: spanish) }.formStyle(.grouped).frame(width: 520)
            }.padding().frame(width: 1180, height: 640).background(Color(nsColor: .windowBackgroundColor)))
            let language = spanish ? "es" : "en"
            try await GuideCaptureSupport.captureNative(view, size: NSSize(width: 1180, height: 640),
                to: destination.appendingPathComponent("downloads-\(language).png"),
                language: language,
                state: "Remote-only, cached, retained, partially retained folder and interrupted pending download; independent temporary/offline usage",
                route: "/native/synchronization/downloads/\(language)",
                screen: "Shared production catalogue and storage controls")
        }
    }
}
