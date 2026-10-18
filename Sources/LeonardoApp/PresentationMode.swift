import Foundation

enum DocumentMode: String, CaseIterable, Identifiable {
    case preview, edit, split, fill
    var id: Self { self }
    @MainActor var title: String {
        switch self {
        case .preview: L10n.text("Preview")
        case .edit: L10n.text("Edit")
        case .split: L10n.text("Split")
        case .fill: L10n.text("Fill form")
        }
    }
}

/// Standalone viewing and focus are orthogonal: focus never creates a project.
struct PresentationMode: Equatable {
    var projectURL: URL?
    var focus = false
    var inspectorRequested = false
    var showsSidebar: Bool { projectURL != nil && !focus }
    var showsInspector: Bool { inspectorRequested && !focus }
    var isStandalone: Bool { projectURL == nil }
}
