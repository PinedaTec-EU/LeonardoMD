import SwiftUI
import LeonardoCore

struct FavoriteThemePicker: View {
    @Bindable var session: AppSession
    let url: URL
    let kind: FavoriteItem.Kind

    private var selection: Binding<String> {
        Binding(get: { session.favorite(url, kind: kind)?.palette?.rawValue ?? "inherit" },
                set: { session.setFavoritePalette(PaletteID(rawValue: $0), for: url, kind: kind) })
    }

    private var selectedTitle: String {
        session.favorite(url, kind: kind)?.palette.map { PaletteCatalog.definition(for: $0).displayName }
            ?? L10n.text("Inherit")
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(L10n.text("Theme"))
            Menu {
                Picker(L10n.text("Theme"), selection: selection) {
                    Text(L10n.text("Inherit")).tag("inherit")
                    ForEach(PaletteCatalog.all) { palette in
                        Text(palette.displayName).tag(palette.id.rawValue)
                    }
                }
            } label: {
                Text(selectedTitle)
            }
            .menuStyle(.borderlessButton)
            // Native menu labels also read accentColor; keep both tied to session text.
            .tint(Color(hex: session.palette.tokens.text))
            .accentColor(Color(hex: session.palette.tokens.text))
            .help(L10n.text("Theme for this favorite"))
            .accessibilityLabel(L10n.text("Theme") + ": " + url.lastPathComponent)
            .accessibilityValue(selectedTitle)
            .accessibilityIdentifier("favorite-theme-" + kind.rawValue + "-" + url.path)
        }
        .fixedSize()
    }
}
