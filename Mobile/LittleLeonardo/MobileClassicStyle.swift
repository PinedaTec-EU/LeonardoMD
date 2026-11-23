import SwiftUI
import LeonardoCore

/// The single supported mobile palette. Reuses the desktop's canonical tokens.
enum MobileClassic {
    private static let tokens = PaletteCatalog.leonardoClassic.tokens
    static let paper = color(tokens.surface)
    static let ink = color(tokens.text)
    static let heading = color(tokens.heading)
    static let accent = color(tokens.accent)
    static let border = color(tokens.border)
    static let secondary = color(tokens.quote)
    static let inset = color(tokens.codeBackground)
    static let canvas = Color(red: 0.97, green: 0.93, blue: 0.83)

    static func color(_ hex: String) -> Color {
        let value = UInt64(hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16) ?? 0
        return Color(red: Double((value >> 16) & 255) / 255,
                     green: Double((value >> 8) & 255) / 255,
                     blue: Double(value & 255) / 255)
    }

    @MainActor static func configureAppearance() {
        let navigation = UINavigationBarAppearance()
        navigation.configureWithOpaqueBackground()
        navigation.backgroundColor = UIColor(paper)
        navigation.titleTextAttributes = [.foregroundColor: UIColor(heading)]
        navigation.largeTitleTextAttributes = [.foregroundColor: UIColor(heading)]
        UINavigationBar.appearance().standardAppearance = navigation
        UINavigationBar.appearance().scrollEdgeAppearance = navigation
        UINavigationBar.appearance().compactAppearance = navigation
        let toolbar = UIToolbarAppearance()
        toolbar.configureWithOpaqueBackground()
        toolbar.backgroundColor = UIColor(paper)
        UIToolbar.appearance().standardAppearance = toolbar
        UIToolbar.appearance().scrollEdgeAppearance = toolbar
    }
}

extension View {
    func classicSurface() -> some View {
        self.scrollContentBackground(.hidden)
            .background(MobileClassic.paper)
            .foregroundStyle(MobileClassic.ink)
            .tint(MobileClassic.accent)
            .toolbarBackground(MobileClassic.paper, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
    }
}

struct MobileBrand: View {
    var size: CGFloat = 96
    var body: some View {
        Image("LeonardoBrand").resizable().scaledToFit()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}
