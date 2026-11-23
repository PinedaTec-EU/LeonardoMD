import SwiftUI

struct SyncRoleSelector: View {
    typealias Page = SynchronizationPreferencesView.Page
    @Binding var selection: Page
    @Environment(\.leonardoAccent) private var accent

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
        let selected = selection == page
        return Button {
            selection = page
        } label: {
            VStack(spacing: 2) {
                page.artwork.illustration.frame(width: 84, height: 48)
                Text(page.title).font(.callout.weight(.semibold))
            }
            .frame(width: 124, height: 76)
            .background { PremiumControlBackground(selected: selected) }
            .overlay(alignment: .topTrailing) {
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(accent)
                        .padding(6)
                        .accessibilityHidden(true)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("sync-role-\(page.rawValue)")
        .help(page.help)
    }
}
