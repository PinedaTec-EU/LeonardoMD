import XCTest
import UIKit

final class OnDemandSyncUITests: XCTestCase {
    @MainActor func testCatalogueContextRetentionAndSeparateCache() throws {
        guard ProcessInfo.processInfo.environment["LEONARDO_ON_DEMAND_QA_ROOT"] != nil else {
            throw XCTSkip("Requires the isolated on-demand loopback source")
        }
        defer { try? phase("finish") }
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(es)", "-AppleLocale", "es_ES",
                              "-directSyncIntervalMinutes", "0"]
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
        let addProject = app.buttons["incoming-project-add-" + projectID]
        let ignoreProject = app.buttons["incoming-project-ignore-" + projectID]
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
        XCTAssertTrue(ignoreProject.isHittable)
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
        let keepProjectOffline = app.buttons["Mantener sin conexión"]
        XCTAssertTrue(keepProjectOffline.waitForExistence(timeout: 5))
        let projectActionReady = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "isHittable == true"), object: keepProjectOffline)
        XCTAssertEqual(XCTWaiter.wait(for: [projectActionReady], timeout: 30), .completed,
                       "Project retention must wait until synchronization leaves the action available")
        try capture(app, "project-context-menu", state: "Project action explicitly enables offline retention")
        keepProjectOffline.tap()
        XCTAssertTrue(project.staticTexts["Incluye los ficheros nuevos"].waitForExistence(timeout: 5),
                      "Spanish project retention copy must match the app locale")
        let failedFileStatus = element("remote-file-download-failure-" + projectID + "-notes/decisions.md", app: app)
        XCTAssertTrue(failedFileStatus.waitForExistence(timeout: 15),
                      "A failed retained download must be visible on its file row")
        let initialAlert = app.alerts.firstMatch
        XCTAssertTrue(initialAlert.waitForExistence(timeout: 15), "The retained-download error must present a user-facing alert")
        let alertCopy = initialAlert.staticTexts.allElementsBoundByIndex.map(\.label).joined(separator: " ")
        XCTAssertTrue(alertCopy.contains("No se pudo completar la operación"))
        XCTAssertTrue(alertCopy.contains("No se pudo descargar el contenido."))
        XCTAssertFalse(alertCopy.contains("NSURLErrorDomain"), "Transport diagnostics stay in the local log")
        let alertCode = try XCTUnwrap(alertCopy.range(
            of: #"LL-[0-9A-F]{12}"#, options: .regularExpression).map { String(alertCopy[$0]) })
        XCTAssertEqual(alertCopy.components(separatedBy: alertCode).count - 1, 1,
                       "The notice should show one opaque reference code")
        XCTAssertEqual(initialAlert.buttons.count, 1, "The notice should offer one acknowledgement action")
        XCTAssertEqual(initialAlert.buttons.firstMatch.label, "Aceptar")
        let alertScreenshot = XCTAttachment(screenshot: app.screenshot())
        alertScreenshot.name = "Spanish Little Leonardo concise download alert"
        alertScreenshot.lifetime = .keepAlways
        add(alertScreenshot)
        initialAlert.buttons["Aceptar"].tap()
        XCTAssertEqual(failedFileStatus.label,
                       "Error de descarga; se reintentará al volver a abrir el fichero")
        XCTAssertTrue(project.staticTexts["Error de descarga · se reintentará"].waitForExistence(timeout: 30),
                      "The first retained transfer must finish before the document starts a contextual retry")

        fileRow(projectID, "notes/decisions.md", app: app).tap()
        let warning = element("remote-download-warning", app: app)
        XCTAssertTrue(warning.waitForExistence(timeout: 15), "A failed document download must show its concise preview message")
        let previewAlert = app.alerts.firstMatch
        XCTAssertTrue(previewAlert.waitForExistence(timeout: 5), "The document-download error must show its concise notice")
        let previewAlertCopy = previewAlert.staticTexts.allElementsBoundByIndex.map(\.label).joined(separator: " ")
        XCTAssertTrue(previewAlertCopy.contains("No se pudo descargar el documento."))
        XCTAssertFalse(previewAlertCopy.contains("NSURLErrorDomain"))
        XCTAssertEqual(previewAlert.buttons.count, 1)
        XCTAssertEqual(previewAlert.buttons.firstMatch.label, "Aceptar")
        previewAlert.buttons["Aceptar"].tap()
        let inlineError = element("remote-download-inline-error", app: app)
        XCTAssertTrue(inlineError.waitForExistence(timeout: 5))
        XCTAssertTrue(inlineError.label.contains("No se pudo descargar el documento."))
        let inlineCode = try XCTUnwrap(inlineError.label.range(
            of: #"LL-[0-9A-F]{12}"#, options: .regularExpression).map { String(inlineError.label[$0]) })
        XCTAssertTrue(inlineError.label.contains("Código: \(inlineCode)"))
        let errorScreenshot = XCTAttachment(screenshot: app.screenshot())
        errorScreenshot.name = "Spanish Little Leonardo document download error"
        errorScreenshot.lifetime = .keepAlways
        add(errorScreenshot)

        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["open-sync-settings"].tap()
        let logLink = element("open-error-log", app: app)
        for _ in 0..<12 {
            if logLink.waitForExistence(timeout: 0.3) { break }
            app.swipeUp()
        }
        XCTAssertTrue(logLink.waitForExistence(timeout: 5))
        logLink.tap()
        let matchingEntry = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "ref=\(inlineCode) op=downloads"))
            .firstMatch
        XCTAssertTrue(matchingEntry.waitForExistence(timeout: 5),
            "The reference in the preview must point to its local diagnostic entry")
        let logViewport = app.scrollViews.firstMatch
        XCTAssertTrue(logViewport.exists)
        XCTAssertTrue(matchingEntry.isHittable && matchingEntry.frame.intersects(logViewport.frame),
                      "The newest referenced error must be visible when the log opens")
        try capture(app, "diagnostic-log-latest", state: "The matching newest error reference is visible without scrolling")
        let logBack = app.navigationBars.buttons["Sincronización"]
        XCTAssertTrue(logBack.waitForExistence(timeout: 5))
        logBack.tap()
        let closeSettings = app.buttons["Cerrar"]
        XCTAssertTrue(closeSettings.waitForExistence(timeout: 5))
        closeSettings.tap()
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
        app.buttons["Sincronizar"].firstMatch.tap()
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

    @MainActor func testLocalDisplayNameAndSingularProjectCountCapture() throws {
        guard ProcessInfo.processInfo.environment["LEONARDO_ON_DEMAND_QA_ROOT"] != nil else {
            throw XCTSkip("Requires the isolated on-demand loopback source")
        }
        defer { try? phase("finish") }
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(es)", "-AppleLocale", "es_ES"]
        app.launch()
        let demoProject = app.buttons["open-demo-project"]
        if !demoProject.waitForExistence(timeout: 3) {
            app.buttons["open-sync-settings"].tap()
            let restoreDemo = app.buttons["restore-demo-project"]
            XCTAssertTrue(restoreDemo.waitForExistence(timeout: 5),
                          "The bundled Demo can be restored to prepare the local-section check")
            restoreDemo.tap()
            dismissSyncSettings(in: app)
        }
        XCTAssertTrue(demoProject.waitForExistence(timeout: 10), "The test must prepare the bundled local Demo")
        XCTAssertTrue(app.staticTexts["En este dispositivo"].exists,
                      "A local Demo must make its section visible before removal")
        demoProject.swipeLeft()
        let deleteDemo = app.buttons["delete-demo-project"]
        XCTAssertTrue(deleteDemo.waitForExistence(timeout: 5), "Removing the local Demo requires the explicit action")
        deleteDemo.tap()
        XCTAssertFalse(app.staticTexts["En este dispositivo"].exists,
                       "The local section must be absent when no local project remains")
        try enroll(app)

        let hostMenu = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@ AND label == %@",
                        "shared-host-menu-", "Acciones de Mac conectado")).firstMatch
        XCTAssertTrue(hostMenu.waitForExistence(timeout: 10), "The connected Mac must expose its local actions")
        hostMenu.tap()
        let rename = app.buttons.matching(NSPredicate(format: "label == %@", "Cambiar nombre")).firstMatch
        XCTAssertTrue(rename.waitForExistence(timeout: 5))
        rename.tap()

        let name = app.textFields.matching(
            NSPredicate(format: "placeholderValue == %@", "Nombre del Mac")).firstMatch
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        if let value = name.value as? String, !value.isEmpty {
            name.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: value.count))
        }
        name.typeText("Mac QA")
        app.buttons.matching(NSPredicate(format: "label == %@", "Guardar")).firstMatch.tap()

        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label == %@", "Mac QA"))
            .firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.matching(
            NSPredicate(format: "label == %@", "1 proyecto · 1 por revisar")).firstMatch.exists,
                      "A single pending project must use the singular count")
        let endpoint = try readyHost() + ":46987"
        XCTAssertFalse(app.staticTexts[endpoint].exists,
                       "An explicit local name keeps the endpoint out of the host row")
        XCTAssertFalse(app.staticTexts["En este dispositivo"].exists,
                       "The library must not reserve an empty local section below remote projects")
        try capture(app, "display-name-singular-count-es",
                    state: "Synthetic connected host uses its saved local Mac QA name, hides the endpoint, shows one project pending review and omits the empty local section")

        app.buttons["open-sync-settings"].tap()
        let restoreDemo = app.buttons["restore-demo-project"]
        XCTAssertTrue(restoreDemo.waitForExistence(timeout: 5))
        restoreDemo.tap()
        dismissSyncSettings(in: app)
        XCTAssertTrue(demoProject.waitForExistence(timeout: 5), "Restore the local Demo after the empty-section check")
    }

    @MainActor func testEnglishSharedDownloadFailureLocalizesVoiceOverCopy() throws {
        guard ProcessInfo.processInfo.environment["LEONARDO_ON_DEMAND_QA_ROOT"] != nil else {
            throw XCTSkip("Requires the isolated on-demand loopback source")
        }
        defer { try? phase("finish-english") }
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US",
                              "-directSyncIntervalMinutes", "0"]
        app.launch()
        XCTAssertTrue(app.buttons["open-sync-settings"].waitForExistence(timeout: 15))
        try enroll(app)

        let projectID = try readyProjectID()
        let addProject = app.buttons["incoming-project-add-" + projectID]
        var foundPendingProject = addProject.isHittable
        let hosts = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "shared-host-"))
        for index in 0..<hosts.count where !foundPendingProject {
            let host = hosts.element(boundBy: index)
            guard host.isHittable else { continue }
            host.tap()
            foundPendingProject = addProject.waitForExistence(timeout: 5) && addProject.isHittable
        }
        XCTAssertTrue(foundPendingProject)
        addProject.tap()
        let project = element("shared-project-" + projectID, app: app)
        XCTAssertTrue(project.waitForExistence(timeout: 20))
        try phase("assert-metadata")
        project.tap()

        element("shared-project-actions-" + projectID, app: app).tap()
        let keepProjectOffline = app.buttons["Mantener sin conexión"]
        XCTAssertTrue(keepProjectOffline.waitForExistence(timeout: 5))
        let actionReady = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "isHittable == true"), object: keepProjectOffline)
        XCTAssertEqual(XCTWaiter.wait(for: [actionReady], timeout: 30), .completed)
        keepProjectOffline.tap()
        XCTAssertTrue(project.staticTexts["Includes new files"].waitForExistence(timeout: 5),
                      "English project retention copy must match the app locale")

        let failure = element("remote-file-download-failure-" + projectID + "-notes/decisions.md", app: app)
        XCTAssertTrue(failure.waitForExistence(timeout: 20))
        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 15))
        let alertCopy = alert.staticTexts.allElementsBoundByIndex.map(\.label).joined(separator: " ")
        XCTAssertTrue(alertCopy.contains("The operation couldn’t be completed"))
        XCTAssertTrue(alertCopy.contains("Couldn't download the content."))
        XCTAssertFalse(alertCopy.contains("NSURLErrorDomain"))
        XCTAssertEqual(alert.buttons.firstMatch.label, "OK")
        XCTAssertEqual(failure.label, "Download failed; it will retry when you open the file again")
        XCTAssertTrue(project.staticTexts["Download failed · will retry"].waitForExistence(timeout: 5),
                      "The visible project status must follow the English app locale")
        try capture(app, "english-project-download-alert",
                    state: "English project and file failure statuses behind the concise download alert",
                    locale: "English")
        let alertScreenshot = XCTAttachment(screenshot: app.screenshot())
        alertScreenshot.name = "English Little Leonardo project failure and concise download alert"
        alertScreenshot.lifetime = .keepAlways
        add(alertScreenshot)
        alert.buttons["OK"].tap()
        XCTAssertTrue(failure.waitForExistence(timeout: 5))
        XCTAssertTrue(failure.isHittable)
        try capture(app, "english-file-failure", state: "English failure status and its VoiceOver retry guidance",
                    locale: "English")
        fileRow(projectID, "notes/decisions.md", app: app).tap()
        let warning = element("remote-download-warning", app: app)
        XCTAssertTrue(warning.waitForExistence(timeout: 15),
                      "A failed document download must show its concise preview message")
        let previewAlert = app.alerts.firstMatch
        XCTAssertTrue(previewAlert.waitForExistence(timeout: 5),
                      "The document-download error must show its concise notice")
        let previewAlertCopy = previewAlert.staticTexts.allElementsBoundByIndex.map(\.label).joined(separator: " ")
        XCTAssertTrue(previewAlertCopy.contains("Couldn't download the document."))
        XCTAssertFalse(previewAlertCopy.contains("NSURLErrorDomain"))
        XCTAssertEqual(previewAlert.buttons.count, 1)
        XCTAssertEqual(previewAlert.buttons.firstMatch.label, "OK")
        previewAlert.buttons["OK"].tap()

        let inlineError = element("remote-download-inline-error", app: app)
        XCTAssertTrue(inlineError.waitForExistence(timeout: 5))
        XCTAssertTrue(inlineError.label.contains("Couldn't download the document."))
        let inlineCode = try XCTUnwrap(inlineError.label.range(
            of: #"LL-[0-9A-F]{12}"#, options: .regularExpression).map { String(inlineError.label[$0]) })
        XCTAssertTrue(inlineError.label.contains("Code: \(inlineCode)"))
        try capture(app, "english-document-error", state: "English inline document failure and its diagnostic reference",
                    locale: "English")
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "English Little Leonardo inline document download error"
        attachment.lifetime = .keepAlways
        add(attachment)

        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["open-sync-settings"].tap()
        let logLink = element("open-error-log", app: app)
        for _ in 0..<12 {
            if logLink.waitForExistence(timeout: 0.3) { break }
            app.swipeUp()
        }
        XCTAssertTrue(logLink.waitForExistence(timeout: 5))
        logLink.tap()
        let matchingEntry = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "ref=\(inlineCode) op=downloads"))
            .firstMatch
        XCTAssertTrue(matchingEntry.waitForExistence(timeout: 5),
                      "The English preview reference must match its local diagnostic entry")
        let logViewport = app.scrollViews.firstMatch
        XCTAssertTrue(logViewport.exists)
        XCTAssertTrue(matchingEntry.isHittable && matchingEntry.frame.intersects(logViewport.frame),
                      "The matching download diagnostic must be visible when the log opens")
        try capture(app, "english-diagnostic-log-reference",
                    state: "English inline reference matches the local download diagnostic", locale: "English")
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
        host.tap(); host.typeText(try readyHost())
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
    private func readyHost() throws -> String {
        let ready = try JSONSerialization.jsonObject(with: Data(contentsOf: root().appendingPathComponent("ready.json"))) as? [String: Any]
        return ready?["host"] as? String ?? "127.0.0.1"
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
    @MainActor private func capture(_ app: XCUIApplication, _ name: String, state: String,
                                    locale: String = "Spanish") throws {
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
            "state": state + "; native points measured from app.frame; " + locale + "; Classic appearance"
        ]
        try JSONSerialization.data(withJSONObject: context, options: [.prettyPrinted, .sortedKeys])
            .write(to: destination.appendingPathComponent(name + ".context.json"), options: .atomic)
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
