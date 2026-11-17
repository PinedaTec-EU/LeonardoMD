import SwiftUI

struct ProjectTreeDragSource: ViewModifier {
    let url: URL
    let selectedURLs: () -> [URL]

    @ViewBuilder
    func body(content: Content) -> some View {
        let draggable = content.onDrag {
            let urls = selectedURLs()
            return DocumentDropProviders.projectTreeItemProvider(for: url, selecting: urls)
        }
        if #available(macOS 26.0, *) {
            draggable.dragConfiguration(DragConfiguration(
                operationsWithinApp: .init(allowCopy: true, allowMove: true),
                operationsOutsideApp: .init(allowCopy: true)
            ))
        } else {
            draggable
        }
    }
}
