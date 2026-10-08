import Foundation
import Observation

/// Supported interface languages. Document content is never translated.
enum AppLanguage: String, CaseIterable, Identifiable {
    case english = "en"
    case spanish = "es"

    var id: Self { self }
    var nativeName: String { self == .english ? "English" : "Español" }
}

/// Immutable catalogs shared by SwiftUI and native AppKit surfaces.
enum TranslationCatalog {
    static let catalogs: [AppLanguage: [String: String]] = Dictionary(
        uniqueKeysWithValues: AppLanguage.allCases.map { language in
            guard let url = Bundle.module.url(forResource: language.rawValue, withExtension: "json"),
                  let data = try? Data(contentsOf: url),
                  let strings = try? JSONDecoder().decode([String: String].self, from: data) else {
                preconditionFailure("Missing or invalid localization resource: \(language.rawValue)")
            }
            return (language, strings)
        }
    )

    static func text(_ key: String, language: AppLanguage) -> String {
        catalogs[language]?[key] ?? catalogs[.english]?[key] ?? key
    }
}

@MainActor @Observable
final class LanguageSettings {
    static let shared = LanguageSettings()
    static let preferenceKey = "interfaceLanguage"
    private let defaults: UserDefaults
    var language: AppLanguage {
        didSet {
            defaults.set(language.rawValue, forKey: Self.preferenceKey)
            NotificationCenter.default.post(name: Self.didChange, object: self)
        }
    }
    static let didChange = Notification.Name("LeonardoInterfaceLanguageChanged")

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        language = AppLanguage(rawValue: defaults.string(forKey: Self.preferenceKey) ?? "") ?? .english
    }
}

@MainActor
enum L10n {
    static func text(_ key: String) -> String {
        TranslationCatalog.text(key, language: LanguageSettings.shared.language)
    }

    static func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: text(key), locale: Locale(identifier: LanguageSettings.shared.language.rawValue), arguments: arguments)
    }
}
