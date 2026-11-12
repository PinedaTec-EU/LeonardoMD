import Foundation
import Observation
import LeonardoCore

@MainActor @Observable
final class ExtensionWarningPreferences {
    static let shared = ExtensionWarningPreferences()
    private static let legacyKey = "suppressedBuiltInExtensionWarnings"
    private static let suppressAllKey = "suppressAllBuiltInExtensionWarnings"
    private let defaults: UserDefaults
    private(set) var legacySuppressed: Set<BuiltInExtension>
    private(set) var suppressAllWarnings: Bool
    private(set) var resetRevision = 0

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        legacySuppressed = Set((defaults.stringArray(forKey: Self.legacyKey) ?? []).compactMap(BuiltInExtension.init(rawValue:)))
        suppressAllWarnings = defaults.bool(forKey: Self.suppressAllKey)
    }
    func setSuppressAllWarnings(_ suppress: Bool) {
        suppressAllWarnings = suppress
        defaults.set(suppress, forKey: Self.suppressAllKey)
    }
    func reset() {
        legacySuppressed = []
        suppressAllWarnings = false
        defaults.removeObject(forKey: Self.legacyKey)
        defaults.removeObject(forKey: Self.suppressAllKey)
        resetRevision += 1
    }
}

struct ExtensionRecommendation: Identifiable {
    let id = UUID()
    let document: URL
    let project: URL?
    let source: String
    let extensions: [BuiltInExtension]
}

struct ExtensionRecommendationChoice: Equatable {
    var enabledExtensions: Set<BuiltInExtension> = []
    var suppressWarnings = false
}

@MainActor @Observable
final class ExtensionRecommendations {
    var detected: Set<BuiltInExtension> = []
    var detectedSource: String?
    var prompt: ExtensionRecommendation?
    let preferences: ExtensionWarningPreferences
    private var offered: Set<BuiltInExtension> = []
    private var resetRevision: Int

    init(preferences: ExtensionWarningPreferences = .shared) {
        self.preferences = preferences
        resetRevision = preferences.resetRevision
    }
    func resetOpening() {
        detected = []
        detectedSource = nil
        offered = []
        prompt = nil
    }
    func prepare(for session: AppSession, eligible: Bool) {
        if resetRevision != preferences.resetRevision {
            offered = []
            resetRevision = preferences.resetRevision
        }
        if let prompt, preferences.suppressAllWarnings || !matches(prompt, session: session) || !eligible
            || prompt.extensions.contains(where: {
                session.features[keyPath: $0.flag] || preferences.legacySuppressed.contains($0)
            }) {
            self.prompt = nil
        }
        guard eligible, !preferences.suppressAllWarnings,
              detectedSource == session.content, prompt == nil,
              let document = session.documentURL else { return }
        let missing = BuiltInExtension.allCases.filter {
            detected.contains($0) && !session.features[keyPath: $0.flag]
                && !preferences.legacySuppressed.contains($0) && !offered.contains($0)
        }
        guard !missing.isEmpty else { return }
        offered.formUnion(missing)
        prompt = ExtensionRecommendation(document: document, project: session.projectURL,
                                         source: session.content, extensions: missing)
    }
    func respond(to request: ExtensionRecommendation, choice: ExtensionRecommendationChoice, session: AppSession) {
        guard prompt?.id == request.id else { return }
        prompt = nil
        guard matches(request, session: session), !session.busy, !session.isSyncSuspended else { return }
        preferences.setSuppressAllWarnings(choice.suppressWarnings)
        let selected = choice.enabledExtensions.intersection(request.extensions)
        guard !selected.isEmpty else { return }
        var features = session.features
        for item in selected where detected.contains(item) {
            features[keyPath: item.flag] = true
        }
        session.setFeatures(features, project: request.project != nil)
    }
    private func matches(_ request: ExtensionRecommendation, session: AppSession) -> Bool {
        !session.stopped && !session.isClosing && session.documentURL == request.document
            && session.projectURL == request.project && session.content == request.source
    }
}
