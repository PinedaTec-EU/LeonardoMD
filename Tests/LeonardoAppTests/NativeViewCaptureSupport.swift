#if os(macOS)
import AppKit
import Foundation
import XCTest

/// Shared native AppKit capture harness for opt-in localization evidence.
///
/// A hosting view can change its intrinsic frame when it becomes a window's
/// content view. Reapply the requested window and view geometry after the
/// settling interval so the bitmap represents the requested capture bounds.
@MainActor
enum NativeViewCaptureSupport {
    static func capture(_ view: NSView,
                        size: NSSize,
                        to url: URL,
                        settlingMilliseconds: Int = 150,
                        title: String = "Leonardo Localization QA") async throws {
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.title = title
        window.isReleasedWhenClosed = false
        window.contentView = view
        window.contentView?.autoresizingMask = [.width, .height]
        window.setContentSize(size)

        let diagnoseGeometry = ProcessInfo.processInfo.environment["LEONARDO_LOCALIZATION_GEOMETRY"] != nil
        func reportGeometry(_ phase: String) {
            guard diagnoseGeometry else { return }
            let contentFrame = window.contentView?.frame ?? .zero
            print("[NativeViewCaptureSupport] capture=\(url.lastPathComponent) title=\(title) phase=\(phase) "
                  + "window=\(window.frame) contentFrame=\(contentFrame) viewFrame=\(view.frame) "
                  + "viewBounds=\(view.bounds) fitting=\(view.fittingSize) intrinsic=\(view.intrinsicContentSize)")
        }

        reportGeometry("attached")
        window.orderFront(nil)
        defer { window.close() }
        try await Task.sleep(for: .milliseconds(settlingMilliseconds))
        window.setContentSize(size)
        view.frame = NSRect(origin: .zero, size: size)
        view.bounds = NSRect(origin: .zero, size: size)
        view.layoutSubtreeIfNeeded()
        view.displayIfNeeded()
        reportGeometry("laid-out")
        let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        try png.write(to: url)
    }
}
#endif
