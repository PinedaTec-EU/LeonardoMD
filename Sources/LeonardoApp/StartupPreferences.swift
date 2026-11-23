import SwiftUI

struct StartupPreferences: View {
    @Bindable var session: AppSession

    var body: some View {
        Toggle(L10n.text("Reopen documents and projects on startup"), isOn: Binding(
            get: { session.globalPreferences.restorePreviousSession },
            set: { session.setRestorePreviousSession($0) }
        )).accessibilityIdentifier("startup-session")
        Text(L10n.text("Reopens the previous session on this Mac. Opening a file directly takes priority."))
            .font(.caption).foregroundStyle(.secondary)
    }
}
