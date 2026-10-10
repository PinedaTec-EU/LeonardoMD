import Foundation
import LeonardoCore
import LeonardoSync

@MainActor
struct DesktopSharedCorpus {
    let buffers: @MainActor (URL) -> [OpenDocumentBuffer]

    func source(_ project: MobileSharedProject) throws -> SharedProjectSource {
        let scope = try CorpusScope(folder: "")
        let selection = try CorpusSelection(folders: project.folders, documents: project.documents)
        let descriptor = SharedProjectDescriptor(id: project.id, name: project.name, scope: scope, selection: selection)
        let root = project.rootURL
        let reader = ProjectCorpusReader()
        let collect = buffers
        return SharedProjectSource(descriptor: descriptor, rootURL: root) {
            guard await MainActor.run(body: { !NativeReconciliationLease.shared.holds(root) }) else { throw DirectAuthorityError.busy }
            let drafts = await collect(root).filter { selection.contains($0.path) }
            let snapshot = try await reader.snapshot(root: root, selection: selection, buffers: drafts)
            guard await MainActor.run(body: { !NativeReconciliationLease.shared.holds(root) }) else { throw DirectAuthorityError.busy }
            return snapshot
        }
    }
}
