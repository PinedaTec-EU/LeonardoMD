import SwiftUI
import LeonardoCore

struct FavoriteThemePicker: View {
    @Bindable var session: AppSession
    let url: URL
    let kind: FavoriteItem.Kind

    var body: some View {
        Picker(L10n.text("Theme"), selection: Binding(
            get: { session.favorite(url, kind: kind)?.palette?.rawValue ?? "inherit" },
            set: { session.setFavoritePalette(PaletteID(rawValue: $0), for: url, kind: kind) }
        )) {
            Text(L10n.text("Inherit")).tag("inherit")
            ForEach(PaletteCatalog.all) { palette in
                Text(palette.displayName).tag(palette.id.rawValue)
            }
        }
        .fixedSize()
        .help(L10n.text("Theme for this favorite"))
        .accessibilityLabel(L10n.text("Theme") + ": " + url.lastPathComponent)
        .accessibilityIdentifier("favorite-theme-" + kind.rawValue + "-" + url.path)
    }
}
