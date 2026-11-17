import SwiftUI

struct ProjectTreeDragSource: ViewModifier {
    let url: URL

    @ViewBuilder
    func body(content: Content) -> some View {
        let draggable = content.onDrag {
            DocumentDropProviders.projectTreeItemProvider(for: url)
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
