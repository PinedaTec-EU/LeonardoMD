#if os(macOS)
import AppKit
import CryptoKit
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
        let projectOpened = await session.openProject(project)
        XCTAssertTrue(projectOpened)
        await session.openDocument(package)
        XCTAssertEqual(session.projectURL?.standardizedFileURL, project.standardizedFileURL)
        XCTAssertEqual(session.documentStorage, .package)
        try await assertWorkspaceAssetAndPDF(
            session: session,
            expectedAsset: packageAsset,
            expectedAssetPath: "assets/\(hash).svg"
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
            expectedAssetPath: "assets/\(hash).svg"
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
            expectedAssetPath: "assets/\(hash).svg"
        )
    }

    private func assertWorkspaceAssetAndPDF(
        session: AppSession,
        expectedAsset: Data,
        expectedAssetPath: String
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
        let pdf = try await host.exportPDF()
        XCTAssertTrue(try containsBlueAsset(in: pdf), "Exported PDF must render the blue extraction asset")
    }

    private func containsBlueAsset(in pdf: Data) throws -> Bool {
        let provider = try XCTUnwrap(CGDataProvider(data: pdf as CFData))
        let document = try XCTUnwrap(CGPDFDocument(provider))
        let page = try XCTUnwrap(document.page(at: 1))
        let bounds = page.getBoxRect(.mediaBox)
        let width = Int(bounds.width.rounded(.up))
        let height = Int(bounds.height.rounded(.up))
        let colorSpace = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let bitmap = try XCTUnwrap(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        ))
        bitmap.setFillColor(NSColor.white.cgColor)
        bitmap.fill(CGRect(x: 0, y: 0, width: width, height: height))
        bitmap.translateBy(x: -bounds.minX, y: -bounds.minY)
        bitmap.drawPDFPage(page)

        let pixels = try XCTUnwrap(bitmap.data).assumingMemoryBound(to: UInt8.self)
        for y in stride(from: 0, to: height, by: 2) {
            for x in stride(from: 0, to: width, by: 2) {
                let index = y * bitmap.bytesPerRow + x * 4
                if pixels[index] < 26 && pixels[index + 1] < 26 && pixels[index + 2] > 204 { return true }
            }
        }
        return false
    }

}
#endif
