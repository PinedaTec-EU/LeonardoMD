import Foundation

@MainActor
final class ReleaseNotesPreferences {
    private let defaults: UserDefaults
    private static let key = "releaseNotesPresentation.v1"

    private struct State: Codable {
        var lastVersion: String?
        var baseline: String?
        var suppressed: Set<String> = []
    }

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    private var state: State {
        guard let data = defaults.data(forKey: Self.key),
              let value = try? JSONDecoder().decode(State.self, from: data),
              value.lastVersion.map({ ReleaseChanges.parts($0) != nil }) ?? true,
              value.baseline.map({ ReleaseChanges.parts($0) != nil }) ?? true,
              value.suppressed.allSatisfy({ ReleaseChanges.parts($0) != nil }) else { return State() }
        return value
    }

    func shouldPresent(version: String) -> Bool { !state.suppressed.contains(version) }

    func baseline(for version: String) -> String? {
        let value = state
        return value.lastVersion == version ? value.baseline : value.lastVersion
    }

    /// A version has its own preference. A new version always starts with suppression enabled.
    func suppressionDefault(for version: String) -> Bool {
        let value = state
        return value.lastVersion != version || value.suppressed.contains(version)
    }

    func acknowledge(version: String, baseline: String?, suppress: Bool) throws {
        var value = state
        value.lastVersion = version
        value.baseline = baseline
        if suppress { value.suppressed.insert(version) }
        else { value.suppressed.remove(version) }
        defaults.set(try JSONEncoder().encode(value), forKey: Self.key)
    }
}
