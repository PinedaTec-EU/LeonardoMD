import Foundation
import Testing
import WebKit
@testable import LeonardoRender
#if os(macOS)
import AppKit
#endif

@Suite(.serialized)
@MainActor
struct MarkdownImageActionsTests {
    @Test func exportsOriginalMemoryBytesAndRejectsMissingAssets() async throws {
        let original = Data("original image bytes".utf8)
        let handler = MarkdownDocumentSchemeHandler(baseURL: nil,
            memoryAssets: MarkdownMemoryAssets(files: ["assets/photo.png": original]))
        let url = URL(string: "leonardo-document://local/assets/photo.png?leonardo-image-purpose=pdf")!
        #expect(try await handler.originalImageData(for: url) == original)
        await #expect(throws: (any Error).self) {
            try await handler.originalImageData(for: URL(string: "leonardo-document://local/missing.png")!)
        }
        await #expect(throws: (any Error).self) {
            try await handler.originalImageData(for: URL(string: "https://example.com/assets/photo.png")!)
        }
    }

    @Test func exportsOriginalLocalBytesAndRejectsEscape() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let bytes = Data("unaltered original".utf8)
        try bytes.write(to: root.appendingPathComponent("photo.png"))
        let handler = MarkdownDocumentSchemeHandler(baseURL: root, assetRootURL: root)
        #expect(try await handler.originalImageData(for: URL(string: "leonardo-document://local/photo.png")!) == bytes)
        await #expect(throws: (any Error).self) {
            try await handler.originalImageData(for: URL(string: "leonardo-document://local/%2e%2e/outside.png")!)
        }
    }

    @Test func originalExportEnforcesInputLimit() async throws {
        var policy = MarkdownImagePolicy.standard
        policy.maximumInputBytes = 4
        let handler = MarkdownDocumentSchemeHandler(baseURL: nil,
            memoryAssets: MarkdownMemoryAssets(files: ["large.png": Data(repeating: 1, count: 5)]), policy: policy)
        await #expect(throws: MarkdownImageError.inputTooLarge) {
            try await handler.originalImageData(for: URL(string: "leonardo-document://local/large.png")!)
        }
    }

    #if os(macOS)
    @Test func isolatedContextCaptureOpensActualImageWindow() async throws {
        _ = NSApplication.shared
        let web = MarkdownImageWebView(frame: NSRect(x: 0, y: 0, width: 400, height: 300),
                                       configuration: WKWebViewConfiguration())
        let source = "leonardo-document://local/photo.png"
        let image = NSImage(size: NSSize(width: 10, height: 10), flipped: false) { rect in
            NSColor.red.setFill()
            rect.fill()
            return true
        }
        let bytes = try #require(image.tiffRepresentation)
        var requested: URL?
        web.imageWindowData = { url in requested = url; return bytes }
        web.loadHTMLString("<img id='photo' src='\(source)'>", baseURL: nil)
        var captured: URL?
        for _ in 0..<100 {
            _ = try? await web.evaluateJavaScript("document.getElementById('photo')?.dispatchEvent(new MouseEvent('contextmenu', {bubbles:true}))")
            captured = try? await web.contextImageURL()
            if captured != nil { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(captured?.absoluteString == source)
        // Page code cannot replace the captured value in the isolated world.
        _ = try await web.evaluateJavaScript("window.leonardoContextImage = 'file:///etc/passwd'")
        #expect(try await web.contextImageURL().absoluteString == source)
        let menu = NSMenu()
        let item = NSMenuItem(title: "Open", action: nil, keyEquivalent: "")
        item.tag = WebMenuItemTagOpenImageInNewWindow
        menu.addItem(item)
        let event = NSEvent.mouseEvent(with: .rightMouseDown, location: .zero,
            modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
            eventNumber: 1, clickCount: 1, pressure: 1)!
        web.willOpenMenu(menu, with: event)
        let action = try #require(menu.items[0].action)
        #expect(NSApp.sendAction(action, to: web, from: menu.items[0]))
        var opened: NSWindow?
        for _ in 0..<100 {
            opened = NSApp.windows.first { $0.title == "photo.png" && $0.isVisible }
            if opened != nil { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        defer { opened?.close() }
        #expect(requested?.absoluteString == source)
        #expect(opened?.contentView is NSImageView)
    }

    @Test func rewiresOnlyBrokenImageMenuActions() {
        let web = MarkdownImageWebView(frame: .zero, configuration: WKWebViewConfiguration())
        let menu = NSMenu()
        let open = NSMenuItem(title: "Open", action: nil, keyEquivalent: "")
        open.tag = WebMenuItemTagOpenImageInNewWindow
        let save = NSMenuItem(title: "Save", action: nil, keyEquivalent: "")
        save.tag = WebMenuItemTagDownloadImageToDisk
        let copy = NSMenuItem(title: "Copy", action: nil, keyEquivalent: "")
        copy.tag = WebMenuItemTagCopyImageToClipboard
        [open, save, copy].forEach { menu.addItem($0) }
        let event = NSEvent.mouseEvent(with: .rightMouseDown, location: .zero,
            modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
            eventNumber: 1, clickCount: 1, pressure: 1)!
        web.willOpenMenu(menu, with: event)
        #expect(menu.items.count == 3)
        #expect(menu.items[0].target === web)
        #expect(menu.items[1].target === web)
        #expect(menu.items[0].representedObject as? NSMenuItem === open)
        #expect(menu.items[2] === copy)
    }
    #endif
}
