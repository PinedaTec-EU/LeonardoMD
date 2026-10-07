import SwiftUI

/// Uses the same session accent as action labels, including native macOS sheets.
struct PremiumSwitchStyle: ToggleStyle {
    @Environment(\.leonardoAccent) private var accent
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.label
            Spacer(minLength: 12)
            Button { configuration.isOn.toggle() } label: {
                Capsule()
                    .fill(configuration.isOn ? accent : Color.secondary.opacity(0.25))
                    .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                        Circle().fill(.white).padding(3)
                            .shadow(color: .black.opacity(0.15), radius: 1, y: 1)
                    }
                    .frame(width: 38, height: 22)
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityHidden(true)
            .opacity(enabled ? 1 : 0.42)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: configuration.isOn)
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(configuration.isOn ? "Activado" : "Desactivado")
        .accessibilityAddTraits(.isToggle)
        .accessibilityAction { if enabled { configuration.isOn.toggle() } }
    }
}
