import AppKit
import Foundation
import WebKit
import XCTest

/// Capture observations alongside the pixels. The shared metadata CLI can then
/// bind the original context and image without reconstructing capture-time facts.
@MainActor
enum GuideCaptureSupport {
    static func capture(_ web: WKWebView, to url: URL, language: String, state: String) async throws {
        let result = try await web.evaluateJavaScript("""
            ({width: innerWidth, height: innerHeight, userAgent: navigator.userAgent,
              devicePixelRatio: devicePixelRatio})
            """)
        let observed = try XCTUnwrap(result as? [String: Any])
        var context = baseContext(language: language, state: state)
        context["browser_name"] = "Native WKWebView; User-Agent reports engine compatibility versions"
        context["browser_version"] = try XCTUnwrap(observed["userAgent"] as? String)
        context["viewport_css"] = ["width": try XCTUnwrap(observed["width"] as? NSNumber).intValue,
                                   "height": try XCTUnwrap(observed["height"] as? NSNumber).intValue]
        context["device_pixel_ratio"] = observed["devicePixelRatio"]
        context["native_viewport_points"] = ["width": web.bounds.width, "height": web.bounds.height]
        context["captured_at"] = timestamp()
        let image = try await web.takeSnapshot(configuration: nil)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: XCTUnwrap(image.tiffRepresentation)))
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: url)
        try write(context, beside: url)
    }

    static func captureWelcome(_ view: NSView, size: NSSize, to url: URL, language: String) async throws {
        try await captureNative(view, size: size, to: url, language: language,
                                state: "Welcome; synthetic empty saved items")
    }

    static func captureNative(_ view: NSView, size: NSSize, to url: URL,
                              language: String, state: String) async throws {
        view.appearance = NSAppearance(named: .aqua)
        var context = baseContext(language: language, state: state)
        try await NativeViewCaptureSupport.capture(view, size: size, to: url, beforeCapture: { capturedView in
            let bounds = capturedView.bounds.size
            context["captured_at"] = timestamp()
            context["browser_name"] = "Native AppKit / SwiftUI NSHostingView"
            context["browser_version"] = "Not applicable: native view, no browser engine"
            context["native_viewport_points"] = ["width": bounds.width, "height": bounds.height]
            // The shared browser-oriented schema requires this field. For a
            // native view use its measured point equivalent, explicitly labeled.
            context["viewport_css"] = ["width": Int(bounds.width), "height": Int(bounds.height)]
            context["state"] = state + "; viewport_css is the measured native-point equivalent; CSS is not applicable"
        })
        try write(context, beside: url)
    }

    private static func baseContext(language: String, state: String) -> [String: Any] {
        ["route": "/native/user-guide/\(language)", "screen": "Leonardo guide: \(state)",
         "state": "\(state); language \(language)", "capture_mode": "element",
         "data_provenance": "synthetic",
         "source_sha": ProcessInfo.processInfo.environment["EVIDENCE_SHA"] ?? "local",
         "os": ProcessInfo.processInfo.operatingSystemVersionString]
    }

    private static func timestamp() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: Date())
    }

    private static func write(_ context: [String: Any], beside image: URL) throws {
        try JSONSerialization.data(withJSONObject: context, options: [.prettyPrinted, .sortedKeys])
            .write(to: image.deletingPathExtension().appendingPathExtension("context.json"))
    }
}
