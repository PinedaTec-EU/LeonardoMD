import AppKit
import Observation

@MainActor @Observable
final class InstancePreferences {
    static let shared = InstancePreferences()
    static let preferenceKey = "allowMultipleInstances"
    static let launchArgument = "--new-instance"
    private let defaults: UserDefaults
    private var revision = 0
    var allowsMultipleInstances: Bool {
        get {
            _ = revision
            defaults.synchronize()
            return defaults.bool(forKey: Self.preferenceKey)
        }
        set {
            defaults.set(newValue, forKey: Self.preferenceKey)
            defaults.synchronize()
            revision += 1
        }
    }

    init(defaults: UserDefaults = UserDefaults(suiteName: "eu.pinedatec.LeonardoMD")!) {
        self.defaults = defaults
    }

    func launch() async throws {
        guard allowsMultipleInstances else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        configuration.allowsRunningApplicationSubstitution = false
        configuration.arguments = [Self.launchArgument]
        _ = try await NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration)
    }
}

/// Set before any controllers are constructed. Additional processes never own
/// synchronization caches, listeners or update installation.
@MainActor
enum InstanceRuntime {
    static var isAdditional = false
}
