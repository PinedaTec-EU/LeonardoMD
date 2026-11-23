#if os(macOS)
import AppKit
import LeonardoCore
import WebKit
import XCTest
@testable import LeonardoRender

/// Opt-in native component QA, run by XCTest rather than a standalone QA executable.
@MainActor
final class MarkdownImageContextVisualTests: XCTestCase {
    func testPackageImageOpenSaveAndCancel() async throws {
        guard let directory = ProcessInfo.processInfo.environment["LEONARDO_IMAGE_EVIDENCE"] else {
            throw XCTSkip("Set LEONARDO_IMAGE_EVIDENCE for native image-window/save-panel QA")
        }
        _ = NSApplication.shared
        let output = URL(fileURLWithPath: directory, isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let bytes = try fixturePNG()
        try bytes.write(to: root.appendingPathComponent("image.png"))
        let text = try LeonardoFormatParser.serialize(LeonardoDocument(body: "# Image actions\n\n![Test landscape](image.png)"))
        let document = root.appendingPathComponent("image-actions.mdlf")
        let package = root.appendingPathComponent("image-actions.mdlz")
        try LeonardoPackageTransport.export(documentURL: document, content: text, to: package)
        let workspace = try LeonardoPackageTransport.open(package)
        defer { LeonardoPackageTransport.discard(workspace) }
        let host = MarkdownPreviewHost(frame: NSRect(x: 0, y: 0, width: 900, height: 640))
        let window = NSWindow(contentRect: host.bounds, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.title = "Image actions — native component QA"
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        defer { host.teardown(); window.close() }
        var config = MarkdownPreviewConfiguration(localAssetRoot: workspace.directoryURL)
        config.allowsLeonardoFormat = true
        host.apply(content: try String(contentsOf: workspace.documentURL, encoding: .utf8),
            baseURL: workspace.documentURL.deletingLastPathComponent(), configuration: config,
            onLinkActivation: nil, onScrollProgress: nil)
        let web = try XCTUnwrap(host.subviews.first as? MarkdownImageWebView)
        try await waitUntil {
            (try? await web.evaluateJavaScript("!!document.querySelector('img')?.naturalWidth")) as? Bool == true
        }
        _ = try await web.evaluateJavaScript("document.querySelector('img').dispatchEvent(new MouseEvent('contextmenu', {bubbles:true}))")
        let imageURL = try await web.contextImageURL()
        XCTAssertEqual(imageURL.scheme, "leonardo-document")
        try await captureWeb(web, output: output)
        let menu = menuForImage(web)
        invoke(menu.items[0], target: web)
        var opened: NSWindow?
        try await waitUntil {
            opened = NSApp.windows.first { $0.isVisible && $0.title == imageURL.lastPathComponent }
            return opened != nil
        }
        let imageWindow = try XCTUnwrap(opened)
        defer { imageWindow.close() }
        XCTAssertTrue(imageWindow.contentView is NSImageView)
        try await capture(try XCTUnwrap(imageWindow.contentView), name: "opened-image", output: output)
        web.makeSavePanel = {
            let panel = NSSavePanel()
            panel.directoryURL = root
            return panel
        }
        invoke(menu.items[1], target: web)
        try await waitUntil { window.attachedSheet is NSSavePanel }
        let save = try XCTUnwrap(window.attachedSheet as? NSSavePanel)
        defer { if save.isVisible { save.cancel(nil) } }
        XCTAssertEqual(save.nameFieldStringValue, imageURL.lastPathComponent)
        try await capture(try XCTUnwrap(save.contentView), name: "save-image-sheet", output: output)
        let destination = root.appendingPathComponent(imageURL.lastPathComponent)
        guard save.url == destination else {
            save.cancel(nil)
            XCTFail("Save panel must select the disposable test destination")
            return
        }
        // Drive the supported sheet lifecycle and exercise the production save completion.
        window.endSheet(save, returnCode: .OK)
        try await waitUntil { FileManager.default.fileExists(atPath: destination.path) }
        XCTAssertEqual(try Data(contentsOf: destination), bytes)
        try await waitUntil { window.attachedSheet == nil }
        invoke(menu.items[1], target: web)
        try await waitUntil { window.attachedSheet is NSSavePanel }
        let cancel = try XCTUnwrap(window.attachedSheet as? NSSavePanel)
        let beforeCancel = try FileManager.default.contentsOfDirectory(atPath: root.path).sorted()
        DispatchQueue.main.async { cancel.cancel(nil) }
        try await waitUntil { window.attachedSheet == nil }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path).sorted(), beforeCancel)
        XCTAssertEqual(try Data(contentsOf: destination), bytes)
    }

    private func menuForImage(_ web: MarkdownImageWebView) -> NSMenu {
        let menu = NSMenu()
        for (title, tag) in [("Open Image in New Window", WebMenuItemTagOpenImageInNewWindow),
                             ("Download Image", WebMenuItemTagDownloadImageToDisk),
                             ("Copy Image", WebMenuItemTagCopyImageToClipboard)] {
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            item.tag = tag
            menu.addItem(item)
        }
        let event = NSEvent.mouseEvent(with: .rightMouseDown, location: .zero, modifierFlags: [],
            timestamp: 0, windowNumber: 0, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
        web.willOpenMenu(menu, with: event)
        return menu
    }

    private func invoke(_ item: NSMenuItem, target: AnyObject) {
        XCTAssertNotNil(item.action)
        if let action = item.action { XCTAssertTrue(NSApp.sendAction(action, to: target, from: item)) }
    }

    private func waitUntil(_ condition: () async throws -> Bool) async throws {
        for _ in 0..<150 {
            if try await condition() { return }
            try await Task.sleep(for: .milliseconds(40))
        }
        XCTFail("Native image action did not reach its expected state")
        throw CocoaError(.executableRuntimeMismatch)
    }

    private func fixturePNG() throws -> Data {
        let image = NSImage(size: NSSize(width: 720, height: 360), flipped: false) { rect in
            NSColor(calibratedRed: 0.08, green: 0.15, blue: 0.25, alpha: 1).setFill()
            rect.fill()
            NSColor(calibratedRed: 0.95, green: 0.65, blue: 0.25, alpha: 1).setFill()
            NSBezierPath(ovalIn: NSRect(x: 540, y: 220, width: 70, height: 70)).fill()
            NSColor(calibratedRed: 0.20, green: 0.52, blue: 0.48, alpha: 1).setFill()
            let landscape = NSBezierPath()
            landscape.move(to: .zero)
            for point in [NSPoint(x: 140, y: 210), NSPoint(x: 330, y: 90),
                          NSPoint(x: 460, y: 190), NSPoint(x: 720, y: 0)] { landscape.line(to: point) }
            landscape.close()
            landscape.fill()
            ("MDLZ image resource" as NSString).draw(at: NSPoint(x: 28, y: 300),
                withAttributes: [.font: NSFont.systemFont(ofSize: 28, weight: .semibold), .foregroundColor: NSColor.white])
            return true
        }
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: try XCTUnwrap(image.tiffRepresentation)))
        return try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
    }

    private func captureWeb(_ web: WKWebView, output: URL) async throws {
        let image: NSImage = try await withCheckedThrowingContinuation { continuation in
            web.takeSnapshot(with: nil) { image, error in
                if let image { continuation.resume(returning: image) }
                else { continuation.resume(throwing: error ?? CocoaError(.fileReadUnknown)) }
            }
        }
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: try XCTUnwrap(image.tiffRepresentation)))
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: output.appendingPathComponent("package-preview.png"))
        try writeContext(web, name: "package-preview", output: output)
    }

    private func capture(_ view: NSView, name: String, output: URL) async throws {
        try await Task.sleep(for: .milliseconds(400))
        view.layoutSubtreeIfNeeded()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-x", "-l", String(try XCTUnwrap(view.window).windowNumber),
                             output.appendingPathComponent(name + ".png").path]
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
        try writeContext(view, name: name, output: output)
    }

    private func writeContext(_ view: NSView, name: String, output: URL) throws {
        let viewport = view.window?.sheetParent?.contentView?.bounds ?? view.bounds
        let context: [String: Any] = [
            "captured_at": ISO8601DateFormatter().string(from: Date()),
            "route": "native/image-context/" + name, "screen": name,
            "browser_name": "Native AppKit/WKWebView component (no standalone application)",
            "browser_version": "Not applicable; native component",
            "viewport_css": ["width": viewport.width, "height": viewport.height],
            "capture_mode": "element", "state": "Actual MDLZ image action; synthetic landscape; native viewport in points; no CSS viewport",
            "data_provenance": "synthetic"
        ]
        try JSONSerialization.data(withJSONObject: context, options: [.prettyPrinted, .sortedKeys])
            .write(to: output.appendingPathComponent(name + ".context.json"))
    }
}
#endif
