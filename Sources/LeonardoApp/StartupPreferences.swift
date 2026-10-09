import SwiftUI

struct StartupPreferences: View {
    @Bindable var session: AppSession

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Picker(L10n.text("On startup"), selection: Binding(
                get: { session.globalPreferences.restorePreviousSession },
                set: { session.globalPreferences.restorePreviousSession = $0; session.persistSettings() }
            )) {
                Text(L10n.text("Restore previous session")).tag(true)
                Text(L10n.text("Start clean")).tag(false)
            }.accessibilityIdentifier("startup-session")
            Text(L10n.text("Applies to all windows on the next launch. Files opened explicitly always take priority."))
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}
