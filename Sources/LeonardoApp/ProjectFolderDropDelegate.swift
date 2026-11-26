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
    var acceptsExternalFiles = true

    func validateDrop(info: DropInfo) -> Bool {
        guard (try? folder.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else {
            return false
        }
        if info.hasItemsConforming(to: [DocumentDropProviders.projectTreeItemType]) {
            return localSelection != nil
        }
        return acceptsExternalFiles && info.hasItemsConforming(to: [.fileURL])
    }

    func dropEntered(info: DropInfo) {
        _ = updateState(info: info)
        session.logger.debug("Folder drop target entered projectTree=\(info.hasItemsConforming(to: [DocumentDropProviders.projectTreeItemType]), privacy: .public) fileURL=\(info.hasItemsConforming(to: [.fileURL]), privacy: .public)")
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: updateState(info: info))
    }

    func dropExited(info: DropInfo) {
        state = .idle
    }

    func performDrop(info: DropInfo) -> Bool {
        state = .idle
        guard validateDrop(info: info) else { return false }
        let providers = providers(for: info)
        let isCopy = DocumentDropProviders.isProjectTreeDrop(providers) && optionKeyIsDown
        let selection = localSelection
        if let selection, !Self.canTransfer(selection, into: folder) { return false }
        let accepted = session.acceptDrop(providers, into: folder, copy: isCopy, expectedProjectURLs: selection)
        session.logger.info("Folder drop callback providers=\(providers.count, privacy: .public) projectTree=\(DocumentDropProviders.isProjectTreeDrop(providers), privacy: .public) copy=\(isCopy, privacy: .public) accepted=\(accepted, privacy: .public)")
        return accepted
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
        guard let localSelection, Self.canTransfer(localSelection, into: folder) else {
            state = .forbidden
            return .forbidden
        }
        let operation: DropOperation = optionKeyIsDown ? .copy : .move
        state = optionKeyIsDown ? .copy : .move
        if operation == .move, !supportsNativeMove { return .copy }
        return operation
    }

    // Same-folder moves are no-ops and same-folder copies acquire a unique
    // name. Cross-folder items keep their names and must fit without a clash.
    static func canTransfer(_ sources: [URL], into folder: URL) -> Bool {
        let parent = folder.standardizedFileURL
        let caseSensitive = (try? parent.resourceValues(forKeys: [.volumeSupportsCaseSensitiveNamesKey])
            .volumeSupportsCaseSensitiveNames) ?? false
        var seenNames: Set<String> = []
        for source in sources where source.deletingLastPathComponent().standardizedFileURL.path != parent.path {
            let name = source.lastPathComponent.precomposedStringWithCanonicalMapping
            let key = caseSensitive ? name : name.folding(options: [.caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            let target = parent.appendingPathComponent(name)
            if !seenNames.insert(key).inserted || FileManager.default.fileExists(atPath: target.path)
                || (try? target.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true {
                return false
            }
        }
        return true
    }

    private var localSelection: [URL]? {
        ProjectTreeDragSourceRegistry.shared.selection(for: session, destination: folder)
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
        let projectTreeProviders = info.itemProviders(for: [DocumentDropProviders.projectTreeItemType])
        let fileURLProviders = acceptsExternalFiles ? info.itemProviders(for: [.fileURL]) : []
        return DocumentDropProviders.preferredFolderDropProviders(
            projectTreeProviders: projectTreeProviders,
            fileURLProviders: fileURLProviders
        )
    }
}
