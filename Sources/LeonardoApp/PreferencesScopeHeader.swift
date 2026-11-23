import SwiftUI

struct PreferencesScopeHeader: View {
    let projectURL: URL?
    @Binding var projectScope: Bool

    var body: some View {
        if projectURL != nil {
            PremiumSelection(selection: $projectScope, options: [false, true],
                title: { $0 ? L10n.text("This project") : L10n.text("Global") })
                .accessibilityLabel(L10n.text("Scope"))
                .accessibilityIdentifier("preferences-scope")
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.horizontal, 16)
                .padding(.bottom, 6)
        }
    }
}
