import SwiftUI

/// Text entry uses the action surface without obscuring editable text or native selection.
struct PremiumTextFieldStyle: TextFieldStyle {
    var compact = false
    @Environment(\.isEnabled) private var enabled
    @Environment(\.leonardoAccent) private var accent
    @FocusState private var focused: Bool
    @State private var hovered = false

    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .textFieldStyle(.plain)
            .focused($focused)
            .font(.system(size: compact ? 12 : 13))
            .padding(.horizontal, compact ? 10 : 15)
            .padding(.vertical, compact ? 7 : 10)
            .background {
                PremiumControlBackground(compact: compact, highlighted: focused || hovered)
            }
            .overlay {
                RoundedRectangle(cornerRadius: compact ? 8 : 10)
                    .strokeBorder(focused ? accent : .clear, lineWidth: 2)
            }
            .opacity(enabled ? 1 : 0.42)
            .onHover { hovered = $0 && enabled }
    }
}

/// NSAlert hosts the same field as SwiftUI screens while retaining modal return semantics.
@Observable
final class PremiumNameValue {
    var text: String
    init(_ text: String) { self.text = text }
}

struct PremiumNameInput: View {
    @Bindable var value: PremiumNameValue
    @FocusState private var focused: Bool

    var body: some View {
        TextField(L10n.text("Name"), text: $value.text)
            .textFieldStyle(PremiumTextFieldStyle())
            .focused($focused)
            .accessibilityIdentifier("name-input")
            .padding(6)
            .onAppear { focused = true }
    }
}
