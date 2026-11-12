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
        editLimit("128", app: app)
        XCTAssertTrue(app.buttons["apply-cache-limit"].waitForExistence(timeout: 5))
        app.buttons["apply-cache-limit"].tap()
        editLimit("64\n", app: app)
        editLimit("128\n", app: app)
        app.buttons["Cerrar"].tap()
        try enroll(app)

        let projectID = try readyProjectID()
        let hosts = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "shared-host-"))
        XCTAssertTrue(hosts.firstMatch.waitForExistence(timeout: 15), "The connected Mac must appear as a host group")
        let incoming = element("incoming-project-" + projectID, app: app)
        let addProject = incoming.buttons["Añadir"]
        var foundPendingProject = addProject.isHittable
        for index in 0..<hosts.count where !foundPendingProject {
            let candidate = hosts.element(boundBy: index)
            guard candidate.isHittable else { continue }
            candidate.tap()
            foundPendingProject = addProject.waitForExistence(timeout: 5) && addProject.isHittable
        }
        XCTAssertTrue(foundPendingProject, "The newly granted project must be visible under its connected host")
        try capture(app, "incoming-project", state: "New project is grouped under its connected host and awaits Add or Ignore")
        XCTAssertTrue(addProject.isHittable)
        XCTAssertTrue(incoming.buttons["Ignorar"].exists)
        addProject.tap()
        let project = element("shared-project-" + projectID, app: app)
        XCTAssertTrue(project.waitForExistence(timeout: 20), "Adding must reveal the expandable project row")
        try phase("assert-metadata")
        project.tap()
        let remote = fileRow(projectID, "reference/remote.md", app: app)
        assertStatus(remote, "Solo remoto")
        try capture(app, "catalogue-remote", state: "Added project shows its host hierarchy and catalogue without fetching file bodies")

        fileRow(projectID, "reference/readme.md", app: app).tap()
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
        try capture(app, "document", state: "One explicitly opened file rendered through compact Classic preview")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        assertStatus(fileRow(projectID, "reference/readme.md", app: app), "En caché")

        let agenda = fileRow(projectID, "notes/agenda.md", app: app)
        let agendaMenu = element("shared-file-actions-" + projectID + "-notes/agenda.md", app: app)
        XCTAssertTrue(agendaMenu.waitForExistence(timeout: 10))
        agendaMenu.tap()
        XCTAssertTrue(app.buttons["Mantener sin conexión"].waitForExistence(timeout: 5))
        try capture(app, "context-menu", state: "File ellipsis menu exposes offline retention and local-space release")
        app.buttons["Mantener sin conexión"].tap()
        assertStatus(agenda, "Disponible sin conexión")

        let projectMenu = element("shared-project-actions-" + projectID, app: app)
        projectMenu.tap()
        XCTAssertTrue(app.buttons["Mantener sin conexión"].waitForExistence(timeout: 5))
        app.buttons["Mantener sin conexión"].tap()
        XCTAssertTrue(element("remote-file-download-failure-" + projectID + "-notes/decisions.md", app: app)
            .waitForExistence(timeout: 15), "A failed retained download must be visible on its file row")
        try capture(app, "catalogue-mixed", state: "Project retention downloads current files and applies to future files; pending transfer remains visible")

        app.buttons["open-sync-settings"].tap()
        XCTAssertEqual(app.textFields["temporary-cache-limit"].value as? String, "128")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Sin conexión (separado)")).firstMatch.exists)
        try capture(app, "storage-separate", state: "128MiB temporary budget; retained project and independent offline/pending accounting")
        app.buttons["clear-temporary-cache"].tap()
        try capture(app, "storage-cleared", state: "Temporary cleanup leaves retained content and its project rule intact")
        app.buttons["Cerrar"].tap()
        assertStatus(fileRow(projectID, "reference/readme.md", app: app), "Disponible sin conexión")
        assertStatus(fileRow(projectID, "notes/agenda.md", app: app), "Disponible sin conexión")

        try phase("allow-pending")
        assertStatus(fileRow(projectID, "notes/decisions.md", app: app), "Disponible sin conexión", timeout: 80)
        let future = fileRow(projectID, "notes/future.md", app: app)
        assertStatus(future, "Disponible sin conexión")
        try capture(app, "catalogue-recovered", state: "Failed transfer recovered and project retention automatically downloaded a newly shared file")

        let currentProject = element("shared-project-" + projectID, app: app)
        XCTAssertTrue(currentProject.waitForExistence(timeout: 10))
        try capture(app, "project-before-delete", state: "Accepted project remains nested under its linked Mac")
        currentProject.swipeLeft()
        XCTAssertTrue(currentProject.exists, "A swipe alone must not delete the received project")
        let delete = element("delete-shared-project-" + projectID, app: app)
        XCTAssertTrue(delete.waitForExistence(timeout: 5))
        try capture(app, "project-swipe-delete", state: "Swipe reveals an explicit local removal action")
        delete.tap()
        XCTAssertTrue(currentProject.waitForNonExistence(timeout: 10))
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["open-sync-settings"].waitForExistence(timeout: 15))
        app.buttons["Sincronizar"].firstMatch.tap()
        XCTAssertFalse(element("shared-project-" + projectID, app: app).waitForExistence(timeout: 10),
                       "Authorized refresh must not restore a locally removed project")
        XCTAssertTrue(app.buttons["open-demo-project"].exists)
        try capture(app, "project-deleted-after-refresh", state: "Locally removed project stays absent after relaunch and authenticated sync; Demo remains")
    }

    @MainActor private func element(_ identifier: String, app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }
    @MainActor private func fileRow(_ projectID: String, _ path: String, app: XCUIApplication) -> XCUIElement {
        element("shared-file-" + projectID + "-" + path, app: app)
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
        let connectedHost = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "shared-host-")).firstMatch
        XCTAssertTrue(connectedHost.waitForExistence(timeout: 20),
                      "Enrollment must expose the connected Mac as a host group")
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
    private func readyProjectID() throws -> String {
        let ready = try JSONSerialization.jsonObject(with: Data(contentsOf: root().appendingPathComponent("ready.json"))) as? [String: Any]
        return try XCTUnwrap(ready?["projectID"] as? String)
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
