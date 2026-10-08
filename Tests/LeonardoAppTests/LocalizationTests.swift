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

    private func isolatedDefaults() -> (UserDefaults, String) {
        let name = "LocalizationTests.\(UUID().uuidString)"
        return (UserDefaults(suiteName: name)!, name)
    }
}
