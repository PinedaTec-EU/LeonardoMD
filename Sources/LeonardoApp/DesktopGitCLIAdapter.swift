#if os(macOS)
import Foundation
import LeonardoGit
import LeonardoSync

struct DesktopGitRemote: Codable, Equatable, Identifiable, Sendable {
    let name: String
    /// URLs are sanitized for display and never contain userinfo.
    let urls: [String]
    var id: String { name }
}

enum DesktopGitCLIError: Error, Equatable, LocalizedError, Sendable {
    case invalidRepository
    case invalidRemote
    case remoteNotFound
    case partialTransferUnavailable
    case workingTreeChanged
    case outputTooLarge
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidRepository: return "The selected folder is not a Git repository."
        case .invalidRemote: return "The selected Git remote name is invalid."
        case .remoteNotFound: return "The selected Git remote is unavailable."
        case .partialTransferUnavailable: return "This Git server does not support the filtered transfer required for a safe review."
        case .workingTreeChanged: return "The Git fetch changed the working tree or index. Review was stopped."
        case .outputTooLarge: return "Git returned more data than LeonardoMD can safely inspect."
        case .commandFailed(let message): return message.isEmpty ? "Git command failed." : message
        }
    }
}

/// A local Git process adapter for publication refs. Fetch updates only the
/// reserved `little-leonardo` namespace and leaves the worktree and index alone.
actor DesktopGitCLIAdapter {
    private struct WorkspaceFingerprint: Equatable, Sendable {
        let status: String
        let index: Data?
    }

    let projectRoot: URL
    private let executableURL: URL
    private let process: DesktopGitCLIProcess

    init(projectRoot: URL, executableURL: URL = URL(fileURLWithPath: "/usr/bin/git")) {
        self.projectRoot = projectRoot.standardizedFileURL.resolvingSymlinksInPath()
        self.executableURL = executableURL
        self.process = DesktopGitCLIProcess(executableURL: executableURL)
    }

    func remotes() async throws -> [DesktopGitRemote] {
        try validateRepository()
        let names = try await command(["remote"]).stdoutLines
        var result: [DesktopGitRemote] = []
        for name in names where !name.isEmpty {
            guard Self.isValidRemoteName(name) else { continue }
            let urls = try await command(["remote", "get-url", "--all", name]).stdoutLines
                .map(Self.sanitizedRemoteURL)
            result.append(DesktopGitRemote(name: name, urls: urls))
        }
        return result.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// Resolves the configured Git author identity without exposing any remote
    /// URL or credential helper data to the UI. The timestamp is captured when
    /// an integration is prepared; retries reuse the durable integration
    /// commit and therefore do not call this method again.
    func commitIdentity() async throws -> GitCommitIdentity {
        try validateRepository()
        let name: String
        let email: String
        do {
            name = try await command(["config", "--get", "user.name"]).stdout
                .trimmingCharacters(in: .whitespacesAndNewlines)
            email = try await command(["config", "--get", "user.email"]).stdout
                .trimmingCharacters(in: .whitespacesAndNewlines)
        } catch DesktopGitCLIError.invalidRepository {
            throw DesktopGitCLIError.invalidRepository
        } catch {
            throw DesktopGitCLIError.commandFailed("Git author identity is not configured for this repository.")
        }
        guard !name.isEmpty, !email.isEmpty else {
            throw DesktopGitCLIError.commandFailed("Git author identity is not configured for this repository.")
        }
        do {
            return try GitCommitIdentity(name: name, email: email,
                                         timestamp: Int64(Date().timeIntervalSince1970))
        } catch {
            throw DesktopGitCLIError.commandFailed("Git author identity is invalid for an integration commit.")
        }
    }

    /// Fetches only Little Leonardo publication refs using Git's configured
    /// credential helpers. `--filter=blob:none` is mandatory: this adapter never
    /// falls back to a full repository transfer when the server lacks filtering.
    func fetchPublishedBranches(remote: String) async throws -> [GitPublishedBranch] {
        try validateRepository()
        guard Self.isValidRemoteName(remote) else { throw DesktopGitCLIError.invalidRemote }
        guard try await remotes().contains(where: { $0.name == remote }) else {
            throw DesktopGitCLIError.remoteNotFound
        }
        let refspec = "+refs/heads/little-leonardo/*:refs/heads/little-leonardo/*"
        // A dry run lets us reject servers that silently ignore `--filter`
        // before a real pack transfer can fall back to every blob.
        let preflight = try await command(["fetch", "--dry-run", "--no-tags", "--filter=blob:none", remote, refspec])
        try Self.requireFilteredTransfer(preflight)
        let before = try await workspaceFingerprint()
        let result = try await command(["fetch", "--no-tags", "--filter=blob:none", remote, refspec])
        try Self.requireFilteredTransfer(result)
        guard before == (try await workspaceFingerprint()) else {
            throw DesktopGitCLIError.workingTreeChanged
        }
        return try await publishedBranches()
    }

    /// Reads one approved scope from the exact local object ID. The fetch is
    /// blob-filtered, so each `cat-file` below is the only selected content read.
    func snapshot(commitID: String, selection: CorpusSelection,
                  limits: CorpusLimits = CorpusLimits()) async throws -> CorpusSnapshot {
        guard Self.isObjectID(commitID) else { throw GitWireError.invalidObjectID }
        var arguments = ["ls-tree", "-r", "-z", "--full-tree", commitID, "--"]
        // An empty folder explicitly means the repository root. Passing an
        // empty literal pathspec would select nothing, so omit pathspecs for
        // that case and let ls-tree enumerate the complete tree.
        if !selection.folders.contains("") {
            arguments.append(contentsOf: (selection.folders + selection.documents).map { ":(literal)\($0)" })
        }
        let tree = try await command(arguments)
        var files: [CorpusFile] = []
        var byteCount = 0
        for record in tree.stdoutData.split(separator: 0, omittingEmptySubsequences: true) {
            guard let line = String(data: Data(record), encoding: .utf8),
                  let tab = line.firstIndex(of: "\t") else { throw GitWireError.invalidPack }
            let header = line[..<tab].split(separator: " ", omittingEmptySubsequences: true)
            let path = String(line[line.index(after: tab)...])
            guard header.count == 3, header[1] == "blob",
                  ["100644", "100755"].contains(header[0]),
                  selection.contains(path) else { continue }
            do { try selection.validate(path) }
            catch SyncError.excludedFile { continue }
            let objectID = String(header[2])
            guard Self.isObjectID(objectID) else { throw GitWireError.invalidObjectID }
            let blob = try await command(["cat-file", "blob", objectID])
            let content = blob.stdoutData
            guard content.count <= limits.maximumFileBytes,
                  content.count <= limits.maximumCorpusBytes - byteCount,
                  files.count < limits.maximumFiles else { throw SyncError.sizeLimitExceeded }
            byteCount += content.count
            files.append(CorpusFile(path: path, content: content))
        }
        let snapshot = CorpusSnapshot(revision: commitID,
                                      files: files.sorted { $0.path < $1.path })
        try selection.validate(snapshot, limits: limits)
        return snapshot
    }

    /// Serves the just-fetched local object database through Git protocol v2.
    /// The object store therefore remains blob-free until `GitRemoteReader`
    /// requests the selected file IDs after scope approval.
    func transport() -> DesktopGitCLITransport {
        DesktopGitCLITransport(projectRoot: projectRoot, executableURL: executableURL)
    }

    private func publishedBranches() async throws -> [GitPublishedBranch] {
        let result = try await command(["for-each-ref", "--format=%(refname)%00%(objectname)",
                                        "refs/heads/little-leonardo"])
        var branches: [GitPublishedBranch] = []
        for line in result.stdout.split(separator: "\n", omittingEmptySubsequences: true) {
            let fields = line.split(separator: "\0", omittingEmptySubsequences: false).map(String.init)
            guard fields.count == 2, fields[0].hasPrefix("refs/heads/little-leonardo/") else { continue }
            branches.append(try GitPublishedBranch(name: fields[0], commitID: fields[1]))
        }
        return branches.sorted {
            if $0.projectID != $1.projectID { return $0.projectID.uuidString < $1.projectID.uuidString }
            if $0.deviceID != $1.deviceID { return $0.deviceID.uuidString < $1.deviceID.uuidString }
            return $0.name < $1.name
        }
    }

    private func validateRepository() throws {
        guard projectRoot.isFileURL,
              (try? projectRoot.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else {
            throw DesktopGitCLIError.invalidRepository
        }
    }

    private func workspaceFingerprint() async throws -> WorkspaceFingerprint {
        let status = try await command(["status", "--porcelain=v2", "-z", "--untracked-files=all"]).stdout
        let indexPath = try await command(["rev-parse", "--git-path", "index"]).stdout
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let indexURL = URL(fileURLWithPath: indexPath, relativeTo: projectRoot).standardizedFileURL
        if FileManager.default.fileExists(atPath: indexURL.path) {
            let values = try indexURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard values.isRegularFile == true, (values.fileSize ?? 0) <= 64 * 1_024 * 1_024 else {
                throw DesktopGitCLIError.outputTooLarge
            }
            return WorkspaceFingerprint(status: status, index: try Data(contentsOf: indexURL))
        }
        return WorkspaceFingerprint(status: status, index: nil)
    }

    private func command(_ arguments: [String]) async throws -> DesktopGitCLIResult {
        let result = try await process.run(arguments: arguments, at: projectRoot)
        guard !result.outputOverflow else { throw DesktopGitCLIError.outputTooLarge }
        guard result.exitCode == 0 else {
            let message = Self.sanitize(result.stderr.isEmpty ? result.stdout : result.stderr)
            if message.localizedCaseInsensitiveContains("not a git repository") {
                throw DesktopGitCLIError.invalidRepository
            }
            throw DesktopGitCLIError.commandFailed(message)
        }
        return result
    }

    fileprivate static func isObjectID(_ value: String) -> Bool {
        [40, 64].contains(value.utf8.count)
            && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
            && value.contains(where: { $0 != "0" })
    }

    private static func requireFilteredTransfer(_ result: DesktopGitCLIResult) throws {
        let output = (result.stdout + "\n" + result.stderr).lowercased()
        if output.contains("filtering not recognized") || output.contains("filtering is not supported") ||
            output.contains("server does not support filtering") || output.contains("does not support filter") ||
            output.contains("filter not supported") || output.contains("filter not recognized") {
            throw DesktopGitCLIError.partialTransferUnavailable
        }
    }

    private static func isValidRemoteName(_ name: String) -> Bool {
        guard !name.isEmpty, name.utf8.count <= 256, !name.hasPrefix("-"), !name.contains(".."),
              !name.unicodeScalars.contains(where: { CharacterSet.whitespacesAndNewlines.contains($0) || CharacterSet.controlCharacters.contains($0) }),
              !name.contains(where: { "~^:?*[\\".contains($0) }) else { return false }
        return true
    }

    private static func sanitizedRemoteURL(_ value: String) -> String {
        // URLComponents treats an SCP-style remote such as
        // `alice@example.invalid:repo` as a scheme-like string rather than
        // URL userinfo. Strip the user before asking URLComponents to handle
        // ordinary `ssh://`/HTTP URLs.
        if !value.contains("://"),
           let at = value.firstIndex(of: "@"),
           let colon = value.firstIndex(of: ":"),
           at < colon,
           !value[..<at].isEmpty,
           !value[..<colon].unicodeScalars.contains(where: {
               CharacterSet.whitespacesAndNewlines.contains($0) || CharacterSet.controlCharacters.contains($0)
           }) {
            return sanitize(String(value[value.index(after: at)...]))
        }
        guard let url = URL(string: value), var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return sanitize(value)
        }
        components.user = nil
        components.password = nil
        return sanitize(components.string ?? value)
    }

    /// Redacts URL and SCP-style userinfo before Git diagnostics reach the UI.
    static func sanitize(_ value: String) -> String {
        var output = value
        if let regex = try? NSRegularExpression(pattern: "([A-Za-z][A-Za-z0-9+.-]*://)([^/@\\s:]+)(?::[^/@\\s]*)?@", options: []) {
            let range = NSRange(output.startIndex..<output.endIndex, in: output)
            output = regex.stringByReplacingMatches(in: output, options: [], range: range, withTemplate: "$1")
        }
        // Git's scp-like syntax (`user@host:path`) has no URL scheme, so the
        // URLComponents path above cannot remove its userinfo.
        if let regex = try? NSRegularExpression(pattern: "(^|[\\s'\"/])[^/@\\s:]+@(?=[^\\s:]+:)", options: []) {
            let range = NSRange(output.startIndex..<output.endIndex, in: output)
            output = regex.stringByReplacingMatches(in: output, options: [], range: range, withTemplate: "$1")
        }
        return output
    }
}

/// Implements the Git v2 upload-pack side against the local object database.
/// The command is configured to advertise filtering and arbitrary selected
/// object wants; it never invokes a remote URL or asks Git to touch the index.
actor DesktopGitCLITransport: GitRemoteTransport {
    private let projectRoot: URL
    private let process: DesktopGitCLIProcess

    init(projectRoot: URL, executableURL: URL = URL(fileURLWithPath: "/usr/bin/git")) {
        self.projectRoot = projectRoot.standardizedFileURL.resolvingSymlinksInPath()
        self.process = DesktopGitCLIProcess(executableURL: executableURL)
    }

    func advertisement() async throws -> Data {
        let result = try await process.run(arguments: Self.uploadPackArguments(advertise: true,
                                                                                repository: try await repositoryPath()),
                                           at: projectRoot, input: nil,
                                           environment: ["GIT_PROTOCOL": "version=2"])
        try Self.validate(result)
        return result.stdoutData
    }

    func uploadPack(request: Data) async throws -> Data {
        try await ensureRequestedObjects(in: request)
        let result = try await process.run(arguments: Self.uploadPackArguments(advertise: false,
                                                                                repository: try await repositoryPath()),
                                           at: projectRoot, input: request,
                                           environment: ["GIT_PROTOCOL": "version=2"])
        try Self.validate(result)
        return result.stdoutData
    }

    private func ensureRequestedObjects(in request: Data) async throws {
        let packets = try GitPacket.decode(request, maximumBytes: 2 * 1_024 * 1_024)
        for packet in packets {
            guard case .data(let data) = packet,
                  let line = String(data: data, encoding: .utf8),
                  line.hasPrefix("want ") else { continue }
            let fields = line.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\n" })
            guard fields.count == 2, fields[0] == "want" else { throw GitWireError.invalidObjectID }
            let objectID = String(fields[1])
            guard DesktopGitCLIAdapter.isObjectID(objectID) else { throw GitWireError.invalidObjectID }
            let result = try await process.run(arguments: ["cat-file", "-e", objectID], at: projectRoot)
            guard result.exitCode == 0 else {
                throw DesktopGitCLIError.commandFailed(DesktopGitCLIAdapter.sanitize(result.stderr))
            }
        }
    }

    private func repositoryPath() async throws -> String {
        let result = try await process.run(arguments: ["rev-parse", "--git-dir"], at: projectRoot)
        guard result.exitCode == 0, !result.outputOverflow else {
            throw DesktopGitCLIError.invalidRepository
        }
        let relative = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !relative.isEmpty else { throw DesktopGitCLIError.invalidRepository }
        return URL(fileURLWithPath: relative, relativeTo: projectRoot).standardizedFileURL.path
    }

    private static func uploadPackArguments(advertise: Bool, repository: String) -> [String] {
        var arguments = ["-c", "uploadpack.allowFilter=true", "-c", "uploadpack.allowAnySHA1InWant=true",
                         "upload-pack", "--stateless-rpc"]
        if advertise { arguments.append("--advertise-refs") }
        arguments.append("--strict")
        arguments.append(repository)
        return arguments
    }

    private static func validate(_ result: DesktopGitCLIResult) throws {
        guard result.exitCode == 0 else {
            throw DesktopGitCLIError.commandFailed(DesktopGitCLIAdapter.sanitize(result.stderr))
        }
        guard !result.outputOverflow else { throw DesktopGitCLIError.outputTooLarge }
    }
}

private struct DesktopGitCLIResult: Sendable {
    let arguments: [String]
    let exitCode: Int32
    let stdoutData: Data
    let stderrData: Data
    let outputOverflow: Bool

    var stdout: String { String(decoding: stdoutData, as: UTF8.self) }
    var stderr: String { String(decoding: stderrData, as: UTF8.self) }
    var stdoutLines: [String] { stdout.split(whereSeparator: { $0.isNewline }).map(String.init) }
}

private final class DesktopGitCLIProcess: @unchecked Sendable {
    private let executableURL: URL
    private let environment: [String: String]
    private let maximumStandardOutput = 80 * 1_024 * 1_024
    private let maximumStandardError = 1 * 1_024 * 1_024

    init(executableURL: URL) {
        self.executableURL = executableURL
        var environment = ProcessInfo.processInfo.environment
        environment["LC_ALL"] = "C"
        environment["LANG"] = "C"
        environment["GIT_TERMINAL_PROMPT"] = "0"
        self.environment = environment
    }

    func run(arguments: [String], at root: URL, input: Data? = nil,
             environment overrides: [String: String] = [:]) async throws -> DesktopGitCLIResult {
        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        let stdoutCollector = Collector(limit: maximumStandardOutput)
        let stderrCollector = Collector(limit: maximumStandardError)
        process.executableURL = executableURL
        process.arguments = arguments
        process.currentDirectoryURL = root
        var processEnvironment = environment
        for (key, value) in overrides { processEnvironment[key] = value }
        process.environment = processEnvironment
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        if input != nil { process.standardInput = Pipe() }

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
                    continuation.resume(returning: DesktopGitCLIResult(
                        arguments: arguments, exitCode: process.terminationStatus,
                        stdoutData: stdoutCollector.data, stderrData: stderrCollector.data,
                        outputOverflow: stdoutCollector.overflow || stderrCollector.overflow))
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
            } catch {
                return
            }
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
