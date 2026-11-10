import SwiftUI
import WebKit
import XCTest
import LeonardoRender
import LeonardoSync
import LeonardoSyncUI
@testable import LittleLeonardo

@MainActor
final class MobileReaderSpacingTests: XCTestCase {
    func testSynchronizedDocumentViewUsesCompactReaderSpacing() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let corpus = root.appendingPathComponent("Corpus")
        let projectID = UUID()
        let file = try CorpusFile(path: "01-Prueba-visual.md", content: Data(
            "# Little Leonardo · prueba visual\n\nDocumento de prueba sin datos personales.\n\n## Imagen local\n\nLectura sincronizada de prueba.".utf8))
        let project = try OfflineProject(id: projectID, name: "QA397", mode: .direct,
            scope: CorpusScope(folder: ""), snapshot: CorpusSnapshot(revision: "qa397", files: [file]))
        try await OfflineCorpusStore(root: corpus).save(project)
        let connection = MobileDirectConnection(deviceID: UUID(), endpoint: URL(string: "https://127.0.0.1:40882")!,
            fingerprint: Data(repeating: 7, count: 32), projectIDs: [projectID], comparisonCode: nil, capabilities: [])
        try MobileDirectConnectionStore(url: root.appendingPathComponent("connections.json")).save([connection])
        let library = MobileLibrary(rootURL: corpus, credentials: ReaderSpacingCredentials())
        await library.reload()
        XCTAssertEqual(library.projects.count, 1)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let priorWindow = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        window.frame = scene.coordinateSpace.bounds
        defer { window.isHidden = true; priorWindow?.makeKeyAndVisible() }
        window.rootViewController = UIHostingController(rootView: NavigationStack {
            MobileDocumentView(library: library, projectID: projectID, file: file)
                .navigationBarTitleDisplayMode(.inline)
        })
        window.makeKeyAndVisible()
        for _ in 0..<150 {
            if let web = findWebView(window), let values = try? await metrics(web) {
                XCTAssertLessThanOrEqual(try XCTUnwrap(values["headingTop"]), 32)
                attach(window, name: "Synchronized document reader")
                return
            }
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTFail("The synchronized document did not render")
    }

    func testCompactReaderKeepsFirstHeadingNearContentTopAndLaterSectionsSpaced() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let priorWindow = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        window.frame = scene.coordinateSpace.bounds
        defer { window.isHidden = true; priorWindow?.makeKeyAndVisible() }
        let controller = MarkdownPreviewController()
        let content = "# Little Leonardo · prueba visual\n\nDocumento de prueba sin datos personales.\n\n## Imagen local\n\n" +
            String(repeating: "Lectura de prueba para comprobar el desplazamiento.\n\n", count: 30)
        let configuration = MarkdownPreviewConfiguration(appearance: .leonardoClassic)
        window.rootViewController = UIHostingController(rootView: NavigationStack {
            MarkdownPreview(content: content, configuration: configuration, controller: controller)
                .classicSurface().navigationTitle("01-Prueba-visual.md").navigationBarTitleDisplayMode(.inline)
        })
        window.makeKeyAndVisible()
        try await waitUntilReady(controller)
        let web = try XCTUnwrap(findWebView(window))
        let original = try await metrics(web)
        attach(window, name: "Default reader spacing")

        var compact = configuration
        compact.compactFirstHeading = true
        controller.update(content: content, configuration: compact)
        // Readiness is published asynchronously after applying the new configuration.
        try await Task.sleep(for: .milliseconds(150))
        try await waitUntilReady(controller)
        let adjusted = try await metrics(web)
        attach(window, name: "Compact reader spacing")
        let record = try JSONSerialization.data(withJSONObject: ["default": original, "compact": adjusted], options: [.sortedKeys])
        let facts = XCTAttachment(data: record, uniformTypeIdentifier: "public.json")
        facts.name = "Measured reader spacing"; facts.lifetime = .keepAlways; add(facts)
        XCTAssertLessThanOrEqual(try XCTUnwrap(adjusted["headingTop"]), 32)
        XCTAssertLessThan(try XCTUnwrap(adjusted["headingTop"]), try XCTUnwrap(original["headingTop"]))
        XCTAssertEqual(adjusted["laterHeadingMargin"], original["laterHeadingMargin"])
        XCTAssertGreaterThan(try XCTUnwrap(adjusted["scrollHeight"]), try XCTUnwrap(adjusted["viewportHeight"]))

        controller.update(content: content, configuration: configuration)
        try await Task.sleep(for: .milliseconds(150))
        try await waitUntilReady(controller)
        let restored = try await metrics(web)
        XCTAssertEqual(try XCTUnwrap(restored["headingTop"]), try XCTUnwrap(original["headingTop"]), accuracy: 0.5)
    }

    func testOnDemandReaderKeepsAcceptedCompactHeadingSpacing() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let library = DownloadLibrary(cache: OnDemandCache(root: root))
        let project = SharedProjectDescriptor(id: UUID(), name: "On-demand reader QA", scope: try CorpusScope(folder: ""))
        let file = CorpusFile(path: "read.md", content: Data("# On-demand reader\n\nSynthetic reading content.\n\n## Later section\n\nNormal section spacing.".utf8))
        try await library.update(id: project.id, descriptor: project, catalogue: RemoteProjectCatalogue(files: [RemoteFileEntry(file: file)]))
        library.fetch = { _, _ in file }
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let priorWindow = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        window.frame = scene.coordinateSpace.bounds
        defer { window.isHidden = true; priorWindow?.makeKeyAndVisible() }
        window.rootViewController = UIHostingController(rootView: NavigationStack {
            RemoteDocumentPreview(library: library, projectID: project.id, entry: RemoteFileEntry(file: file),
                appearance: .leonardoClassic, compactFirstHeading: true)
                .classicSurface().navigationBarTitleDisplayMode(.inline)
        })
        window.makeKeyAndVisible()
        for _ in 0..<150 {
            if let web = findWebView(window), let values = try? await metrics(web) {
                XCTAssertEqual(try XCTUnwrap(values["headingTop"]), 16, accuracy: 1)
                XCTAssertGreaterThan(try XCTUnwrap(values["laterHeadingMargin"]), 0)
                let data = try JSONSerialization.data(withJSONObject: values, options: [.sortedKeys])
                let record = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
                record.name = "On-demand measured reader spacing"; record.lifetime = .keepAlways; add(record)
                attach(window, name: "On-demand synchronized document reader")
                return
            }
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTFail("The real on-demand preview did not render")
    }

    private func waitUntilReady(_ controller: MarkdownPreviewController) async throws {
        for _ in 0..<200 {
            if controller.isReady { return }
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTFail("The real WKWebView renderer did not become ready")
    }

    private func findWebView(_ view: UIView) -> WKWebView? {
        if let web = view as? WKWebView { return web }
        return view.subviews.lazy.compactMap(findWebView).first
    }

    private func metrics(_ web: WKWebView) async throws -> [String: Double] {
        let result = try await web.evaluateJavaScript("""
        (() => ({headingTop: document.querySelector('h1').getBoundingClientRect().top,
          laterHeadingMargin: parseFloat(getComputedStyle(document.querySelector('h2')).marginTop),
          scrollHeight: document.documentElement.scrollHeight, viewportHeight: window.innerHeight}))()
        """)
        return try XCTUnwrap(result as? [String: Double])
    }

    private func attach(_ window: UIWindow, name: String) {
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}

private actor ReaderSpacingCredentials: DeviceCredentialStore {
    func credential(deviceID: UUID) async throws -> String? { "synthetic-offline-credential" }
    func save(_ credential: String, deviceID: UUID) async throws {}
    func remove(deviceID: UUID) async throws {}
}
