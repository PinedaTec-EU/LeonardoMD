import SwiftUI

struct SyncRoleSelector: View {
    typealias Page = SynchronizationPreferencesView.Page
    @Binding var selection: Page

    var body: some View {
        HStack(spacing: 12) {
            ForEach(Page.allCases) { page in
                roleButton(page)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L10n.text("Synchronization role"))
        .accessibilityIdentifier("synchronization-role")
    }

    private func roleButton(_ page: Page) -> some View {
        IllustratedSelectorButton(title: page.title, artwork: page.artwork, selected: selection == page) {
            selection = page
        }
        .accessibilityIdentifier("sync-role-\(page.rawValue)")
        .help(page.help)
    }
}
