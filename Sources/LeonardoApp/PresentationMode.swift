import Foundation

enum DocumentMode: String, CaseIterable, Identifiable {
    case preview, edit, split
    var id: Self { self }
    var title: String {
        switch self {
        case .preview: "Lectura"
        case .edit: "Edición"
        case .split: "Dividida"
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
