import Foundation
import Observation
import LeonardoCore

@MainActor @Observable
final class ExtensionWarningPreferences {
    static let shared = ExtensionWarningPreferences()
    private static let key = "suppressedBuiltInExtensionWarnings"
    private let defaults: UserDefaults
    private(set) var suppressed: Set<BuiltInExtension>
    private(set) var resetRevision = 0

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        suppressed = Set((defaults.stringArray(forKey: Self.key) ?? []).compactMap(BuiltInExtension.init(rawValue:)))
    }
    func suppress(_ extensions: Set<BuiltInExtension>) {
        suppressed.formUnion(extensions)
        defaults.set(suppressed.map(\.rawValue).sorted(), forKey: Self.key)
    }
    func reset() {
        suppressed = []
        defaults.removeObject(forKey: Self.key)
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
        if let prompt, !matches(prompt, session: session) || !eligible {
            self.prompt = nil
        }
        guard eligible, detectedSource == session.content, prompt == nil, let document = session.documentURL else { return }
        let missing = BuiltInExtension.allCases.filter {
            detected.contains($0) && !session.features[keyPath: $0.flag]
                && !preferences.suppressed.contains($0) && !offered.contains($0)
        }
        guard !missing.isEmpty else { return }
        offered.formUnion(missing)
        prompt = ExtensionRecommendation(document: document, project: session.projectURL,
                                         source: session.content, extensions: missing)
    }
    func respond(to request: ExtensionRecommendation, activate: Bool,
                 suppress: Set<BuiltInExtension>, session: AppSession) {
        guard prompt?.id == request.id else { return }
        prompt = nil
        guard matches(request, session: session), !session.busy, !session.isSyncSuspended else { return }
        preferences.suppress(suppress.intersection(request.extensions))
        guard activate else { return }
        var features = session.features
        for item in request.extensions where detected.contains(item) {
            features[keyPath: item.flag] = true
        }
        session.setFeatures(features, project: request.project != nil)
    }
    private func matches(_ request: ExtensionRecommendation, session: AppSession) -> Bool {
        !session.stopped && !session.isClosing && session.documentURL == request.document
            && session.projectURL == request.project && session.content == request.source
    }
}
