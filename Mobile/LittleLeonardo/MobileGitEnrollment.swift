import Foundation
import Observation
import LeonardoGit
import LeonardoSync

@MainActor @Observable
final class MobileGitEnrollment {
    var endpointText = ""
    var username = ""
    var password = ""
    var sshKeyAlgorithm: GitSSHKeyAlgorithm = .ed25519
    private(set) var sshPublicKey = ""
    var projectName = ""
    private(set) var discovery: GitRemoteDiscovery?
    private(set) var metadata: GitRepositoryMetadata?
    private(set) var branch = ""
    private(set) var folder = ""
    private(set) var folders: [String] = []
    private(set) var busy = false
    private(set) var hostKeyChallenge: GitSSHHostKeyChallenge?
    var error: String?
    private var reader: GitRemoteReader?
    private var endpoint: URL?
    private var sshPrivateKey: GitSSHPrivateKeyMaterial?
    private let sshPins = GitSSHHostKeyPinStore()

    var branches: [GitReference] {
        discovery?.references.filter { GitProjectConnection.isAllowedSourceBranch($0.name) && $0.objectID != nil } ?? []
    }

    var isSSHEndpoint: Bool {
        URL(string: endpointText.trimmingCharacters(in: .whitespacesAndNewlines))?.scheme?.lowercased() == "ssh"
    }

    func prepareSSHKeyIfNeeded() {
        guard isSSHEndpoint else { return }
        if sshPrivateKey?.algorithm == sshKeyAlgorithm { return }
        do {
            let key = try GitSSHPrivateKeyMaterial.generated(for: sshKeyAlgorithm)
            sshPrivateKey = key
            sshPublicKey = try key.openSSHPublicKey()
        } catch { report(error) }
    }

    func discover() async {
        guard !busy else { return }
        busy = true; defer { busy = false }
        do {
            guard let endpoint = URL(string: endpointText.trimmingCharacters(in: .whitespacesAndNewlines)) else { throw GitRemoteError.invalidEndpoint }
            self.endpoint = endpoint
            prepareSSHKeyIfNeeded()
            let reader = GitRemoteReader(transport: try makeTransport(endpoint: endpoint))
            let discovery = try await reader.discover()
            try Task.checkCancellation()
            guard discovery.references.contains(where: { GitProjectConnection.isAllowedSourceBranch($0.name) && $0.objectID != nil }) else {
                throw GitWireError.invalidObjectID
            }
            self.reader = reader; self.discovery = discovery; hostKeyChallenge = nil
        } catch let error as GitSSHError {
            if case .hostKeyConfirmationRequired(let challenge) = error {
                hostKeyChallenge = challenge
                self.error = nil
            } else { report(error) }
        } catch { report(error) }
    }

    /// Saves exactly the key observed during the previous handshake and retries
    /// discovery.  A pin is never inferred from a failed or unauthenticated
    /// request, and the private key is not decoded until SSH authentication.
    func confirmHostKey() async {
        guard !busy, let endpoint, let challenge = hostKeyChallenge else { return }
        busy = true; defer { busy = false }
        do {
            let sshEndpoint = try GitSSHEndpoint(url: endpoint, username: username.isEmpty ? nil : username)
            guard challenge.pin.host == sshEndpoint.host, challenge.pin.port == sshEndpoint.port else {
                throw GitSSHError.invalidHostKey
            }
            try await sshPins.save(challenge.pin, for: sshEndpoint)
            hostKeyChallenge = nil
            let reader = GitRemoteReader(transport: try makeTransport(endpoint: endpoint))
            let discovery = try await reader.discover()
            try Task.checkCancellation()
            guard discovery.references.contains(where: { GitProjectConnection.isAllowedSourceBranch($0.name) && $0.objectID != nil }) else {
                throw GitWireError.invalidObjectID
            }
            self.reader = reader; self.discovery = discovery
        } catch { report(error) }
    }

    func selectBranch(_ ref: GitReference) async {
        guard !busy, GitProjectConnection.isAllowedSourceBranch(ref.name), let reader,
              let discovery, let id = ref.objectID else { return }
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
            let sshCredential: GitSSHCredential?
            let storedUsername: String?
            if endpoint.scheme?.lowercased() == "ssh" {
                let sshEndpoint = try GitSSHEndpoint(url: endpoint, username: username.isEmpty ? nil : username)
                sshCredential = try makeSSHCredential(endpoint: sshEndpoint)
                storedUsername = sshEndpoint.username
            } else {
                guard username.isEmpty == password.isEmpty else { throw GitRemoteError.authenticationRequired }
                sshCredential = nil
                storedUsername = username.isEmpty ? nil : username
            }
            let connection = try GitProjectConnection(projectID: project.id, endpoint: endpoint, branch: branch,
                                                      scope: scope, username: storedUsername)
            let saved = await library.installGitProject(project, connection: connection, baseline: metadata.baseline,
                                                        password: endpoint.scheme?.lowercased() == "ssh" ? nil : (username.isEmpty ? nil : password),
                                                        sshCredential: sshCredential)
            if saved { password = "" }
            return saved
        } catch { report(error); return false }
    }

    private func makeTransport(endpoint: URL) throws -> any GitRemoteTransport {
        if endpoint.scheme?.lowercased() == "ssh" {
            let sshEndpoint = try GitSSHEndpoint(url: endpoint, username: username.isEmpty ? nil : username)
            guard let privateKey = sshPrivateKey else { throw GitSSHError.authenticationRequired }
            let endpointUsername = sshEndpoint.username
            return try GitSSHTransport(endpoint: sshEndpoint, pins: sshPins, credentialProvider: {
                try GitSSHCredential(username: endpointUsername, privateKey: privateKey)
            })
        }
        let user = username.isEmpty ? nil : username
        let secret = username.isEmpty ? nil : password
        guard username.isEmpty == password.isEmpty else { throw GitRemoteError.authenticationRequired }
        return try GitHTTPTransport(endpoint: endpoint, username: user, password: secret)
    }

    private func makeSSHCredential(endpoint: GitSSHEndpoint) throws -> GitSSHCredential {
        guard let privateKey = sshPrivateKey else {
            throw GitSSHError.authenticationRequired
        }
        return try GitSSHCredential(username: endpoint.username, privateKey: privateKey)
    }

    private func report(_ error: Error) {
        guard !(error is CancellationError) else { return }
        self.error = error.localizedDescription
    }
}
