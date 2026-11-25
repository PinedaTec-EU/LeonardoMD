import SwiftUI

struct IllustratedSelectorButton: View {
    let title: String
    let artwork: PreferencesArtwork
    let selected: Bool
    let action: () -> Void

    @Environment(\.leonardoAccent) private var accent

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                artwork.illustration.frame(width: 72, height: 38)
                Text(title).font(.callout.weight(.semibold))
            }
            .frame(minWidth: 0, maxWidth: .infinity)
            .frame(height: 64)
            .background { PremiumControlBackground(selected: selected) }
            .overlay(alignment: .topTrailing) {
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(accent)
                        .padding(6)
                        .accessibilityHidden(true)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
