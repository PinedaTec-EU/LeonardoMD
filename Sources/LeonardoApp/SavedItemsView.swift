import SwiftUI
import LeonardoCore

struct SavedItemsView: View {
    @Bindable var session: AppSession
    @State var recentKind: FavoriteItem.Kind = .document

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            favorites
            Divider()
            recentItems
        }
        .padding(20)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .accessibilityIdentifier("welcome-saved-items")
    }

    private var recentItems: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.text("Recent items")).font(.title2.weight(.semibold))
            Picker(L10n.text("Recent items"), selection: $recentKind) {
                ForEach(FavoriteItem.Kind.allCases, id: \.self) { kind in
                    Text(L10n.text(kind.title)).tag(kind)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .accessibilityIdentifier("welcome-recent-tabs")
            let urls = session.recentItems(recentKind)
            if urls.isEmpty {
                Text(L10n.text("No recent items"))
                    .font(.caption).foregroundStyle(.secondary)
            }
            ForEach(urls, id: \.self) { url in row(url, kind: recentKind) }
        }
    }

    private var favorites: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.text("Favorites")).font(.title2.weight(.semibold))
            ForEach(FavoriteItem.Kind.allCases, id: \.self) { kind in
                let urls = session.globalPreferences.favorites.filter { $0.kind == kind }.map(\.url)
                VStack(alignment: .leading, spacing: 6) {
                    Label(L10n.text(kind.title), systemImage: kind.symbol).font(.headline)
                    if urls.isEmpty {
                        Text(L10n.text("No favorites yet"))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    ForEach(urls, id: \.self) { url in row(url, kind: kind) }
                }
            }
        }
    }

    private func row(_ url: URL, kind: FavoriteItem.Kind) -> some View {
        let favorite = session.isFavorite(url, kind: kind)
        let available = FavoriteItem(kind: kind, url: url).isAvailable
        return HStack(spacing: 12) {
            Button { Task { await session.openSavedItem(url, kind: kind) } } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(url.lastPathComponent).lineLimit(1)
                    Text(url.deletingLastPathComponent().path).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!available)
            .help(available ? url.path : L10n.text("Item unavailable"))
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
    }
}
