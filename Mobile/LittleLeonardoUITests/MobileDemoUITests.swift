import XCTest

@MainActor
func dismissSyncSettings(in app: XCUIApplication) {
    let close = app.buttons.matching(
        NSPredicate(format: "label IN %@", ["Cerrar", "Close", "Cerrar / Close"])
    ).firstMatch
    XCTAssertTrue(close.waitForExistence(timeout: 5), "The synchronization settings close button should be visible")
    close.tap()
}

final class MobileDemoUITests: XCTestCase {
    @MainActor func testOfflineDemoRendersAndRetainsPracticeAcrossRelaunch() throws {
        let app = XCUIApplication()
        app.launch()
        setAllExtensions(false, in: app)
        openDemo("en", in: app, expectRecommendation: true)
        resetDemo(in: app)
        let web = app.webViews.firstMatch
        XCTAssertTrue(web.staticTexts["Welcome to Little Leonardo"].waitForExistence(timeout: 15))
        capture(app, "English welcome")
        let field = practiceName(in: web, capturePrefix: "English gallery", app: app)
        XCTAssertEqual(field.value as? String, "")
        let help = web.buttons["Help for Practice name"]
        XCTAssertTrue(help.exists)
        help.tap()
        XCTAssertTrue(app.staticTexts["Local practice: use fictional details. Tap Save to confirm your answers."].waitForExistence(timeout: 5))
        app.buttons["Cerrar / Close"].tap()
        field.tap()
        field.typeText("Offline review sample")
        saveDemo(in: app)
        capture(app, "English saved practice")
        app.terminate()
        app.launch()
        openDemo("en", in: app)
        XCTAssertEqual(practiceName(in: app.webViews.firstMatch, app: app).value as? String, "Offline review sample")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        openDemo("es", in: app)
        XCTAssertTrue(app.webViews.staticTexts["Bienvenido a Little Leonardo"].waitForExistence(timeout: 15))
        capture(app, "Spanish welcome")
    }

    @MainActor func testSpanishSourceRoundTripKeepsFormEditableAndAnswersSeparate() throws {
        let app = XCUIApplication()
        app.launch()
        setAllExtensions(false, in: app)
        openDemo("es", in: app, expectRecommendation: true)
        resetDemo(in: app)
        let field = practiceName(in: app.webViews.firstMatch, app: app)
        XCTAssertEqual(field.value as? String, "")
        field.tap()
        field.typeText("Spanish source sample")
        saveDemo(in: app)
        app.buttons["demo-options"].tap()
        app.buttons["demo-source"].tap()
        let metadata = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@", "\"values\"", "Spanish source sample")).firstMatch
        XCTAssertTrue(metadata.waitForExistence(timeout: 10))
        capture(app, "Spanish source with saved values")
        app.buttons["demo-options"].tap()
        app.buttons["demo-source"].tap()
        let resumed = practiceName(in: app.webViews.firstMatch, app: app)
        XCTAssertEqual(resumed.value as? String, "Spanish source sample")
        resumed.tap()
        resumed.typeText(" after source")
        let editedValue = try XCTUnwrap(resumed.value as? String)
        XCTAssertTrue(editedValue.contains("Spanish source sample"))
        XCTAssertTrue(editedValue.contains(" after source"))
        saveDemo(in: app)
        app.terminate()
        app.launch()
        openDemo("es", in: app)
        XCTAssertEqual(practiceName(in: app.webViews.firstMatch, app: app).value as? String, editedValue)
        capture(app, "Spanish persisted practice after source")
    }

    @MainActor func testDemoProjectDeletionRequiresSwipeAndTapAndCanBeRestored() {
        let app = XCUIApplication()
        app.launch()
        setAllExtensions(false, in: app)
        let settings = app.buttons["open-sync-settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 15))
        if !app.buttons["open-demo-project"].exists {
            settings.tap()
            app.buttons["restore-demo-project"].tap()
            dismissSyncSettings(in: app)
        }
        let project = app.buttons["open-demo-project"]
        XCTAssertTrue(project.exists)
        capture(app, "Ordinary project library")
        project.swipeLeft()
        capture(app, "Swipe reveals explicit Delete")
        XCTAssertTrue(project.exists, "Swiping alone must not delete")
        app.buttons["delete-demo-project"].tap()
        XCTAssertFalse(project.exists)
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["open-sync-settings"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.buttons["open-demo-project"].exists)
        app.buttons["open-sync-settings"].tap()
        app.buttons["restore-demo-project"].tap()
        dismissSyncSettings(in: app)
        XCTAssertTrue(app.buttons["open-demo-project"].exists)
        capture(app, "Restored ordinary Demo project")
        app.buttons["open-demo-project"].tap()
        let demoHeader = app.descendants(matching: .any)["project-identity"].firstMatch
        XCTAssertTrue(demoHeader.waitForExistence(timeout: 10))
        XCTAssertEqual(demoHeader.label, "Demo, Local")
        capture(app, "Demo role Local")
        openDemo("en", in: app)
        capture(app, "Demo language document")
    }

    @MainActor private func setAllExtensions(_ enabled: Bool, in app: XCUIApplication) {
        let settings = app.buttons["open-sync-settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 15))
        settings.tap()
        capture(app, "Five device-local extension settings")

        for identifier in ["mermaid", "math", "vega-lite", "citations", "markdown-extensions"] {
            let toggle = app.switches["mobile-extension-\(identifier)-toggle"]
            XCTAssertTrue(toggle.waitForExistence(timeout: 10), "Missing extension setting: \(identifier)")
            XCTAssertTrue(toggle.isHittable
                          && toggle.frame.minY >= app.frame.minY + 100
                          && toggle.frame.maxY <= app.frame.maxY - 120,
                          "Extension setting is not fully visible: \(identifier), frame=\(toggle.frame)")
            let currentValue = extensionToggleValue(toggle)
            XCTAssertNotNil(currentValue,
                            "Unexpected value for extension setting: \(identifier), raw=\(String(describing: toggle.value))")
            if currentValue != enabled {
                toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
            }
            XCTAssertEqual(extensionToggleValue(toggle), enabled,
                           "The extension setting did not change: \(identifier)")
        }

        let reset = app.buttons["reset-mobile-extension-warnings"]
        for _ in 0..<8 where !reset.isHittable { app.swipeUp() }
        XCTAssertTrue(reset.isHittable)
        reset.tap()
        dismissSyncSettings(in: app)
    }

    @MainActor private func extensionToggleValue(_ toggle: XCUIElement) -> Bool? {
        if let value = toggle.value as? String {
            switch value.lowercased() {
            case "1", "true", "on": true
            case "0", "false", "off": false
            default: nil
            }
        } else if let value = toggle.value as? NSNumber {
            value.boolValue
        } else {
            nil
        }
    }

    @MainActor private func openDemo(_ language: String, in app: XCUIApplication,
                                     expectRecommendation: Bool = false) {
        let entry = app.buttons["open-demo-\(language)"]
        if !entry.exists, app.buttons["open-demo-project"].exists {
            app.buttons["open-demo-project"].tap()
        }
        XCTAssertTrue(entry.waitForExistence(timeout: 15))
        entry.tap()
        let enableSelected = app.buttons["enable-selected-mobile-extensions"]
        if expectRecommendation {
            XCTAssertTrue(enableSelected.waitForExistence(timeout: 15),
                          "The Demo should recommend its detected disabled extensions")
        } else {
            _ = enableSelected.waitForExistence(timeout: 5)
        }
        if enableSelected.exists {
            capture(app, "\(language) Demo extension recommendation")
            for identifier in ["mermaid", "math", "vega-lite", "citations", "markdown-extensions"] {
                let toggle = app.switches["enable-mobile-extension-\(identifier)"]
                XCTAssertTrue(toggle.waitForExistence(timeout: 10), "Missing detected extension: \(identifier)")
                if (toggle.value as? String) != "1" { toggle.tap() }
            }
            enableSelected.tap()
        }
        XCTAssertTrue(app.webViews.firstMatch.waitForExistence(timeout: 15))
    }

    @MainActor private func resetDemo(in app: XCUIApplication) {
        app.buttons["demo-options"].tap()
        app.buttons["demo-reset"].tap()
        let confirmation = app.sheets.firstMatch
        XCTAssertTrue(confirmation.waitForExistence(timeout: 5))
        confirmation.buttons["Restablecer / Reset"].tap()
        XCTAssertTrue(confirmation.waitForNonExistence(timeout: 5))
    }

    @MainActor private func practiceName(in web: XCUIElement, capturePrefix: String? = nil,
                                        app: XCUIApplication) -> XCUIElement {
        XCTAssertTrue(web.waitForExistence(timeout: 15))
        let field = web.textFields.firstMatch
        for step in 0..<22 {
            if field.exists && field.isHittable { break }
            web.swipeUp()
            if let capturePrefix { capture(app, "\(capturePrefix) \(step)") }
        }
        XCTAssertTrue(field.exists && field.isHittable)
        return field
    }

    @MainActor private func saveDemo(in app: XCUIApplication) {
        app.buttons["demo-save"].tap()
        XCTAssertTrue(app.staticTexts["Guardado en este dispositivo / Saved on this device"].waitForExistence(timeout: 10))
    }

    @MainActor private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
