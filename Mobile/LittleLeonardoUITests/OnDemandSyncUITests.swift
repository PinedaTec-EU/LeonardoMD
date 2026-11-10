import XCTest
import UIKit

final class OnDemandSyncUITests: XCTestCase {
    @MainActor func testCatalogueContextRetentionAndSeparateCache() throws {
        guard ProcessInfo.processInfo.environment["LEONARDO_ON_DEMAND_QA_ROOT"] != nil else {
            throw XCTSkip("Requires the isolated on-demand loopback source")
        }
        defer { try? phase("finish") }
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.buttons["open-sync-settings"].waitForExistence(timeout: 15))
        app.buttons["open-sync-settings"].tap()
        try capture(app, "storage-initial", state: "Visible MiB label and explicit Apply action before editing")
        editLimit("128", app: app)
        XCTAssertTrue(app.buttons["apply-cache-limit"].waitForExistence(timeout: 5))
        app.buttons["apply-cache-limit"].tap()
        editLimit("64\n", app: app)
        editLimit("128\n", app: app)
        app.buttons["Cerrar"].tap()
        try enroll(app)
        try phase("assert-metadata")
        let project = app.staticTexts["QA · On-demand"].firstMatch
        project.tap()
        let remote = row("reference/remote.md", app: app)
        assertStatus(remote, "Solo remoto")
        try capture(app, "catalogue-remote", state: "Authenticated catalogue; no file body requested")
        row("reference/readme.md", app: app).tap()
        XCTAssertTrue(app.webViews.firstMatch.staticTexts["Cached reference"].waitForExistence(timeout: 15))
        let web = app.webViews.firstMatch
        let heading = web.staticTexts["Cached reference"].firstMatch
        XCTAssertGreaterThanOrEqual(heading.frame.minY - web.frame.minY, 0)
        XCTAssertLessThanOrEqual(heading.frame.minY - web.frame.minY, 40,
                                "The on-demand reader must preserve the accepted compact first-heading spacing")
        app.buttons["Ver texto"].tap()
        XCTAssertTrue(app.buttons["Ver documento"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "# Cached reference")).firstMatch.waitForExistence(timeout: 5))
        try capture(app, "document-source", state: "Read-only source and explicit Show document action; no extra download")
        app.buttons["Ver documento"].tap()
        XCTAssertTrue(app.webViews.firstMatch.staticTexts["Cached reference"].waitForExistence(timeout: 10))
        try phase("assert-single-file")
        try capture(app, "document", state: "One requested file rendered through compact Classic preview after source/preview round-trip")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        assertStatus(row("reference/readme.md", app: app), "En caché")
        let agenda = row("notes/agenda.md", app: app)
        agenda.press(forDuration: 1)
        XCTAssertTrue(app.buttons["Mantener sin conexión"].waitForExistence(timeout: 5))
        try capture(app, "context-menu", state: "Native long-press menu on a remote file")
        app.buttons["Mantener sin conexión"].tap()
        assertStatus(agenda, "Disponible sin conexión")
        let folder = app.descendants(matching: .any)["download-folder-notes"].firstMatch
        XCTAssertTrue(folder.waitForExistence(timeout: 5))
        folder.press(forDuration: 1)
        app.buttons["Mantener sin conexión"].tap()
        assertStatus(row("notes/decisions.md", app: app), "Offline pendiente")
        try capture(app, "catalogue-mixed", state: "Remote, cached, offline, partially retained and failed/pending download states")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["open-sync-settings"].tap()
        XCTAssertEqual(app.textFields["temporary-cache-limit"].value as? String, "128")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Sin conexión (separado)")).firstMatch.exists)
        try capture(app, "storage-separate", state: "128MiB temporary budget; retained folder and independent offline/pending accounting")
        app.buttons["clear-temporary-cache"].tap()
        try capture(app, "storage-cleared", state: "Temporary cleanup leaves retained content and its pending rule intact")
        app.buttons["Cerrar"].tap()
        project.tap()
        assertStatus(row("reference/readme.md", app: app), "Solo remoto")
        assertStatus(row("notes/agenda.md", app: app), "Disponible sin conexión")
        try phase("allow-pending")
        assertStatus(row("notes/decisions.md", app: app), "Disponible sin conexión", timeout: 80)
        assertStatus(row("notes/future.md", app: app), "Disponible sin conexión")
        try capture(app, "catalogue-recovered", state: "Automatic refresh retried the failed file and retained a future folder descendant without a manual sync")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        let ready = try JSONSerialization.jsonObject(with: Data(contentsOf: root().appendingPathComponent("ready.json"))) as? [String: Any]
        let projectID = try XCTUnwrap(ready?["projectID"] as? String)
        let received = app.buttons["open-project-" + projectID]
        XCTAssertTrue(received.waitForExistence(timeout: 10))
        try capture(app, "project-before-delete", state: "Received project remains an ordinary row in the same list as the local Demo project")
        received.swipeLeft()
        XCTAssertTrue(received.exists, "A swipe alone must not delete the received project")
        let delete = app.buttons["delete-project-" + projectID]
        XCTAssertTrue(delete.waitForExistence(timeout: 5))
        try capture(app, "project-swipe-delete", state: "Swipe reveals Delete; explicit button tap is still required")
        delete.tap()
        XCTAssertTrue(received.waitForNonExistence(timeout: 10))
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["open-sync-settings"].waitForExistence(timeout: 15))
        XCTAssertFalse(received.exists)
        app.buttons["Sincronizar"].firstMatch.tap()
        XCTAssertFalse(received.waitForExistence(timeout: 10), "Authorized refresh must not restore a locally removed project")
        XCTAssertTrue(app.buttons["open-demo-project"].exists)
        try capture(app, "project-deleted-after-refresh", state: "Received project stays absent after app relaunch and authenticated synchronization; local Demo remains")
    }

    @MainActor private func enroll(_ app: XCUIApplication) throws {
        app.buttons["open-pairing"].tap()
        app.segmentedControls["pairing-method"].buttons["IP y puerto"].tap()
        let host = app.textFields["pairing-host"], port = app.textFields["pairing-port"]
        host.tap(); host.typeText("127.0.0.1")
        port.tap()
        port.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: (port.value as? String)?.count ?? 0))
        port.typeText("46987")
        app.buttons["Solicitar conexión"].tap()
        let code = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Código de conexión:")).firstMatch
        guard code.waitForExistence(timeout: 15) else {
            try capture(app, "enrollment-failed", state: "Enrollment did not persist; diagnostic only, not accepted evidence")
            throw NSError(domain: "OnDemandFixture", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "The native app did not persist enrollment"])
        }
        try phase("approve")
        app.buttons["Sincronizar"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["QA · On-demand"].firstMatch.waitForExistence(timeout: 20))
    }

    @MainActor private func row(_ path: String, app: XCUIApplication) -> XCUIElement {
        app.buttons["download-file-" + path]
    }
    @MainActor private func editLimit(_ text: String, app: XCUIApplication) {
        let field = app.textFields["temporary-cache-limit"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        // LabeledContent exposes the whole labeled row as the text-field frame.
        // Target its trailing editable value rather than the label at row centre.
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.99, dy: 0.5)).tap()
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: (field.value as? String)?.count ?? 0))
        field.typeText(text)
    }
    @MainActor private func assertStatus(_ element: XCUIElement, _ status: String, timeout: TimeInterval = 15) {
        XCTAssertTrue(element.waitForExistence(timeout: timeout))
        let expected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", status), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [expected], timeout: timeout), .completed)
    }
    private func root() throws -> URL {
        URL(fileURLWithPath: try XCTUnwrap(ProcessInfo.processInfo.environment["LEONARDO_ON_DEMAND_QA_ROOT"]), isDirectory: true)
    }
    private func phase(_ value: String) throws {
        let root = try root()
        try Data(value.utf8).write(to: root.appendingPathComponent("phase.txt"), options: .atomic)
        let deadline = Date().addingTimeInterval(20)
        while Date() < deadline {
            if (try? String(contentsOf: root.appendingPathComponent("phase-applied.txt"), encoding: .utf8)) == value { return }
            Thread.sleep(forTimeInterval: 0.1)
        }
        throw NSError(domain: "OnDemandFixture", code: 1, userInfo: [NSLocalizedDescriptionKey: "Fixture did not apply " + value])
    }
    @MainActor private func capture(_ app: XCUIApplication, _ name: String, state: String) throws {
        let screenshot = app.screenshot()
        let capturedAt = ISO8601DateFormatter().string(from: Date())
        let destination = try root().appendingPathComponent("evidence", isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try screenshot.pngRepresentation.write(to: destination.appendingPathComponent(name + ".png"), options: .atomic)
        let context: [String: Any] = [
            "captured_at": capturedAt, "route": "/native/ios/on-demand/" + name, "screen": name,
            "browser_name": "Little Leonardo native SwiftUI/WKWebView · iOS Simulator " + UIDevice.current.systemVersion,
            "browser_version": "WKWebView engine version not exposed by XCTest",
            "viewport_css": NSNull(),
            "native_viewport_points": ["width": app.frame.width, "height": app.frame.height],
            "capture_mode": "viewport", "data_provenance": "synthetic",
            "source_sha": ProcessInfo.processInfo.environment["LEONARDO_QA_SOURCE_SHA"] ?? "unavailable",
            "state": state + "; native points measured from app.frame; Spanish; Classic appearance"
        ]
        try JSONSerialization.data(withJSONObject: context, options: [.prettyPrinted, .sortedKeys])
            .write(to: destination.appendingPathComponent(name + ".context.json"), options: .atomic)
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
