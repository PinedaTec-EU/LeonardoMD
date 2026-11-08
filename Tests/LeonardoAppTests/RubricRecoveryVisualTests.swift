import AppKit
import SwiftUI
import Vision
import XCTest
import LeonardoCore
import LeonardoSync
@testable import LeonardoApp

/// Production editor and controller; only the remote runtime and storage are synthetic.
@MainActor
final class RubricRecoveryVisualTests: XCTestCase {
    private let size = NSSize(width: 696, height: 820)

    func testNativeRecoveryErrorAndClosingStates() async throws {
        guard let path = ProcessInfo.processInfo.environment["LEONARDO_RUBRIC_RECOVERY_CAPTURE"] else {
            throw XCTSkip("Opt-in production rubric recovery captures")
        }
        let oldLanguage = LanguageSettings.shared.language
        defer { LanguageSettings.shared.language = oldLanguage }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        for language in AppLanguage.allCases {
            LanguageSettings.shared.language = language
            for scenario in ["recovery", "persistent", "closing"] {
                let output = URL(fileURLWithPath: path).appendingPathComponent(language.rawValue).appendingPathComponent(scenario)
                try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
                try await exercise(scenario, root: root.appendingPathComponent(language.rawValue + scenario),
                                   output: output, language: language.rawValue)
            }
        }
    }

    private func exercise(_ scenario: String, root: URL, output: URL, language: String) async throws {
        let now = Date(), requestID = UUID(), targetID = UUID(), ownerID = UUID()
        let document = root.appendingPathComponent("Synthetic.mdlf")
        let source = "# Synthetic rubric recovery"
        let pending = try LeonardoSync.RubricRequest(id: requestID, targetDeviceID: targetID,
            requesterID: ownerID, requesterName: "Synthetic Mac", labelHint: "Synthetic rubric", createdAt: now)
        var completed = pending
        completed.state = .completed
        let ink = LeonardoRubric(strokes: [.init(color: "#194D80", width: 5, style: .solid,
            points: [.init(x: 25, y: 140), .init(x: 100, y: 40), .init(x: 180, y: 130), .init(x: 530, y: 70)])])
        let response = try LeonardoSync.RubricResponse(requestID: requestID, targetDeviceID: targetID,
            requesterID: ownerID, label: "Synthetic rubric", rubric: ink, submittedAt: now)
        let store = RubricCaptureStore(url: root.appendingPathComponent("MobileSync/RubricCaptures/captures.json"), now: Date.init)
        try store.upsert(RubricCaptureRecord(id: requestID, targetDeviceID: targetID,
            targetDeviceName: "Synthetic iPhone", documentURL: document,
            sourceDigest: RubricCaptureRecord.digest(source: source), fieldID: nil,
            labelHint: pending.labelHint, request: pending, updatedAt: now))
        let runtime = RubricGuideCaptureRuntime(status: RubricExchangeStatus(request: completed, response: response),
            failingReads: scenario == "persistent" ? 4 : 1)
        let controller = DesktopSyncController(preferencesURL: root.appendingPathComponent("preferences.json"), runtime: runtime)
        let host = NSHostingView(rootView: AnyView(RubricEditor(
            request: RubricRequest(documentURL: document, source: source, fieldID: nil),
            library: RubricLibrary(url: root.appendingPathComponent("library.json")),
            syncController: controller) { _, _, _ in false }
            .frame(width: size.width, height: size.height)
            .background(Color(nsColor: .windowBackgroundColor)).preferredColorScheme(.light)))
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.title = "Synthetic rubric recovery"
        window.contentView = host
        window.orderFront(nil)
        defer { host.rootView = AnyView(EmptyView()); window.close() }
        try await waitUntil { await runtime.queryIDs.count == 1 }
        if scenario != "persistent" {
            let text = try await capture(host, output: output, name: "waiting-after-first-failure", language: language,
                state: "Production RubricEditor waiting after one synthetic failed status read; no Retry action")
            XCTAssertTrue(text.contains(L10n.text("Cancel request")), text)
            XCTAssertFalse(text.contains("Synthetic query unavailable"), text)
            XCTAssertFalse(text.contains(L10n.text("Retry")), text)
        }
        switch scenario {
        case "recovery":
            try await waitUntil { controller.rubricCapture(id: requestID)?.response != nil }
            let text = try await capture(host, output: output, name: "automatically-recovered", language: language,
                state: "Same production editor automatically displays returned rubric after second same-ID read; no button pressed")
            XCTAssertTrue(text.contains(L10n.text("Review received rubric")), text)
            XCTAssertTrue(text.contains(L10n.text("Save to library")), text)
            XCTAssertFalse(text.contains("Synthetic query unavailable"), text)
            XCTAssertEqual(controller.rubricCapture(id: requestID)?.response, response)
        case "persistent":
            try await waitUntil { await runtime.queryIDs.count == 4 }
            let text = try await capture(host, output: output, name: "persistent-error", language: language,
                state: "Production editor displays persistent original synthetic error and Retry after four failed same-ID reads")
            XCTAssertTrue(text.contains("Synthetic query unavailable"), text)
            XCTAssertTrue(text.contains(L10n.text("Retry")), text)
            XCTAssertNil(controller.rubricCapture(id: requestID)?.response)
        default:
            // Removing the editor exercises its real onDisappear cancellation.
            host.rootView = AnyView(EmptyView())
            try await Task.sleep(for: .milliseconds(100))
            window.close()
            try await Task.sleep(for: .milliseconds(1200))
            let closedReads = await runtime.queryIDs.count
            XCTAssertEqual(closedReads, 1, "Closed editor must not retry or receive")
            XCTAssertNil(controller.rubricCapture(id: requestID)?.response)
        }
        let queries = await runtime.queryIDs
        let creations = await runtime.creations
        XCTAssertTrue(queries.allSatisfy { $0 == requestID })
        XCTAssertEqual(creations, 0, "UI recovery must never recreate a request")
        let trace: [String: Any] = ["scenario": scenario, "language": language,
            "source_sha": ProcessInfo.processInfo.environment["EVIDENCE_SHA"] ?? "local",
            "test_process_id": ProcessInfo.processInfo.processIdentifier,
            "build": "SwiftPM debug XCTest component; source version 0.3.1127",
            "queries": queries.map(\.uuidString), "original_request_id": requestID.uuidString,
            "create_calls": creations, "manual_retry_actions": 0,
            "response_received": controller.rubricCapture(id: requestID)?.response != nil,
            "packaged_process_acceptance": false, "physical_device_acceptance": false]
        try JSONSerialization.data(withJSONObject: trace, options: [.prettyPrinted, .sortedKeys])
            .write(to: output.appendingPathComponent("transition.json"))
    }

    private func waitUntil(_ condition: () async -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(8))
        while !(await condition()) {
            guard ContinuousClock.now < deadline else { throw XCTUnwrapError.timeout }
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    private enum XCTUnwrapError: Error { case timeout }

    private func capture(_ host: NSView, output: URL, name: String, language: String, state: String) async throws -> String {
        try await Task.sleep(for: .milliseconds(200))
        host.frame = NSRect(origin: .zero, size: size)
        host.bounds = NSRect(origin: .zero, size: size)
        host.layoutSubtreeIfNeeded()
        host.display()
        let image = output.appendingPathComponent(name + ".png")
        let context: [String: Any] = ["captured_at": ISO8601DateFormatter().string(from: Date()),
            "route": "/native/rubric-recovery/\(language)/\(name)", "screen": "Production RubricEditor",
            "browser_name": "Native AppKit NSHostingView", "browser_version": "N/A native component",
            "viewport_css": ["width": Int(host.bounds.width), "height": Int(host.bounds.height)],
            "capture_mode": "element", "data_provenance": "synthetic", "state": state + "; language " + language,
            "source_sha": ProcessInfo.processInfo.environment["EVIDENCE_SHA"] ?? "local",
            "os": ProcessInfo.processInfo.operatingSystemVersionString]
        try NativeViewCaptureSupport.writeBitmap(host, size: size, to: image, pixelScale: 2)
        try JSONSerialization.data(withJSONObject: context, options: [.prettyPrinted, .sortedKeys])
            .write(to: image.deletingPathExtension().appendingPathExtension("context.json"))
        let recognition = VNRecognizeTextRequest()
        recognition.recognitionLevel = .accurate
        recognition.usesLanguageCorrection = false
        try VNImageRequestHandler(url: image).perform([recognition])
        return (recognition.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
    }
}
