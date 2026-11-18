import AppKit
import SwiftUI

enum ProjectFolderDropState: Equatable {
    case idle
    case move
    case copy
    case open
    case forbidden

    var label: String? {
        switch self {
        case .move: "Move"
        case .copy: "Copy"
        case .open, .idle, .forbidden: nil
        }
    }

    var symbol: String? {
        switch self {
        case .move: "arrow.down.to.line"
        case .copy: "plus"
        case .open, .idle, .forbidden: nil
        }
    }

    var isTarget: Bool {
        self == .move || self == .copy || self == .open
    }
}

@MainActor
struct ProjectFolderDropDelegate: DropDelegate {
    let folder: URL
    let session: AppSession
    @Binding var state: ProjectFolderDropState

    func validateDrop(info: DropInfo) -> Bool {
        guard (try? folder.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else {
            return false
        }
        return info.hasItemsConforming(to: [.fileURL])
    }

    func dropEntered(info: DropInfo) {
        _ = updateState(info: info)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: updateState(info: info))
    }

    func dropExited(info: DropInfo) {
        state = .idle
    }

    func performDrop(info: DropInfo) -> Bool {
        let providers = providers(for: info)
        let isCopy = DocumentDropProviders.isProjectTreeDrop(providers) && optionKeyIsDown
        state = .idle
        return session.acceptDrop(providers, into: folder, copy: isCopy)
    }

    private func updateState(info: DropInfo) -> DropOperation {
        guard validateDrop(info: info) else {
            state = .forbidden
            return .forbidden
        }
        guard info.hasItemsConforming(to: [DocumentDropProviders.projectTreeItemType]) else {
            state = .open
            return .copy
        }
        let operation: DropOperation = optionKeyIsDown ? .copy : .move
        state = optionKeyIsDown ? .copy : .move
        if operation == .move, !supportsNativeMove { return .copy }
        return operation
    }

    private var optionKeyIsDown: Bool {
        NSApp.currentEvent?.modifierFlags.contains(.option) == true
    }

    private var supportsNativeMove: Bool {
        if #available(macOS 26.0, *) { return true }
        return false
    }

    private func providers(for info: DropInfo) -> [NSItemProvider] {
        // SwiftUI only permits querying providers during performDrop(info:).
        info.itemProviders(for: [DocumentDropProviders.projectTreeItemType, .fileURL])
    }
}
