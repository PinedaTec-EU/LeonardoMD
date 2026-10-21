import SwiftUI

/// Shared pointer feedback for project, search and saved-item rows.
struct FileRowHighlight: ViewModifier {
    let accent: Color
    var selected = false
    var enabled = true
    @State private var hovered = false

    private var opacity: Double {
        if selected { return hovered && enabled ? 0.24 : 0.14 }
        return hovered && enabled ? 0.10 : 0
    }

    func body(content: Content) -> some View {
        content
            .background(accent.opacity(opacity), in: RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
            .onHover { hovered = $0 }
    }
}
