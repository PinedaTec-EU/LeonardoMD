import Foundation
import Observation
import LeonardoSync

/// Device-local removal intent, independent of Mac authorization and corpus contents.
@MainActor @Observable
final class MobileProjectLifecycle {
    private let demoRevision: Int
    private struct State: Codable {
        var deletedDemoRevision: Int?
        var deletedProjectIDs: Set<UUID> = []
    }
    private let url: URL
    private var state = State()
    var demoIsVisible: Bool {
        state.deletedDemoRevision.map { demoRevision > $0 } ?? true
    }

    init(url: URL, demoRevision: Int = MobileDemoStore.contentRevision) {
        self.url = url
        self.demoRevision = demoRevision
    }

    func reload() throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        state = try JSONDecoder().decode(State.self, from: Data(contentsOf: url))
    }

    func isDeleted(_ id: UUID) -> Bool { state.deletedProjectIDs.contains(id) }

    /// IDs whose device-local removal intent must win before a cache is decoded.
    var deletedProjectIDs: Set<UUID> { state.deletedProjectIDs }

    func deleteDemo() throws {
        var next = state
        next.deletedDemoRevision = demoRevision
        try commit(next)
    }

    func restoreDemo() throws {
        var next = state
        next.deletedDemoRevision = nil
        try commit(next)
    }

    func deleteProject(_ id: UUID) throws {
        var next = state
        next.deletedProjectIDs.insert(id)
        try commit(next)
    }

    private func commit(_ next: State) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(next).write(to: url, options: .atomic)
        state = next
    }
}

extension MobileLibrary {
    /// Persist intent before removing bytes; serializes against in-flight downloads.
    func deleteProject(_ id: UUID) async {
        guard !connecting else { return }
        let mutation = cacheMutations.enqueue { [weak self] in
            guard let self else { return }
            try self.projectLifecycle.deleteProject(id)
            self.projects.removeAll { $0.id == id }
            try await self.store.remove(id: id)
        }
        do { try await mutation.value }
        catch { self.error = error.localizedDescription }
    }
}

enum MobileLibraryProject: Identifiable {
    case demo
    case downloaded(OfflineProject)

    var id: String {
        switch self {
        case .demo: "bundled-demo"
        case .downloaded(let project): project.id.uuidString
        }
    }
    var name: String {
        switch self {
        case .demo: "Demo"
        case .downloaded(let project): project.name
        }
    }
}

extension MobileLibrary {
    var libraryProjects: [MobileLibraryProject] {
        var entries = projects.map(MobileLibraryProject.downloaded)
        if projectLifecycle.demoIsVisible { entries.append(.demo) }
        return entries.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func deleteLibraryProject(_ project: MobileLibraryProject) async {
        guard !connecting else { return }
        switch project {
        case .demo:
            do { try projectLifecycle.deleteDemo() }
            catch { self.error = error.localizedDescription }
        case .downloaded(let project): await deleteProject(project.id)
        }
    }
}
