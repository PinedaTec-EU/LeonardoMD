#if os(macOS)
import Foundation
import LeonardoGit
import LeonardoSync

enum DesktopGitIntegrationError: Error, Equatable, LocalizedError, Sendable {
    case invalidRepository
    case localRefConflict
    case remoteConflict(existing: String)
    case remoteVerificationFailed
    case outputTooLarge
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidRepository: return "The selected folder is not a Git repository."
        case .localRefConflict: return "A different local integration already uses this proposal ref."
        case .remoteConflict: return "The remote already contains a different result for this proposal."
        case .remoteVerificationFailed: return "The remote did not expose the exact integration commit after push."
        case .outputTooLarge: return "Git returned more data than LeonardoMD can safely inspect."
        case .commandFailed(let message): return message.isEmpty ? "Git command failed." : message
        }
    }
}

/// Builds and publishes a real Git integration commit without touching the
/// user's worktree or index. All Git mutations run under the native lease.
@MainActor
final class DesktopGitIntegrationPublisher {
    private let projectRoot: URL
    private let lease: NativeReconciliationLease
    private let process: DesktopGitIntegrationProcess
    private let outbox: DesktopGitIntegrationOutboxStore

    init(projectRoot: URL, stateRoot: URL,
         lease: NativeReconciliationLease = .shared,
         executableURL: URL = URL(fileURLWithPath: "/usr/bin/git")) {
        self.projectRoot = projectRoot.standardizedFileURL.resolvingSymlinksInPath()
        self.lease = lease
        self.process = DesktopGitIntegrationProcess(executableURL: executableURL)
        self.outbox = DesktopGitIntegrationOutboxStore(
            root: stateRoot.appendingPathComponent("GitIntegrationOutbox", isDirectory: true))
    }

    /// Creates the exact result commit, stores its durable push intent, and
    /// publishes only its immutable integration ref.
    func publish(receipt: GitIntegrationReceipt, remoteName: String,
                 identity: GitCommitIdentity,
                 message: String = "Little Leonardo integration") async throws -> GitIntegrationEnvelope {
        let selection = try CorpusSelection(folders: [receipt.scope.folder], documents: [])
        return try await lease.runApplication(projectRoot: projectRoot, selection: selection) {
            let envelope = try await self.prepareAndPublish(receipt: receipt, remoteName: remoteName,
                                                            identity: identity, message: message)
            return NativeReconciliationApplication(value: envelope, appliedNow: false,
                                                   appliedSnapshot: receipt.accepted)
        }
    }

    /// Retries every durable intent with its original local ref and commit.
    /// A failed entry remains in the outbox and is reported to the caller.
    func retryPending() async throws -> [GitIntegrationEnvelope] {
        let allEntries = try await outbox.all()
        let entries = allEntries.filter { $0.projectRoot == projectRoot }
        var published: [GitIntegrationEnvelope] = []
        for entry in entries {
            let selection = try CorpusSelection(folders: [entry.envelope.result.scope.folder], documents: [])
            let envelope = try await lease.runApplication(projectRoot: entry.projectRoot, selection: selection) {
                let value = try await self.publishEntry(entry)
                return NativeReconciliationApplication(value: value, appliedNow: false,
                                                       appliedSnapshot: entry.envelope.receipt.accepted)
            }
            published.append(envelope)
        }
        return published
    }

    func hasPending() async throws -> Bool {
        let entries = try await outbox.all()
        return entries.contains { $0.projectRoot == projectRoot }
    }

    private func prepareAndPublish(receipt: GitIntegrationReceipt, remoteName: String,
                                   identity: GitCommitIdentity,
                                   message: String) async throws -> GitIntegrationEnvelope {
        guard Self.isValidRemoteName(remoteName) else { throw DesktopGitCLIError.invalidRemote }
        guard projectRoot.isFileURL,
              (try? projectRoot.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else {
            throw DesktopGitIntegrationError.invalidRepository
        }

        if let existing = try await outbox.load(projectID: receipt.projectID, deviceID: receipt.deviceID,
                                                 proposalCommitID: receipt.commitID) {
            guard existing.envelope.receipt == receipt, existing.remoteName == remoteName,
                  existing.projectRoot == projectRoot else { throw SyncError.publicationPending }
            return try await publishEntry(existing)
        }

        let envelope = try await ensureLocalResult(receipt: receipt, identity: identity, message: message)
        let entry = try DesktopGitIntegrationOutboxEntry(envelope: envelope, projectRoot: projectRoot,
                                                         remoteName: remoteName)
        // This is the durable before-push boundary. A failed push leaves this
        // exact entry and the local immutable ref available for retry.
        try await outbox.save(entry)
        return try await publishEntry(entry)
    }

    private func ensureLocalResult(receipt: GitIntegrationReceipt,
                                   identity: GitCommitIdentity,
                                   message: String) async throws -> GitIntegrationEnvelope {
        let localRef = try GitIntegrationRef(deviceID: receipt.deviceID,
                                             projectID: receipt.projectID,
                                             proposalCommitID: receipt.commitID)
        if let existingID = try await readRef(localRef.name) {
            let data = try await command(["cat-file", "commit", existingID]).stdoutData
            let result = try GitIntegrationResult.parse(commitData: data, expectedCommitID: existingID)
            return try GitIntegrationEnvelope(result: result, receipt: receipt)
        }

        let before = try await workspaceFingerprint()
        // Keep the result fast-forwardable from the exact proposal branch tip.
        // The tree is based on the local HEAD separately, so files outside the
        // approved scope survive even when the desktop checkout has advanced.
        let treeBasisID = try await readHEAD()
        let treeID = try await buildTree(receipt: receipt, treeBasisID: treeBasisID)
        let built = try GitIntegrationResult.buildCommit(receipt: receipt,
                                                         parentCommitID: receipt.commitID,
                                                         treeID: treeID, identity: identity,
                                                         sourceRevision: treeBasisID, message: message)
        let writtenID = try await writeObject(kind: "commit", data: built.commit.data)
        guard writtenID == built.commit.id else { throw GitWireError.invalidObjectID }
        guard before == (try await workspaceFingerprint()) else {
            throw DesktopGitCLIError.workingTreeChanged
        }
        try await installLocalRef(localRef.name, commitID: built.commit.id)
        return try GitIntegrationEnvelope(result: built.result, receipt: receipt)
    }

    private func buildTree(receipt: GitIntegrationReceipt, treeBasisID: String) async throws -> String {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LeonardoMD-GitIntegration-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: directory) }
        let index = directory.appendingPathComponent("index")
        let environment = ["GIT_INDEX_FILE": index.path]

        try await command(["read-tree", treeBasisID], environment: environment)
        let existing = try await treeEntries(parentID: treeBasisID, scope: receipt.scope)
        for path in existing.keys.sorted() {
            // This index is a pure receipt tree. `--remove` is conditional on
            // the worktree file being absent; `--force-remove` makes a
            // historical deletion win even if the user recreated that path
            // after the receipt was accepted.
            try await command(["update-index", "--force-remove", "--", path], environment: environment)
        }

        for file in receipt.accepted.files.sorted(by: { $0.path < $1.path }) {
            try receipt.scope.validate(file.path)
            guard !file.isUnsavedBuffer else { throw SyncError.invalidSnapshot }
            let blobID = try await writeObject(kind: "blob", data: file.content)
            let mode = existing[file.path] ?? "100644"
            guard mode == "100644" || mode == "100755" else { throw GitWireError.invalidPack }
            try await command(["update-index", "--add", "--cacheinfo",
                               "\(mode),\(blobID),\(file.path)"],
                              environment: environment)
        }
        let result = try await command(["write-tree"], environment: environment)
        let treeID = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.isObjectID(treeID), treeID.count == treeBasisID.count else {
            throw GitWireError.invalidObjectID
        }
        return treeID
    }

    private func treeEntries(parentID: String, scope: CorpusScope) async throws -> [String: String] {
        var arguments = ["ls-tree", "-r", "-z", "--full-tree", parentID, "--"]
        if !scope.folder.isEmpty { arguments.append(":(literal)\(scope.folder)") }
        let result = try await command(arguments)
        var entries: [String: String] = [:]
        for record in result.stdoutData.split(separator: 0, omittingEmptySubsequences: true) {
            guard let line = String(data: Data(record), encoding: .utf8),
                  let tab = line.firstIndex(of: "\t") else { throw GitWireError.invalidPack }
            let header = line[..<tab].split(separator: " ", omittingEmptySubsequences: true)
            let path = String(line[line.index(after: tab)...])
            guard header.count == 3, header[1] == "blob",
                  ["100644", "100755"].contains(header[0]), Self.isObjectID(String(header[2])) else {
                continue
            }
            do { try scope.validate(path) }
            catch SyncError.excludedFile { continue }
            entries[path] = String(header[0])
        }
        return entries
    }

    private func writeObject(kind: String, data: Data) async throws -> String {
        let result = try await command(["hash-object", "-w", "-t", kind, "--stdin"], input: data)
        let id = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.isObjectID(id) else { throw GitWireError.invalidObjectID }
        return id
    }

    private func installLocalRef(_ ref: String, commitID: String) async throws {
        if let existing = try await readRef(ref) {
            guard existing == commitID else { throw DesktopGitIntegrationError.localRefConflict }
            return
        }
        let empty = String(repeating: "0", count: commitID.count)
        let result = try await rawCommand(["update-ref", ref, commitID, empty])
        guard result.exitCode == 0 else {
            if try await readRef(ref) == commitID { return }
            throw DesktopGitIntegrationError.commandFailed(Self.sanitize(result.stderr))
        }
    }

    private func readRef(_ ref: String) async throws -> String? {
        let result = try await rawCommand(["rev-parse", "--verify", "--quiet", ref])
        guard result.exitCode == 0 else { return nil }
        let id = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.isObjectID(id) else { throw GitWireError.invalidObjectID }
        return id
    }

    private func readHEAD() async throws -> String {
        let result = try await command(["rev-parse", "--verify", "HEAD^{commit}"])
        let id = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.isObjectID(id) else { throw GitWireError.invalidObjectID }
        return id
    }

    private func publishEntry(_ entry: DesktopGitIntegrationOutboxEntry) async throws -> GitIntegrationEnvelope {
        guard let localID = try await readRef(entry.localRef),
              localID == entry.envelope.integrationCommitID else {
            throw DesktopGitIntegrationError.localRefConflict
        }
        // Re-authenticate the durable envelope against the exact local commit
        // before retrying or notifying. A JSON outbox replay must never be
        // allowed to describe a different source revision than its Git tree.
        let localData = try await command(["cat-file", "commit", localID]).stdoutData
        let localResult = try GitIntegrationResult.parse(commitData: localData,
                                                         expectedCommitID: localID)
        guard localResult == entry.envelope.result else {
            throw DesktopGitIntegrationError.localRefConflict
        }
        let remoteID = try await remoteRef(entry.remoteName, ref: entry.localRef)
        if let remoteID {
            guard remoteID == entry.envelope.integrationCommitID else {
                throw DesktopGitIntegrationError.remoteConflict(existing: remoteID)
            }
        } else {
            let result = try await rawCommand(["push", "--no-tags", entry.remoteName,
                                               "\(entry.localRef):\(entry.localRef)"])
            guard result.exitCode == 0 else {
                throw DesktopGitIntegrationError.commandFailed(Self.sanitize(
                    result.stderr.isEmpty ? result.stdout : result.stderr))
            }
            guard try await remoteRef(entry.remoteName, ref: entry.localRef) ==
                    entry.envelope.integrationCommitID else {
                throw DesktopGitIntegrationError.remoteVerificationFailed
            }
        }
        // The durable receipt and outbox are the delivery contract. Remove the
        // intent only after the exact remote commit has been verified; a crash
        // before cleanup leaves the immutable entry available for an idempotent
        // retry.
        try await outbox.remove(projectID: entry.envelope.result.projectID,
                                deviceID: entry.envelope.result.deviceID,
                                proposalCommitID: entry.envelope.result.proposalCommitID)
        return entry.envelope
    }

    private func remoteRef(_ remote: String, ref: String) async throws -> String? {
        let result = try await command(["ls-remote", "--refs", remote, ref])
        for line in result.stdout.split(whereSeparator: { $0.isNewline }) {
            let fields = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
            guard fields.count == 2, String(fields[1]) == ref else { continue }
            let id = String(fields[0])
            guard Self.isObjectID(id) else { throw GitWireError.invalidObjectID }
            return id
        }
        return nil
    }

    private struct WorkspaceFingerprint: Equatable, Sendable {
        let status: Data
        let index: Data?
    }

    private func workspaceFingerprint() async throws -> WorkspaceFingerprint {
        let status = try await command(["status", "--porcelain=v2", "-z", "--untracked-files=all"]).stdoutData
        let indexPath = try await command(["rev-parse", "--git-path", "index"]).stdout
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let indexURL = URL(fileURLWithPath: indexPath, relativeTo: projectRoot).standardizedFileURL
        if FileManager.default.fileExists(atPath: indexURL.path) {
            guard try indexURL.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else {
                throw DesktopGitCLIError.invalidRepository
            }
        }
        let index = FileManager.default.fileExists(atPath: indexURL.path) ? try Data(contentsOf: indexURL) : nil
        guard index == nil || index!.count <= 64 * 1_024 * 1_024 else {
            throw DesktopGitIntegrationError.outputTooLarge
        }
        return WorkspaceFingerprint(status: status, index: index)
    }

    private func command(_ arguments: [String], input: Data? = nil,
                         environment: [String: String] = [:]) async throws -> DesktopGitIntegrationCommandResult {
        let result = try await rawCommand(arguments, input: input, environment: environment)
        guard result.exitCode == 0 else {
            let message = Self.sanitize(result.stderr.isEmpty ? result.stdout : result.stderr)
            if message.localizedCaseInsensitiveContains("not a git repository") {
                throw DesktopGitIntegrationError.invalidRepository
            }
            throw DesktopGitIntegrationError.commandFailed(message)
        }
        return result
    }

    private func rawCommand(_ arguments: [String], input: Data? = nil,
                            environment: [String: String] = [:]) async throws -> DesktopGitIntegrationCommandResult {
        try await process.run(arguments: arguments, at: projectRoot, input: input, environment: environment)
    }

    private static func isValidRemoteName(_ value: String) -> Bool {
        guard !value.isEmpty, value.utf8.count <= 256, !value.hasPrefix("-"), !value.contains(".."),
              !value.unicodeScalars.contains(where: {
                  CharacterSet.whitespacesAndNewlines.contains($0) || CharacterSet.controlCharacters.contains($0)
              }), !value.contains(where: { "~^:?*[\\".contains($0) }) else { return false }
        return true
    }

    private static func isObjectID(_ value: String) -> Bool {
        [40, 64].contains(value.utf8.count)
            && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
            && value.contains(where: { $0 != "0" })
    }

    private static func sanitize(_ value: String) -> String { DesktopGitCLIAdapter.sanitize(value) }
}

private struct DesktopGitIntegrationCommandResult: Sendable {
    let exitCode: Int32
    let stdoutData: Data
    let stderrData: Data

    var stdout: String { String(decoding: stdoutData, as: UTF8.self) }
    var stderr: String { String(decoding: stderrData, as: UTF8.self) }
}

private final class DesktopGitIntegrationProcess: @unchecked Sendable {
    private let executableURL: URL
    private let environment: [String: String]

    init(executableURL: URL) {
        self.executableURL = executableURL
        var environment = ProcessInfo.processInfo.environment
        environment["LC_ALL"] = "C"
        environment["LANG"] = "C"
        environment["GIT_TERMINAL_PROMPT"] = "0"
        self.environment = environment
    }

    func run(arguments: [String], at root: URL, input: Data? = nil,
             environment overrides: [String: String] = [:]) async throws -> DesktopGitIntegrationCommandResult {
        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        let stdoutCollector = Collector(limit: 80 * 1_024 * 1_024)
        let stderrCollector = Collector(limit: 2 * 1_024 * 1_024)
        process.executableURL = executableURL
        process.arguments = arguments
        process.currentDirectoryURL = root
        var processEnvironment = environment
        for (key, value) in overrides { processEnvironment[key] = value }
        process.environment = processEnvironment
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        if input == nil { process.standardInput = FileHandle.nullDevice }
        else { process.standardInput = Pipe() }

        let readers = DispatchGroup()
        DispatchQueue.global(qos: .utility).async(group: readers) {
            Self.collect(stdoutPipe.fileHandleForReading, into: stdoutCollector)
        }
        DispatchQueue.global(qos: .utility).async(group: readers) {
            Self.collect(stderrPipe.fileHandleForReading, into: stderrCollector)
        }

        return try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { process in
                readers.notify(queue: .global(qos: .utility)) {
                    if stdoutCollector.overflow || stderrCollector.overflow {
                        continuation.resume(throwing: DesktopGitIntegrationError.outputTooLarge)
                    } else {
                        continuation.resume(returning: DesktopGitIntegrationCommandResult(
                            exitCode: process.terminationStatus,
                            stdoutData: stdoutCollector.data,
                            stderrData: stderrCollector.data))
                    }
                }
            }
            do {
                try process.run()
                if let input, let pipe = process.standardInput as? Pipe {
                    pipe.fileHandleForWriting.write(input)
                    try? pipe.fileHandleForWriting.close()
                }
            } catch {
                process.terminationHandler = nil
                try? stdoutPipe.fileHandleForReading.close()
                try? stderrPipe.fileHandleForReading.close()
                continuation.resume(throwing: error)
            }
        }
    }

    private static func collect(_ handle: FileHandle, into collector: Collector) {
        while true {
            do {
                guard let chunk = try handle.read(upToCount: 64 * 1_024), !chunk.isEmpty else { return }
                collector.append(chunk)
            } catch { return }
        }
    }

    private final class Collector: @unchecked Sendable {
        private let lock = NSLock()
        private let limit: Int
        private var storage = Data()
        private(set) var overflow = false

        init(limit: Int) { self.limit = limit }

        var data: Data {
            lock.lock(); defer { lock.unlock() }
            return storage
        }

        func append(_ data: Data) {
            guard !data.isEmpty else { return }
            lock.lock(); defer { lock.unlock() }
            guard storage.count < limit else { overflow = true; return }
            let room = limit - storage.count
            storage.append(data.prefix(room))
            if data.count > room { overflow = true }
        }
    }
}
#endif
