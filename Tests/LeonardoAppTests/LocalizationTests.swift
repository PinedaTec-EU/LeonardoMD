import AppKit
import XCTest
@testable import LeonardoApp

@MainActor
final class LocalizationTests: XCTestCase {
    func testFreshAndUnknownPreferencesUseEnglish() {
        let (defaults, name) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(["es"], forKey: "AppleLanguages")
        XCTAssertEqual(LanguageSettings(defaults: defaults).language, .english)
        defaults.set("unsupported", forKey: LanguageSettings.preferenceKey)
        XCTAssertEqual(LanguageSettings(defaults: defaults).language, .english)
    }

    func testSelectionPersistsAcrossSettingsInstances() {
        let (defaults, name) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let settings = LanguageSettings(defaults: defaults)
        settings.language = .spanish
        XCTAssertEqual(LanguageSettings(defaults: defaults).language, .spanish)
        settings.language = .english
        XCTAssertEqual(LanguageSettings(defaults: defaults).language, .english)
    }

    func testCatalogsHaveIdenticalKeysAndFormatArguments() throws {
        let english = try XCTUnwrap(TranslationCatalog.catalogs[.english])
        XCTAssertGreaterThan(english.count, 100)
        let pattern = try NSRegularExpression(pattern: "%[-+0-9.]*[a-zA-Z@]")
        func placeholders(_ value: String) -> [String] {
            pattern.matches(in: value, range: NSRange(value.startIndex..., in: value)).map {
                String(value[Range($0.range, in: value)!])
            }
        }
        for language in AppLanguage.allCases {
            let catalog = try XCTUnwrap(TranslationCatalog.catalogs[language])
            XCTAssertEqual(Set(catalog.keys), Set(english.keys))
            for (key, value) in catalog {
                XCTAssertFalse(value.isEmpty, key)
                XCTAssertEqual(placeholders(value), placeholders(english[key]!), key)
            }
        }
        XCTAssertEqual(TranslationCatalog.text("Preferences", language: .spanish), "Preferencias")
        XCTAssertEqual(TranslationCatalog.text("Unknown key", language: .spanish), "Unknown key")
    }

    func testLiveLookupAndInterpolationFollowSelection() {
        let settings = LanguageSettings.shared
        let previous = settings.language
        defer { settings.language = previous }
        settings.language = .english
        XCTAssertEqual(DocumentMode.preview.title, "Preview")
        XCTAssertEqual(L10n.format("Close tab %@", "notes.md"), "Close tab notes.md")
        settings.language = .spanish
        XCTAssertEqual(DocumentMode.preview.title, "Lectura")
        XCTAssertEqual(L10n.format("Close tab %@", "notes.md"), "Cerrar pestaña notes.md")
        XCTAssertEqual(L10n.format("%d words", 42), "42 palabras")
    }

    func testNativeMenusAndSuggestedFilenamesUseSelectedLanguage() {
        _ = NSApplication.shared
        let previousLanguage = LanguageSettings.shared.language
        let previousMenu = NSApp.mainMenu
        defer {
            LanguageSettings.shared.language = previousLanguage
            NSApp.mainMenu = previousMenu
        }
        let delegate = ApplicationDelegate(diagnostics: StartupDiagnostics(),
            instance: SingleInstance(name: "LocalizationMenuTests"), role: .primary)
        for language in AppLanguage.allCases {
            LanguageSettings.shared.language = language
            delegate.configureMenu()
            let appMenu = NSApp.mainMenu?.items.first?.submenu
            XCTAssertEqual(appMenu?.items[1].title, language == .english ? "Preferences…" : "Preferencias…")
            XCTAssertEqual(NSApp.mainMenu?.items[1].title, language == .english ? "File" : "Archivo")
            XCTAssertEqual(L10n.text("Copy filename suffix"), language == .english ? "-copy.md" : "-copia.md")
            XCTAssertEqual(L10n.text("New note filename"), language == .english ? "note.md" : "nota.md")
        }
    }

    func testTabReorderCopyUsesSelectedLanguage() {
        let previous = LanguageSettings.shared.language
        defer { LanguageSettings.shared.language = previous }
        for language in AppLanguage.allCases {
            LanguageSettings.shared.language = language
            XCTAssertEqual(L10n.text("Drag to reorder tab"), language == .english ? "Drag to reorder tab" : "Arrastra para reordenar la pestaña")
            XCTAssertEqual(L10n.format("Reorder tab %@", "notes.md"), language == .english ? "Reorder tab notes.md" : "Reordenar pestaña notes.md")
        }
    }

    func testAppHelpAndAccessibilityAvoidUntranslatedSpanishLiterals() throws {
        let appSources = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/LeonardoApp")
        let files = try XCTUnwrap(FileManager.default.enumerator(at: appSources,
            includingPropertiesForKeys: nil))
        let literal = try NSRegularExpression(pattern: #"\.(?:help|accessibilityLabel)\("([^"\n]*)""#)
        let spanish = try NSRegularExpression(pattern: #"(?i)[áéíóúñ¿¡]|\b(?:arrastra|reordenar|pestaña|abrir|cerrar|mostrar|copiar|guardar|mover)\b"#)
        for case let file as URL in files where file.pathExtension == "swift" {
            let source = try String(contentsOf: file, encoding: .utf8)
            for match in literal.matches(in: source, range: NSRange(source.startIndex..., in: source)) {
                let text = String(source[try XCTUnwrap(Range(match.range(at: 1), in: source))])
                XCTAssertNil(spanish.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)), file.lastPathComponent + ": " + text)
            }
        }
    }

    func testOpenAboutWindowTitleChangesWithLanguage() {
        _ = NSApplication.shared
        let previous = LanguageSettings.shared.language
        defer { LanguageSettings.shared.language = previous }
        LanguageSettings.shared.language = .english
        let controller = AboutWindow()
        defer { controller.close() }
        controller.present()
        XCTAssertTrue(controller.window?.isVisible == true)
        LanguageSettings.shared.language = .spanish
        XCTAssertEqual(controller.window?.title, "Acerca de LeonardoMD")
        LanguageSettings.shared.language = .english
        XCTAssertEqual(controller.window?.title, "About LeonardoMD")
    }

    private func isolatedDefaults() -> (UserDefaults, String) {
        let name = "LocalizationTests.\(UUID().uuidString)"
        return (UserDefaults(suiteName: name)!, name)
    }
}
