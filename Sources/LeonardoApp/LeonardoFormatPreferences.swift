import Foundation
import Observation

/// Mac-wide format settings share one observation source across document sessions.
@MainActor @Observable
final class LeonardoFormatPreferences {
    static let shared = LeonardoFormatPreferences(defaults: .standard)
    static let migrationDefaultsKey = "migrateMarkdownOnSave"
    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    var packageOpenPreference: LeonardoPackageOpenPreference {
        get {
            access(keyPath: \.packageOpenPreference)
            return LeonardoPackageOpenPreference(rawValue:
                defaults.string(forKey: LeonardoPackageOpenPreference.defaultsKey) ?? "") ?? .defaultValue
        }
        set {
            withMutation(keyPath: \.packageOpenPreference) {
                defaults.set(newValue.rawValue, forKey: LeonardoPackageOpenPreference.defaultsKey)
            }
        }
    }

    var migrateMarkdownOnSave: Bool {
        get {
            access(keyPath: \.migrateMarkdownOnSave)
            return defaults.bool(forKey: Self.migrationDefaultsKey)
        }
        set {
            withMutation(keyPath: \.migrateMarkdownOnSave) {
                defaults.set(newValue, forKey: Self.migrationDefaultsKey)
            }
        }
    }
}
