import SwiftUI

/// Scope is part of the selected pane, so it cannot move the tab navigation.
struct PreferencesScopeHeader: View {
    let title: String
    let projectURL: URL?
    @Binding var projectScope: Bool

    private var scopeDescription: String {
        if projectScope, let projectURL {
            return L10n.format("Project: %@", projectURL.lastPathComponent)
        }
        return L10n.text("Global preferences apply to the standalone viewer and projects that inherit them.")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(L10n.text(title)).font(.title3.bold())
                Spacer()
                if projectURL != nil {
                    PremiumSelection(selection: $projectScope, options: [false, true],
                        title: { $0 ? L10n.text("This project") : L10n.text("Global") })
                        .accessibilityLabel(L10n.text("Scope"))
                        .accessibilityIdentifier("preferences-scope")
                }
            }
            Text(scopeDescription)
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
