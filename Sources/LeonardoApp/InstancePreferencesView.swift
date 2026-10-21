import SwiftUI

struct InstancePreferencesView: View {
    var preferences: InstancePreferences = .shared

    var body: some View {
        Toggle(L10n.text("Allow multiple instances"), isOn: Binding(
            get: { preferences.allowsMultipleInstances },
            set: { preferences.allowsMultipleInstances = $0 }))
            .accessibilityIdentifier("allow-multiple-instances")
        Text(L10n.text("Use File > New instance to open an independent process. Finder opens go to the principal instance. Turning this off keeps existing instances open."))
            .font(.caption).foregroundStyle(.secondary)
    }
}
