import SwiftUI

struct WelcomeView: View {
    @Bindable var session: AppSession

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                Color.clear
                    .frame(height: WelcomeWatermark.letteringSize(in: geometry.size).height + 24)
                    .accessibilityHidden(true)
                welcomeContent
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background { WelcomeWatermark() }
    }

    private var welcomeContent: some View {
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
                Text(L10n.text("Local · No account · Optional extensions")).font(.caption).foregroundStyle(.secondary)
                SavedItemsView(session: session)
            }
            .padding(28)
            .frame(maxWidth: 900)
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
