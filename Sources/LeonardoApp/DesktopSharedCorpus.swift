import Foundation
import LeonardoCore
import LeonardoSync

@MainActor
struct DesktopSharedCorpus {
    let buffers: @MainActor (URL) -> [OpenDocumentBuffer]

    func source(_ project: MobileSharedProject) throws -> SharedProjectSource {
        let scope = try CorpusScope(folder: "")
        let descriptor = SharedProjectDescriptor(id: project.id, name: project.name, scope: scope)
        let root = project.rootURL
        let reader = ProjectCorpusReader()
        let collect = buffers
        return SharedProjectSource(descriptor: descriptor) {
            let drafts = await collect(root)
            return try await reader.snapshot(root: root, scope: scope, revision: UUID().uuidString, buffers: drafts)
        }
    }
}
