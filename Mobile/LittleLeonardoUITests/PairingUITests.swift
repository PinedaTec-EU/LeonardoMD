import XCTest

final class PairingUITests: XCTestCase {
    @MainActor func testNativeSSHGitScopedImportOfflineMutationRestartAndPublication() throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["LEONARDO_GIT_QA"] == "1",
              let port = environment["LEONARDO_GIT_QA_PORT"], UInt16(port) != nil,
              let fingerprint = environment["LEONARDO_GIT_QA_FINGERPRINT"],
              let projectName = environment["LEONARDO_GIT_QA_NAME"] else {
            throw XCTSkip("Requires the explicit generated-key native Git acceptance fixture")
        }
        let app = XCUIApplication()
        app.launch()
        app.buttons["open-git-pairing"].tap()
        let endpoint = app.textFields["git-endpoint"]
        XCTAssertTrue(endpoint.waitForExistence(timeout: 5))
        endpoint.tap()
        endpoint.typeText("ssh://fixture@127.0.0.1:\(port)/repo.git")
        app.buttons["Generar clave SSH en este dispositivo"].tap()
        let publicKey = app.staticTexts["git-public-key"]
        XCTAssertTrue(publicKey.waitForExistence(timeout: 5))
        XCTAssertTrue(publicKey.label.hasPrefix("ssh-ed25519 "))
        // This is the public provider key. The private key stays in the native
        // enrollment flow and device Keychain throughout the acceptance test.
        try FileHandle.standardOutput.write(contentsOf:
            Data("LEONARDO_GIT_PUBLIC_KEY \(publicKey.label)\n".utf8))
        try advanceGitFixture("authorize")
        app.buttons["git-discover"].tap()
        let confirm = app.buttons["git-confirm-host-key"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts[fingerprint].exists)
        confirm.tap()
        let branch = app.buttons[environment["LEONARDO_GIT_QA_BRANCH"] ?? "main"]
        XCTAssertTrue(branch.waitForExistence(timeout: 20))
        branch.tap()
        let folder = app.buttons["docs"]
        XCTAssertTrue(folder.waitForExistence(timeout: 20))
        folder.tap()
        XCTAssertEqual(app.staticTexts["git-selected-folder"].label, "Carpeta: docs")
        let name = app.textFields["git-project-name"]
        name.tap()
        if let value = name.value as? String, !value.isEmpty {
            name.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: value.count))
        }
        name.typeText(projectName)
        app.buttons["git-import-folder"].tap()
        let project = app.staticTexts[projectName].firstMatch
        XCTAssertTrue(project.waitForExistence(timeout: 25))
        project.tap()
        XCTAssertFalse(app.buttons["code/large.bin"].exists)
        let note = app.buttons["docs/note.md"].firstMatch
        XCTAssertTrue(note.waitForExistence(timeout: 10))
        note.tap()
        XCTAssertTrue(app.webViews.firstMatch.staticTexts["Native Git Initial"].waitForExistence(timeout: 10))

        try advanceGitFixture("offline")
        app.buttons["document-sync"].tap()
        XCTAssertTrue(app.alerts["No se pudo completar la operación"].waitForExistence(timeout: 15))
        app.alerts.buttons["Aceptar"].tap()
        XCTAssertTrue(app.webViews.firstMatch.staticTexts["Native Git Initial"].exists)
        try editNativeGitDocument(app, text: "# Native Git Edited\n")
        app.navigationBars.buttons[projectName].firstMatch.tap()
        app.buttons["Nuevo documento"].tap()
        let create = app.alerts["Nuevo documento"]
        XCTAssertTrue(create.waitForExistence(timeout: 5))
        create.textFields.firstMatch.tap()
        create.textFields.firstMatch.typeText("new.md")
        create.buttons["Crear"].tap()
        let newDocument = app.buttons["docs/new.md"].firstMatch
        XCTAssertTrue(newDocument.waitForExistence(timeout: 10))
        newDocument.tap()
        try editNativeGitDocument(app, text: "# Native Git New\n")
        app.navigationBars.buttons[projectName].firstMatch.tap()
        let deleted = app.buttons["docs/delete.md"].firstMatch
        XCTAssertTrue(deleted.waitForExistence(timeout: 5))
        deleted.swipeLeft()
        app.buttons["Eliminar"].firstMatch.tap()
        let deleteConfirmation = app.alerts["Eliminar documento"]
        XCTAssertTrue(deleteConfirmation.waitForExistence(timeout: 5))
        deleteConfirmation.buttons["Eliminar"].tap()
        XCTAssertFalse(deleted.waitForExistence(timeout: 2))

        app.terminate()
        app.launch()
        XCTAssertTrue(project.waitForExistence(timeout: 10))
        project.tap()
        XCTAssertTrue(app.buttons["docs/new.md"].exists)
        XCTAssertFalse(app.buttons["docs/delete.md"].exists)
        app.buttons["docs/note.md"].tap()
        XCTAssertTrue(app.webViews.firstMatch.staticTexts["Native Git Edited"].waitForExistence(timeout: 10))
        app.navigationBars.buttons[projectName].firstMatch.tap()
        try advanceGitFixture("online")
        let send = app.buttons["git-send-changes"]
        XCTAssertTrue(send.isEnabled)
        send.tap()
        let sent = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Reconciliación pendiente")).firstMatch
        XCTAssertTrue(sent.waitForExistence(timeout: 30))
        XCTAssertFalse(send.isEnabled)
        try advanceGitFixture("verify")
        let capture = XCTAttachment(screenshot: app.screenshot())
        capture.name = "Native SSH publication after scoped offline edits and restart"
        capture.lifetime = .keepAlways
        add(capture)
        try advanceGitFixture("integrate")
        app.buttons["docs/note.md"].tap()
        app.buttons["document-sync"].tap()
        app.navigationBars.buttons[projectName].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Reconciliación integrada"].waitForExistence(timeout: 30))
        XCTAssertFalse(send.isEnabled, "The exact integrated proposal must not be sent again")
        let integratedCapture = XCTAttachment(screenshot: app.screenshot())
        integratedCapture.name = "Native SSH integration consumed without duplicate changes"
        integratedCapture.lifetime = .keepAlways
        add(integratedCapture)
        app.buttons["docs/note.md"].tap()
        try editNativeGitDocument(app, text: "# Native Git Continued\n")
        app.navigationBars.buttons[projectName].firstMatch.tap()
        XCTAssertTrue(send.isEnabled)
        send.tap()
        XCTAssertTrue(sent.waitForExistence(timeout: 30))
        XCTAssertFalse(send.isEnabled)
        try advanceGitFixture("verifysecond")
        try advanceGitFixture("finish")
    }

    @MainActor private func editNativeGitDocument(_ app: XCUIApplication, text: String) throws {
        app.buttons["Editar"].tap()
        let editor = app.textViews.firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        let old = editor.value as? String ?? ""
        // A center tap can put the caret before the first line on iOS. Tap
        // below the short fixture text to place it at the end before deletion.
        editor.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.95)).tap()
        editor.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: old.count) + text)
        let valueExpectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", text), object: editor)
        guard XCTWaiter().wait(for: [valueExpectation], timeout: 5) == .completed else {
            XCTFail("The UI fixture editor did not settle to the requested text before saving")
            return
        }
        XCTAssertEqual(editor.value as? String, text, "The UI fixture must replace the entire document before saving")
        app.buttons["Guardar"].tap()
        XCTAssertTrue(app.buttons["Editar"].waitForExistence(timeout: 10))
    }

    private func advanceGitFixture(_ phase: String) throws {
        try FileHandle.standardOutput.write(contentsOf: Data("LEONARDO_GIT_STAGE_\(phase.uppercased())\n".utf8))
        Thread.sleep(forTimeInterval: 2)
    }

    @MainActor func testNativeDirectEnrollmentRefreshOfflineRetentionRetryAndRevocation() throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["LEONARDO_DIRECT_QA"] == "1",
              let port = environment["LEONARDO_DIRECT_QA_PORT"], UInt16(port) != nil else {
            throw XCTSkip("Requires the explicit loopback native direct acceptance fixture")
        }
        let app = XCUIApplication()
        app.launch()
        app.buttons["open-pairing"].tap()
        app.segmentedControls["pairing-method"].buttons["IP y puerto"].tap()
        let host = app.textFields["pairing-host"], portField = app.textFields["pairing-port"]
        host.tap(); host.typeText("127.0.0.1")
        portField.tap()
        if let value = portField.value as? String {
            portField.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: value.count))
        }
        portField.typeText(port)
        app.buttons["Solicitar conexión"].tap()
        let code = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Código de conexión:")).firstMatch
        XCTAssertTrue(code.waitForExistence(timeout: 15))
        try advanceDirectFixture("approve")
        app.buttons["Sincronizar"].firstMatch.tap()
        let project = app.staticTexts["QA · Native Direct"].firstMatch
        XCTAssertTrue(project.waitForExistence(timeout: 20))
        project.tap()
        app.buttons["docs/read.md"].firstMatch.tap()
        XCTAssertTrue(app.webViews.firstMatch.staticTexts["Native direct initial"].waitForExistence(timeout: 15))
        app.buttons["Editar"].tap()
        XCTAssertTrue(app.alerts["Este proyecto es de solo lectura"].waitForExistence(timeout: 5))
        app.alerts.buttons["Aceptar"].tap()

        try advanceDirectFixture("refresh")
        app.buttons["document-sync"].tap()
        XCTAssertTrue(app.webViews.firstMatch.staticTexts["Native direct updated"].waitForExistence(timeout: 15))
        try advanceDirectFixture("disable")
        app.buttons["document-sync"].tap()
        XCTAssertTrue(app.alerts["No se pudo completar la operación"].waitForExistence(timeout: 15))
        app.alerts.buttons["Aceptar"].tap()
        XCTAssertTrue(app.webViews.firstMatch.staticTexts["Native direct updated"].exists)

        try advanceDirectFixture("restart")
        app.buttons["document-sync"].tap()
        XCTAssertTrue(app.webViews.firstMatch.staticTexts["Native direct updated"].waitForExistence(timeout: 15))
        try advanceDirectFixture("revoke")
        app.buttons["document-sync"].tap()
        XCTAssertTrue(app.staticTexts["Acceso retirado"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.webViews.firstMatch.exists)
        let capture = XCTAttachment(screenshot: app.screenshot())
        capture.name = "Enrolled direct project purged after confirmed revocation"
        capture.lifetime = .keepAlways
        add(capture)
        try advanceDirectFixture("finish")
    }

    private func advanceDirectFixture(_ phase: String) throws {
        try FileHandle.standardOutput.write(contentsOf: Data("LEONARDO_DIRECT_STAGE_\(phase.uppercased())\n".utf8))
        // The host controller applies the phase to the real loopback service. This short
        // delay precedes an actual UI/network assertion; it does not manufacture a result.
        Thread.sleep(forTimeInterval: 2)
    }

    @MainActor func testCachedDocumentLinksNavigateInsideGrantedCorpusAndRejectMissingFiles() throws {
        let app = XCUIApplication()
        app.launch()
        let fixture = app.staticTexts["QA · Links"].firstMatch
        guard fixture.waitForExistence(timeout: 5) else {
            throw XCTSkip("Requires the isolated QA link corpus in the simulator app container")
        }
        fixture.tap()
        app.buttons["docs/start.md"].firstMatch.tap()
        let web = app.webViews.firstMatch
        XCTAssertTrue(web.links["Siguiente documento"].waitForExistence(timeout: 10))
        web.links["Siguiente documento"].tap()
        XCTAssertTrue(app.webViews.firstMatch.staticTexts["Linked page"].waitForExistence(timeout: 10))
        app.navigationBars.buttons["start.md"].firstMatch.tap()
        XCTAssertTrue(app.webViews.firstMatch.links["Documento ausente"].waitForExistence(timeout: 10))
        app.webViews.firstMatch.links["Documento ausente"].tap()
        XCTAssertTrue(app.alerts["Documento no disponible"].waitForExistence(timeout: 5))
        app.alerts.buttons["Aceptar"].tap()
        XCTAssertTrue(app.webViews.firstMatch.staticTexts["Start page"].exists)
        let capture = XCTAttachment(screenshot: app.screenshot())
        capture.name = "Cached document navigation with missing-link denial"
        capture.lifetime = .keepAlways
        add(capture)
    }

    @MainActor func testCachedMarkdownPreviewShowsRenderedHeadingTableAndImage() throws {
        let app = XCUIApplication()
        app.launch()
        let fixture = app.staticTexts["QA · Markdown"].firstMatch
        guard fixture.waitForExistence(timeout: 5) else {
            throw XCTSkip("Requires the isolated QA Markdown corpus in the simulator app container")
        }
        fixture.tap()
        app.buttons["docs/preview.md"].firstMatch.tap()
        let web = app.webViews.firstMatch
        XCTAssertTrue(web.waitForExistence(timeout: 10))
        XCTAssertTrue(web.staticTexts["Offline preview"].waitForExistence(timeout: 10))
        XCTAssertTrue(web.staticTexts["Ready"].exists)
        XCTAssertTrue(web.images["Cached diagram"].exists)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Offline Markdown corpus preview"
        attachment.lifetime = .keepAlways
        add(attachment)
        app.buttons["Ver texto"].tap()
        XCTAssertFalse(app.webViews.firstMatch.exists)
    }

    @MainActor func testSyncSettingsAreAvailableWithoutDesktopPairing() throws {
        let app = XCUIApplication()
        app.launch()
        let settings = app.buttons["open-sync-settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 10))
        settings.tap()
        XCTAssertTrue(app.staticTexts["La sincronización automática funciona mientras la app está activa."].waitForExistence(timeout: 5))
        app.buttons["Cerrar"].tap()
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
    }

    @MainActor func testGitEnrollmentRequiresEndpointAndCanCancelWithoutConnecting() throws {
        let app = XCUIApplication()
        app.launch()
        let connect = app.buttons["open-git-pairing"]
        XCTAssertTrue(connect.waitForExistence(timeout: 10))
        connect.tap()
        let endpoint = app.textFields["git-endpoint"]
        XCTAssertTrue(endpoint.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["git-discover"].isEnabled)
        endpoint.tap()
        endpoint.typeText("https://fixture.invalid/project.git")
        XCTAssertTrue(app.buttons["git-discover"].isEnabled)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Git endpoint and device Keychain enrollment"
        attachment.lifetime = .keepAlways
        add(attachment)
        app.buttons["Cerrar"].tap()
        XCTAssertTrue(connect.waitForExistence(timeout: 5))
    }

    @MainActor func testManualPairingFormRequiresAddressAndRetainsQRAlternative() throws {
        let app = XCUIApplication()
        app.launch()
        let connect = app.buttons["open-pairing"]
        XCTAssertTrue(connect.waitForExistence(timeout: 10))
        connect.tap()
        app.segmentedControls["pairing-method"].buttons["IP y puerto"].tap()
        let host = app.textFields["pairing-host"]
        XCTAssertTrue(host.waitForExistence(timeout: 5))
        XCTAssertEqual(app.textFields["pairing-port"].value as? String, "40882")
        XCTAssertFalse(app.buttons["Solicitar conexión"].isEnabled)
        host.tap()
        host.typeText("192.168.1.7")
        XCTAssertTrue(app.buttons["Solicitar conexión"].isEnabled)
        app.segmentedControls["pairing-method"].buttons["QR"].tap()
        XCTAssertTrue(app.buttons["scan-pairing-qr"].exists)
        XCTAssertFalse(app.buttons["Solicitar conexión"].isEnabled)
        app.buttons["Cerrar"].tap()
    }

    @MainActor func testSimulatorScannerFallbackCanBeCancelledWithoutStartingConnection() throws {
        let app = XCUIApplication()
        app.launch()
        let connect = app.buttons["open-pairing"]
        XCTAssertTrue(connect.waitForExistence(timeout: 10))
        connect.tap()
        let scan = app.buttons["scan-pairing-qr"]
        XCTAssertTrue(scan.waitForExistence(timeout: 5))
        scan.tap()
        XCTAssertTrue(app.staticTexts["Cámara no disponible"].waitForExistence(timeout: 10))
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Scanner unavailable on Simulator"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        app.buttons["Cancelar"].tap()
        XCTAssertTrue(scan.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Solicitar conexión"].isEnabled)
        app.buttons["Cerrar"].tap()
        XCTAssertTrue(connect.waitForExistence(timeout: 5))
    }
}
