import SwiftUI

/// Shared pointer feedback for project, search and saved-item rows.
struct FileRowHighlight: ViewModifier {
    let accent: Color
    var selected = false
    var enabled = true
    var dropTarget = false
    @State private var hovered = false

    private var opacity: Double {
        if dropTarget { return selected ? 0.30 : 0.20 }
        if selected { return hovered && enabled ? 0.24 : 0.14 }
        return hovered && enabled ? 0.10 : 0
    }

    func body(content: Content) -> some View {
        content
            .background(accent.opacity(opacity), in: RoundedRectangle(cornerRadius: 6))
            .overlay {
                if dropTarget {
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(accent.opacity(0.75), lineWidth: 1.5)
                }
            }
            .contentShape(Rectangle())
            .onHover { hovered = $0 }
    }
}
