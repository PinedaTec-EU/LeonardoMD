#if os(macOS)
import AppKit
import CryptoKit
import PDFKit
import WebKit
import XCTest
import LeonardoCore
@testable import LeonardoApp
@testable import LeonardoRender

@MainActor
final class SessionRenderingPackageAssetTests: XCTestCase {
    func testPackageAndExtractedPreviewsUseTheirWorkspaceAssetsWithActiveProject() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("LeonardoPackageAssets-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let project = root.appendingPathComponent("Project", isDirectory: true)
        let input = root.appendingPathComponent("package-input", isDirectory: true)
        try FileManager.default.createDirectory(at: project.appendingPathComponent("assets"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: input.appendingPathComponent("assets"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let projectAsset = Data(#"<svg xmlns="http://www.w3.org/2000/svg" width="10" height="10"><rect width="10" height="10" fill="red"/></svg>"#.utf8)
        let packageAsset = Data(#"<svg xmlns="http://www.w3.org/2000/svg" width="10" height="10"><rect width="10" height="10" fill="blue"/></svg>"#.utf8)
        try projectAsset.write(to: project.appendingPathComponent("assets/logo.svg"), options: .atomic)
        try packageAsset.write(to: input.appendingPathComponent("assets/logo.svg"), options: .atomic)

        let template = input.appendingPathComponent("request.mdlf")
        let package = project.appendingPathComponent("request.mdlz")
        let document = LeonardoDocument(
            body: "# Request\n\n![Logo](assets/logo.svg)",
            metadata: LeonardoMetadata(document: LeonardoDocumentDescriptor(title: "Request", kind: .form))
        )
        let source = try LeonardoFormatParser.serialize(document)
        try source.write(to: template, atomically: true, encoding: .utf8)
        try LeonardoPackageTransport.export(documentURL: template, content: source, to: package)

        // Package export names assets by content hash. Put a different asset
        // at that exact path in the active project so a project-root fallback
        // cannot accidentally make this test pass.
        let hash = SHA256.hash(data: packageAsset).prefix(8)
            .map { String(format: "%02x", $0) }.joined()
        let conflictingPackagedName = project.appendingPathComponent("assets/\(hash).svg")
        try projectAsset.write(to: conflictingPackagedName, options: .atomic)

        let tabs = DocumentTabs(preferencesURL: root.appendingPathComponent("preferences.json"))
        let session = tabs.activeSession
        session.authorizePath = { _, _ in }
        defer { tabs.stop() }
        let evidenceDirectory: URL?
        if let evidencePath = ProcessInfo.processInfo.environment["LEONARDO_VISUAL_EVIDENCE"] {
            let directory = URL(fileURLWithPath: evidencePath, isDirectory: true)
                .appendingPathComponent("package-assets", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            evidenceDirectory = directory
        } else {
            evidenceDirectory = nil
        }
        let projectOpened = await session.openProject(project)
        XCTAssertTrue(projectOpened)
        await session.openDocument(package)
        XCTAssertEqual(session.projectURL?.standardizedFileURL, project.standardizedFileURL)
        XCTAssertEqual(session.documentStorage, .package)
        try await assertWorkspaceAssetAndPDF(
            session: session,
            expectedAsset: packageAsset,
            expectedAssetPath: "assets/\(hash).svg",
            state: "package",
            evidenceDirectory: evidenceDirectory
        )

        let oldWorkspace = try XCTUnwrap(session.packageWorkspace)
        let extraction = root.appendingPathComponent("extracted", isDirectory: true)
        let extracted = await session.openLeonardoPackage(package, extractingTo: extraction)
        XCTAssertTrue(extracted)
        LeonardoPackageTransport.discard(oldWorkspace)
        XCTAssertEqual(session.documentStorage, .extracted)
        XCTAssertEqual(session.projectURL?.standardizedFileURL, project.standardizedFileURL)
        try await assertWorkspaceAssetAndPDF(
            session: session,
            expectedAsset: packageAsset,
            expectedAssetPath: "assets/\(hash).svg",
            state: "extracted",
            evidenceDirectory: evidenceDirectory
        )
        let extractedDocument = try XCTUnwrap(session.documentURL)
        let editedSource = try String(contentsOf: extractedDocument, encoding: .utf8) + "\n\nEdited in the extraction.\n"
        try editedSource.write(to: extractedDocument, atomically: true, encoding: .utf8)
        let archiveBeforeQuit = try Data(contentsOf: package)
        let store = SessionRestoration(preferencesURL: root.appendingPathComponent("preferences.json"))
        let closeApproved = await tabs.prepareClose()
        XCTAssertTrue(closeApproved)
        try store.save(SavedSession(windows: [tabs.savedWindow]))
        await tabs.finishPreparedClose()
        let saved = try XCTUnwrap(store.load(restorePreviousSession: true, explicitURLs: []).flatMap { $0.windows.first })

        let restored = DocumentTabs(preferencesURL: root.appendingPathComponent("preferences.json"))
        defer { restored.stop() }
        await restored.restore(saved, initialTabID: try XCTUnwrap(restored.activeID))
        let reopened = restored.activeSession
        XCTAssertEqual(reopened.projectURL?.standardizedFileURL, project.standardizedFileURL)
        XCTAssertEqual(reopened.documentURL?.standardizedFileURL, extractedDocument.standardizedFileURL)
        XCTAssertEqual(reopened.documentStorage, .extracted)
        XCTAssertEqual(reopened.content, editedSource)
        XCTAssertEqual(try Data(contentsOf: package), archiveBeforeQuit)
        try await assertWorkspaceAssetAndPDF(
            session: reopened,
            expectedAsset: packageAsset,
            expectedAssetPath: "assets/\(hash).svg",
            state: "restored-extraction",
            evidenceDirectory: evidenceDirectory
        )
        if let evidenceDirectory {
            let context = """
            Surface: actual MarkdownPreviewHost/WKWebView using AppSession.renderConfiguration
            States: package, extracted workspace and restored extraction with the same active project
            Viewport: 800x600 points
            Project conflict: assets/logo.svg and assets/\(hash).svg are red
            Package asset: assets/\(hash).svg is blue and is loaded from the workspace root
            Preview and PDF: both use the captured renderConfiguration.localAssetRoot
            Active project: \(project.path)
            Package source: \(package.path)
            Provenance head: \(ProcessInfo.processInfo.environment["EVIDENCE_SHA"] ?? ProcessInfo.processInfo.environment["GITHUB_SHA"] ?? ProcessInfo.processInfo.environment["CI_COMMIT_SHA"] ?? "unknown")
            Evidence root: \(evidenceDirectory.path)
            """
            try context.write(to: evidenceDirectory.appendingPathComponent("capture-context.txt"), atomically: true, encoding: .utf8)
        }
    }

    private func assertWorkspaceAssetAndPDF(
        session: AppSession,
        expectedAsset: Data,
        expectedAssetPath: String,
        state: String,
        evidenceDirectory: URL?
    ) async throws {
        let configuration = session.renderConfiguration
        let workspaceRoot = try XCTUnwrap(session.packageWorkspace?.directoryURL)
        XCTAssertEqual(configuration.localAssetRoot?.standardizedFileURL, workspaceRoot.standardizedFileURL)
        let documentURL = try XCTUnwrap(session.documentURL)
        let requestURL = try XCTUnwrap(URL(string: "leonardo-document://local/\(expectedAssetPath)"))
        let resolved = MarkdownDocumentSchemeHandler.resolvedFileURL(
            baseDirectory: documentURL.deletingLastPathComponent(),
            assetRoot: configuration.localAssetRoot,
            requestURL: requestURL
        )
        XCTAssertEqual(try Data(contentsOf: try XCTUnwrap(resolved)), expectedAsset)

        let host = MarkdownPreviewHost(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderFront(nil)
        defer { host.teardown(); window.close() }

        let ready = expectation(description: "Package preview ready")
        host.onReady = { if $0 { ready.fulfill() } }
        host.apply(
            content: session.content,
            baseURL: documentURL.deletingLastPathComponent(),
            configuration: configuration,
            onLinkActivation: nil,
            onScrollProgress: nil
        )
        await fulfillment(of: [ready], timeout: 10)
        let webView = try XCTUnwrap(host.subviews.compactMap { $0 as? WKWebView }.first)
        var imageLoaded = false
        for _ in 0..<100 {
            let state = try await webView.evaluateJavaScript("""
            (() => {
                const image = document.querySelector('img');
                return image ? {src: image.currentSrc, complete: image.complete, width: image.naturalWidth, height: image.naturalHeight} : null;
            })()
            """) as? [String: Any]
            if let state,
               state["complete"] as? Bool == true,
               let width = (state["width"] as? NSNumber)?.doubleValue,
               width > 0 {
                imageLoaded = true
                break
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertTrue(imageLoaded, "The package image must decode in the preview WKWebView")
        let source = try await webView.evaluateJavaScript("document.querySelector('img')?.currentSrc") as? String
        XCTAssertTrue(source?.contains(expectedAssetPath) == true)
        if let evidenceDirectory {
            try await captureSnapshot(
                webView,
                to: evidenceDirectory.appendingPathComponent("\(state).png")
            )
        }
        let pdf = try await host.exportPDF()
        let page = try XCTUnwrap(PDFDocument(data: pdf)?.page(at: 0))
        let image = page.thumbnail(of: NSSize(width: 800, height: 1_000), for: .mediaBox)
        let tiff = try XCTUnwrap(image.tiffRepresentation)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: tiff))
        XCTAssertTrue(containsBlueAsset(in: bitmap), "Exported PDF must render the blue extraction asset")
    }

    private func containsBlueAsset(in bitmap: NSBitmapImageRep) -> Bool {
        for y in stride(from: 0, to: bitmap.pixelsHigh, by: 2) {
            for x in stride(from: 0, to: bitmap.pixelsWide, by: 2) {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                if color.blueComponent > 0.8 && color.redComponent < 0.1 && color.greenComponent < 0.1 {
                    return true
                }
            }
        }
        return false
    }

    private func captureSnapshot(_ webView: WKWebView, to url: URL) async throws {
        let configuration = WKSnapshotConfiguration()
        configuration.rect = webView.bounds
        let image = try await webView.takeSnapshot(configuration: configuration)
        let tiff = try XCTUnwrap(image.tiffRepresentation)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: tiff))
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        try png.write(to: url, options: .atomic)
    }
}
#endif
