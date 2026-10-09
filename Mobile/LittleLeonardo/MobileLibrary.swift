import Foundation
import Observation
import LeonardoSync

@MainActor @Observable
final class MobileLibrary {
    private(set) var projects: [OfflineProject] = []
    var error: String?
    private let store: OfflineCorpusStore
    private var savingProjects: Set<UUID> = []

    init() {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LittleLeonardo/Corpus", isDirectory: true)
        store = OfflineCorpusStore(root: root)
    }

    func reload() async {
        guard savingProjects.isEmpty else { return }
        do {
            var loaded: [OfflineProject] = []
            for id in try await store.projectIDs() {
                if let project = try await store.load(id: id) { loaded.append(project) }
            }
            guard savingProjects.isEmpty else { return }
            projects = loaded.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        } catch { self.error = error.localizedDescription }
    }

    func saveText(projectID: UUID, path: String, text: String) async -> Bool {
        await mutate(projectID: projectID) { try $0.write(path: path, content: Data(text.utf8)) }
    }

    func createDocument(projectID: UUID, path: String) async -> Bool {
        await mutate(projectID: projectID) { project in
            let canonical = path.precomposedStringWithCanonicalMapping.lowercased()
            guard !project.files.contains(where: { $0.path.precomposedStringWithCanonicalMapping.lowercased() == canonical }) else {
                throw SyncError.invalidPath
            }
            try project.write(path: path, content: Data())
        }
    }

    func deleteFile(projectID: UUID, path: String) async -> Bool {
        await mutate(projectID: projectID) { try $0.delete(path: path) }
    }

    private func mutate(projectID: UUID, operation: (inout OfflineProject) throws -> Void) async -> Bool {
        guard !savingProjects.contains(projectID),
              let project = projects.first(where: { $0.id == projectID }) else { return false }
        savingProjects.insert(projectID)
        defer { savingProjects.remove(projectID) }
        do {
            var updated = project
            try operation(&updated)
            try await store.save(updated)
            if let index = projects.firstIndex(where: { $0.id == projectID }) { projects[index] = updated }
            return true
        } catch { self.error = error.localizedDescription; return false }
    }
}
