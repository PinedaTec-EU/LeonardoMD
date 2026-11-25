import SwiftUI
import LeonardoCore

struct WelcomeView: View {
    @Bindable var session: AppSession
    @State private var kind: FavoriteItem.Kind = .project

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                Image(systemName: "doc.richtext").font(.system(size: 54, weight: .light)).foregroundStyle(session.accentColor)
                Text(L10n.text("Your documents, your way.")).font(.largeTitle.weight(.semibold))
                Text(L10n.text("Open a Markdown file to read it instantly\nor a folder to work with a project."))
                    .multilineTextAlignment(.center).foregroundStyle(.secondary)
                categorySelector
                Button(L10n.text(kind == .project ? "Open project…" : "Open document…")) {
                    if kind == .project {
                        session.chooseProject()
                    } else {
                        session.chooseDocument()
                    }
                }
                .buttonStyle(PremiumButtonStyle(prominent: true))
                Button { Task { await session.openUserGuide() } } label: {
                    Label(L10n.text("Leonardo user guide…"), systemImage: "book")
                }
                .buttonStyle(PremiumButtonStyle())
                .accessibilityIdentifier("open-user-guide")
                SavedItemsView(session: session, kind: kind)
            }
            .padding(28)
            .frame(maxWidth: 900)
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background { WelcomeWatermark() }
    }

    private var categorySelector: some View {
        HStack(spacing: 12) {
            categoryButton(.project, artwork: .project)
            categoryButton(.document, artwork: .document)
        }
        .frame(maxWidth: 220)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L10n.text("Item type"))
        .accessibilityIdentifier("welcome-item-type")
    }

    private func categoryButton(_ category: FavoriteItem.Kind, artwork: PreferencesArtwork) -> some View {
        IllustratedSelectorButton(title: L10n.text(category.title), artwork: artwork, selected: kind == category) {
            kind = category
        }
        .accessibilityIdentifier("welcome-kind-\(category.rawValue)")
    }
}
