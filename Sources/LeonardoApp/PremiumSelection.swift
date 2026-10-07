import SwiftUI

/// Shared selection surface for document modes and preferences scope.
struct PremiumSelection<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [Value]
    let title: (Value) -> String

    var body: some View {
        HStack(spacing: 6) {
            ForEach(options, id: \.self) { option in
                Button { selection = option } label: {
                    Text(title(option)).frame(maxWidth: .infinity)
                }
                .buttonStyle(PremiumButtonStyle(compact: true, selected: selection == option))
                .accessibilityAddTraits(selection == option ? .isSelected : [])
            }
        }
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityElement(children: .contain)
    }
}
