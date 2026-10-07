import AppKit

/// AppKit presents its modal window while the main actor remains available
/// for initialization, SwiftUI updates and asynchronous file operations.
@MainActor
func presentFilePanel(_ panel: NSSavePanel, completion: @escaping @MainActor (URL) -> Void) {
    panel.begin { response in
        guard response == .OK, let url = panel.url else { return }
        completion(url)
    }
}
