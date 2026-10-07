import SwiftUI

private struct LeonardoAccentKey: EnvironmentKey {
    static let defaultValue = Color.accentColor
}
extension EnvironmentValues {
    var leonardoAccent: Color {
        get { self[LeonardoAccentKey.self] }
        set { self[LeonardoAccentKey.self] = newValue }
    }
}

struct SessionAppearance: ViewModifier {
    let session: AppSession
    func body(content: Content) -> some View {
        content.tint(session.accentColor).accentColor(session.accentColor)
            .environment(\.leonardoAccent, session.accentColor)
            .preferredColorScheme(session.darkPalette ? .dark : .light)
    }
}

/// A restrained tactile surface shared by document, project and settings actions.
struct PremiumButtonStyle: ButtonStyle {
    var prominent = false
    var compact = false
    func makeBody(configuration: Configuration) -> some View {
        Surface(configuration: configuration, prominent: prominent, compact: compact)
    }

    private struct Surface: View {
        let configuration: Configuration
        let prominent: Bool
        let compact: Bool
        @Environment(\.isEnabled) private var enabled
        @Environment(\.colorScheme) private var colorScheme
        @State private var hovered = false
        @Environment(\.leonardoAccent) private var accent
        private var edge: Color { colorScheme == .dark ? .white.opacity(0.18) : .black.opacity(0.10) }
        var body: some View {
            configuration.label
                .font(.system(size: compact ? 12 : 13, weight: .semibold))
                .foregroundStyle(prominent ? (colorScheme == .dark ? Color.black.opacity(0.85) : Color.white) : accent)
                .padding(.horizontal, compact ? 10 : 15)
                .padding(.vertical, compact ? 7 : 10)
                .background {
                    RoundedRectangle(cornerRadius: compact ? 8 : 10)
                        .fill(.regularMaterial)
                    RoundedRectangle(cornerRadius: compact ? 8 : 10)
                        .fill(prominent ? accent.gradient : Color.clear.gradient)
                    RoundedRectangle(cornerRadius: compact ? 8 : 10)
                        .fill(LinearGradient(colors: [.white.opacity(hovered ? 0.22 : 0.12), .clear, .black.opacity(configuration.isPressed ? 0.12 : 0.035)], startPoint: .top, endPoint: .bottom))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: compact ? 8 : 10)
                        .strokeBorder(prominent ? .white.opacity(0.22) : hovered ? accent.opacity(0.45) : edge, lineWidth: 1)
                }
                .shadow(color: .black.opacity(configuration.isPressed ? 0.03 : colorScheme == .dark ? 0.24 : 0.10), radius: configuration.isPressed ? 1 : 4, x: 0, y: configuration.isPressed ? 1 : 2)
                .scaleEffect(configuration.isPressed ? 0.98 : 1)
                .brightness(hovered && enabled ? 0.025 : 0)
                .opacity(enabled ? 1 : 0.42)
                .onHover { hovered = $0 }
                .animation(.easeOut(duration: 0.12), value: hovered)
                .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
        }
    }
}
