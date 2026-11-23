import Foundation
import LeonardoCore
import LeonardoSync

@MainActor
struct DesktopSharedCorpus {
    let buffers: @MainActor (URL) async throws -> [OpenDocumentBuffer]

    func source(_ project: MobileSharedProject) throws -> SharedProjectSource {
        let scope = try CorpusScope(folder: "")
        let selection = try CorpusSelection(folders: project.folders, documents: project.documents)
        let descriptor = SharedProjectDescriptor(id: project.id, name: project.name, scope: scope, selection: selection)
        let root = project.rootURL
        let reader = ProjectCorpusReader()
        let collect = buffers
        let buildSnapshot: @Sendable (Set<String>) async throws -> CorpusSnapshot = { excludedExtensions in
            guard await MainActor.run(body: { !NativeReconciliationLease.shared.holds(root) }) else { throw DirectAuthorityError.busy }
            let excluded = Set(excludedExtensions.map { $0.lowercased() })
            let drafts = try await collect(root).filter {
                selection.contains($0.path) && !excluded.contains(($0.path as NSString).pathExtension.lowercased())
            }
            let snapshot = try await reader.snapshot(root: root, selection: selection, buffers: drafts,
                excludingExtensions: excluded)
            guard await MainActor.run(body: { !NativeReconciliationLease.shared.holds(root) }) else { throw DirectAuthorityError.busy }
            return snapshot
        }
        return SharedProjectSource(descriptor: descriptor, rootURL: root,
            snapshot: { try await buildSnapshot([]) }, snapshotExcludingExtensions: buildSnapshot)
    }
}
