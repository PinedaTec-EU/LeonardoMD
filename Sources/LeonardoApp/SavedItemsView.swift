import SwiftUI
import LeonardoCore

struct SavedItemsView: View {
    @Bindable var session: AppSession
    let kind: FavoriteItem.Kind

    private static let visibleRowLimit = 5
    private static let rowHeight: CGFloat = 48
    private static let rowSpacing: CGFloat = 4

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            favorites
            Divider()
            recentItems
            Divider()
            WelcomeRemoteItemsView(kind: kind, showNonDocumentFiles: session.showNonDocumentFiles)
        }
        .padding(20)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .accessibilityIdentifier("welcome-saved-items")
    }

    private var recentItems: some View {
        savedSection(
            title: "Recent items",
            urls: session.recentItems(kind), emptyMessage: "No recent items",
            identifier: "welcome-recent"
        )
    }

    private var favorites: some View {
        savedSection(
            title: "Favorites",
            urls: session.globalPreferences.favorites.filter { $0.kind == kind }.map(\.url),
            emptyMessage: "No favorites yet", identifier: "welcome-favorites"
        )
    }

    private func savedSection(
        title: String, urls: [URL],
        emptyMessage: String, identifier: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.text(title)).font(.title2.weight(.semibold))
            if urls.isEmpty {
                Text(L10n.text(emptyMessage))
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                savedList(urls, kind: kind)
                    .id(kind)
                    .accessibilityIdentifier(identifier + "-list")
            }
        }
    }

    private func savedList(_ urls: [URL], kind: FavoriteItem.Kind) -> some View {
        let visibleCount = min(urls.count, Self.visibleRowLimit)
        let height = CGFloat(visibleCount) * Self.rowHeight
            + CGFloat(max(0, visibleCount - 1)) * Self.rowSpacing
        return ScrollView(.vertical) {
            LazyVStack(spacing: Self.rowSpacing) {
                ForEach(urls, id: \.self) { url in
                    row(url, kind: kind).frame(height: Self.rowHeight)
                }
            }
        }
        .frame(height: height)
    }

    private func row(_ url: URL, kind: FavoriteItem.Kind) -> some View {
        let favorite = session.isFavorite(url, kind: kind)
        let available = FavoriteItem(kind: kind, url: url).isAvailable
        let presentation = kind == .project ? DesktopProjectPresentation.resolve(url, session: session) : nil
        return HStack(spacing: 12) {
            Button { Task { await session.openSavedItem(url, kind: kind) } } label: {
                HStack(spacing: 8) {
                    if let presentation { ProjectIdentityIcon(identity: presentation.identity) }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(url.lastPathComponent).lineLimit(1)
                        Text(savedItemDetail(url, presentation: presentation))
                            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!available)
            .help(available ? url.path : L10n.text("Item unavailable"))
            .accessibilityLabel(url.lastPathComponent)
            .accessibilityValue(savedItemDetail(url, presentation: presentation))
            if favorite, kind != .document {
                FavoriteThemePicker(session: session, url: url, kind: kind)
            }
            if !available { Image(systemName: "exclamationmark.triangle").help(L10n.text("Item unavailable")) }
            Button { session.toggleFavorite(url, kind: kind) } label: {
                Image(systemName: favorite ? "star.fill" : "star")
                    .foregroundStyle(favorite ? session.accentColor : .secondary)
            }
            .buttonStyle(.plain)
            .help(L10n.text(favorite ? "Remove from favorites" : "Add to favorites"))
            .accessibilityLabel(L10n.text(favorite ? "Remove from favorites" : "Add to favorites") + ": " + url.lastPathComponent)
            .accessibilityValue(L10n.text(favorite ? "Favorite" : "Not favorite"))
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .modifier(FileRowHighlight(accent: session.accentColor, enabled: available))
    }

    private func savedItemDetail(_ url: URL, presentation: DesktopProjectPresentation?) -> String {
        let path = url.deletingLastPathComponent().path
        guard let presentation else { return path }
        return [presentation.identity.title(languageCode: LanguageSettings.shared.language.rawValue),
                presentation.detail, path].compactMap { $0 }.joined(separator: " · ")
    }
}
