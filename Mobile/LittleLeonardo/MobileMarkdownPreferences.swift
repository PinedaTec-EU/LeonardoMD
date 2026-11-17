import Combine
import Foundation
import LeonardoCore

@MainActor
final class MobileMarkdownPreferences: ObservableObject {
    static let shared = MobileMarkdownPreferences()

    private static let featuresKey = "littleLeonardo.markdownFeatures"
    private static let suppressWarningsKey = "littleLeonardo.suppressExtensionWarnings"

    private let defaults: UserDefaults
    @Published private(set) var features: MarkdownFeatures
    @Published private(set) var suppressesExtensionWarnings: Bool
    @Published private(set) var extensionWarningResetRevision = 0

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.featuresKey),
           let saved = try? JSONDecoder().decode(MarkdownFeatures.self, from: data) {
            features = saved
        } else {
            features = MarkdownFeatures()
        }
        suppressesExtensionWarnings = defaults.bool(forKey: Self.suppressWarningsKey)
    }

    func setEnabled(_ enabled: Bool, for item: BuiltInExtension) {
        var updated = features
        updated[keyPath: item.flag] = enabled
        setFeatures(updated)
    }

    func setFeatures(_ updated: MarkdownFeatures) {
        guard features != updated else { return }
        features = updated
        if let data = try? JSONEncoder().encode(updated) {
            defaults.set(data, forKey: Self.featuresKey)
        }
    }

    func setSuppressesExtensionWarnings(_ suppress: Bool) {
        guard suppressesExtensionWarnings != suppress else { return }
        suppressesExtensionWarnings = suppress
        defaults.set(suppress, forKey: Self.suppressWarningsKey)
    }

    func resetExtensionWarnings() {
        suppressesExtensionWarnings = false
        defaults.set(false, forKey: Self.suppressWarningsKey)
        extensionWarningResetRevision += 1
    }
}

struct MobileDocumentIdentity: Hashable {
    let projectID: UUID
    let path: String
}
