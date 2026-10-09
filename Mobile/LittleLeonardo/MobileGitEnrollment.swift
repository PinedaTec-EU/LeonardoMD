import Foundation
import Observation
import LeonardoGit
import LeonardoSync

@MainActor @Observable
final class MobileGitEnrollment {
    var endpointText = ""
    var username = ""
    var password = ""
    var projectName = ""
    private(set) var discovery: GitRemoteDiscovery?
    private(set) var metadata: GitRepositoryMetadata?
    private(set) var branch = ""
    private(set) var folder = ""
    private(set) var folders: [String] = []
    private(set) var busy = false
    var error: String?
    private var reader: GitRemoteReader?
    private var endpoint: URL?

    var branches: [GitReference] { discovery?.references.filter { $0.name.hasPrefix("refs/heads/") && $0.objectID != nil } ?? [] }

    func discover() async {
        guard !busy else { return }
        busy = true; defer { busy = false }
        do {
            guard let endpoint = URL(string: endpointText.trimmingCharacters(in: .whitespacesAndNewlines)) else { throw GitRemoteError.invalidEndpoint }
            let user = username.isEmpty ? nil : username
            let secret = username.isEmpty ? nil : password
            guard username.isEmpty == password.isEmpty else { throw GitRemoteError.authenticationRequired }
            let reader = GitRemoteReader(transport: try GitHTTPTransport(endpoint: endpoint, username: user, password: secret))
            let discovery = try await reader.discover()
            try Task.checkCancellation()
            guard discovery.references.contains(where: { $0.name.hasPrefix("refs/heads/") && $0.objectID != nil }) else { throw GitWireError.invalidObjectID }
            self.endpoint = endpoint; self.reader = reader; self.discovery = discovery
        } catch { report(error) }
    }

    func selectBranch(_ ref: GitReference) async {
        guard !busy, let reader, let discovery, let id = ref.objectID else { return }
        busy = true; defer { busy = false }
        do {
            let metadata = try await reader.metadata(commitID: id, discovery: discovery)
            let folders = try metadata.index.folders()
            try Task.checkCancellation()
            self.metadata = metadata; self.branch = ref.name; self.folder = ""; self.folders = folders
        } catch { report(error) }
    }

    func selectFolder(_ path: String) {
        guard !busy, let metadata else { return }
        do { folders = try metadata.index.folders(in: path); folder = path }
        catch { report(error) }
    }

    func resetBranch() { guard !busy else { return }; metadata = nil; folder = ""; folders = [] }

    func importProject(into library: MobileLibrary) async -> Bool {
        guard !busy, let reader, let metadata, let endpoint else { return false }
        busy = true; defer { busy = false }
        do {
            let scope = try CorpusScope(folder: folder)
            let snapshot = try await reader.snapshot(metadata: metadata, scope: scope)
            try Task.checkCancellation()
            let name = projectName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, name.utf8.count <= 1_024 else { throw SyncError.invalidSnapshot }
            let project = try OfflineProject(name: name, mode: .git, scope: scope, snapshot: snapshot)
            let connection = try GitProjectConnection(projectID: project.id, endpoint: endpoint, branch: branch,
                                                      scope: scope, username: username.isEmpty ? nil : username)
            let saved = await library.installGitProject(project, connection: connection, baseline: metadata.baseline, password: username.isEmpty ? nil : password)
            if saved { password = "" }
            return saved
        } catch { report(error); return false }
    }

    private func report(_ error: Error) {
        guard !(error is CancellationError) else { return }
        self.error = error.localizedDescription
    }
}
