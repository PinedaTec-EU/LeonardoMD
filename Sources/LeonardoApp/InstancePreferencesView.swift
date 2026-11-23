import SwiftUI

struct InstancePreferencesView: View {
    var preferences: InstancePreferences = .shared

    var body: some View {
        Toggle(L10n.text("Allow multiple instances"), isOn: Binding(
            get: { preferences.allowsMultipleInstances },
            set: { preferences.allowsMultipleInstances = $0 }))
            .accessibilityIdentifier("allow-multiple-instances")
        Toggle(L10n.text("Group instances in Dock and app switcher"), isOn: Binding(
            get: { preferences.groupsInstances },
            set: { preferences.groupsInstances = $0 }))
            .disabled(!preferences.allowsMultipleInstances)
            .accessibilityIdentifier("group-application-instances")
        Text(L10n.text("Grouped processes share one Dock entry. Use Instances in any window to switch or quit. If the representative closes, another takes its place."))
            .font(.caption).foregroundStyle(.secondary)
        Text(L10n.text("Use File > New instance to open an independent process. Finder opens go to the principal instance. Turning this off keeps existing instances open."))
            .font(.caption).foregroundStyle(.secondary)
    }
}
