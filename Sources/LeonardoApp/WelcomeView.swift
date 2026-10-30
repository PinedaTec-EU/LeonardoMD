import SwiftUI

struct WelcomeView: View {
    @Bindable var session: AppSession

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                Image(systemName: "doc.richtext").font(.system(size: 54, weight: .light)).foregroundStyle(session.accentColor)
                Text(L10n.text("Your documents, your way.")).font(.largeTitle.weight(.semibold))
                Text(L10n.text("Open a Markdown file to read it instantly\nor a folder to work with a project."))
                    .multilineTextAlignment(.center).foregroundStyle(.secondary)
                HStack {
                    Button(L10n.text("Open document…")) { session.chooseDocument() }.buttonStyle(PremiumButtonStyle(prominent: true))
                    Button(L10n.text("Open project…")) { session.chooseProject() }.buttonStyle(PremiumButtonStyle())
                }
                Button(L10n.text("Manage workspaces…")) { session.showWorkspace = true }.buttonStyle(PremiumButtonStyle())
                Button { Task { await session.openUserGuide() } } label: {
                    Label(L10n.text("Leonardo user guide…"), systemImage: "book")
                }
                .buttonStyle(PremiumButtonStyle())
                .accessibilityIdentifier("open-user-guide")
                Text(L10n.text("Local · No account · Optional extensions")).font(.caption).foregroundStyle(.secondary)
                SavedItemsView(session: session)
            }
            .padding(28)
            .frame(maxWidth: 900)
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background { WelcomeWatermark() }
    }
}
