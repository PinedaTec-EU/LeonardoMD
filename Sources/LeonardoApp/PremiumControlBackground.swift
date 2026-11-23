import SwiftUI

/// Shared material, edge and lighting for action and text-entry surfaces.
struct PremiumControlBackground: View {
    var compact = false
    var prominent = false
    var selected = false
    var highlighted = false
    var pressed = false
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.leonardoAccent) private var accent

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: compact ? 8 : 10) }
    private var edge: Color { colorScheme == .dark ? .white.opacity(0.18) : .black.opacity(0.10) }

    var body: some View {
        shape.fill(.regularMaterial)
            .overlay {
                shape.fill(prominent ? accent.gradient : (selected ? accent.opacity(0.14) : Color.clear).gradient)
            }
            .overlay {
                shape.fill(LinearGradient(colors: [.white.opacity(highlighted ? 0.22 : 0.12), .clear, .black.opacity(pressed ? 0.12 : 0.035)], startPoint: .top, endPoint: .bottom))
            }
            .overlay {
                shape.strokeBorder(prominent ? .white.opacity(0.22) : (highlighted || selected) ? accent.opacity(0.45) : edge, lineWidth: 1)
            }
            .shadow(color: .black.opacity(pressed ? 0.03 : colorScheme == .dark ? 0.24 : 0.10), radius: pressed ? 1 : 4, x: 0, y: pressed ? 1 : 2)
    }
}
