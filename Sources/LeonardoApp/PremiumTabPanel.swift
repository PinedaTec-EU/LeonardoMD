import SwiftUI

/// Joined tabs sit across the top edge of one bordered options panel.
struct PremiumTabPanel<Value: Hashable, Content: View>: View {
    @Binding var selection: Value
    let options: [Value]
    let title: (Value) -> String
    @ViewBuilder let content: () -> Content
    @Environment(\.leonardoAccent) private var accent

    private let headerOverlap: CGFloat = 16

    var body: some View {
        content()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.top, headerOverlap)
            .background { PremiumControlBackground() }
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10).strokeBorder(.primary.opacity(0.18), lineWidth: 1)
            }
            .overlay(alignment: .top) {
                HStack(spacing: 0) {
                    ForEach(options, id: \.self) { option in
                        Button { selection = option } label: {
                            Text(title(option)).padding(.horizontal, 18).padding(.vertical, 8)
                        }
                        .buttonStyle(PremiumTabStyle(selected: selection == option))
                        .accessibilityAddTraits(selection == option ? .isSelected : [])
                    }
                }
                .background { PremiumControlBackground(compact: true) }
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8).strokeBorder(accent.opacity(0.30), lineWidth: 1)
                }
                .fixedSize()
                .accessibilityElement(children: .contain)
                .accessibilityLabel(L10n.text("Preferences section"))
                .accessibilityIdentifier("preferences-section")
                .offset(y: -headerOverlap)
            }
            .padding(.top, headerOverlap)
    }
}

private struct PremiumTabStyle: ButtonStyle {
    let selected: Bool
    @Environment(\.leonardoAccent) private var accent
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(selected ? accent : .secondary)
            .background {
                Rectangle().fill(selected ? accent.opacity(0.14) : .black.opacity(colorScheme == .dark ? 0.12 : 0.035))
                Rectangle().fill(LinearGradient(
                    colors: selected ? [.white.opacity(0.18), .clear, .black.opacity(0.035)] : [.black.opacity(0.09), .clear, .white.opacity(0.04)],
                    startPoint: .top, endPoint: .bottom))
            }
            .overlay {
                if selected {
                    RoundedRectangle(cornerRadius: 7).strokeBorder(accent.opacity(0.40), lineWidth: 1)
                }
            }
            .shadow(color: .black.opacity(selected ? 0.15 : 0), radius: 3, y: 1)
            .brightness(configuration.isPressed ? -0.035 : 0)
            .opacity(enabled ? 1 : 0.42)
    }
}
