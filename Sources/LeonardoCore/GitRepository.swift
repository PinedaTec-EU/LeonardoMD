import Foundation

public enum GitRepositoryState: String, Codable, Hashable, Sendable {
    case noRepository
    case clean
    case changesPending
    case conflicted
}

public enum GitChangeStatus: String, Codable, Hashable, Sendable {
    case added
    case modified
    case deleted
    case renamed
    case copied
    case typeChanged
    case untracked
    case conflicted
    case unknown
}

public struct GitChange: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let path: String
    public let status: GitChangeStatus
    public let isStaged: Bool
    public let hasWorktreeChanges: Bool

    public init(path: String, status: GitChangeStatus, isStaged: Bool, hasWorktreeChanges: Bool) {
        self.path = path
        self.id = path
        self.status = status
        self.isStaged = isStaged
        self.hasWorktreeChanges = hasWorktreeChanges
    }
}

public struct GitStatus: Codable, Hashable, Sendable {
    public let state: GitRepositoryState
    public let branch: String?
    public let ahead: Int
    public let behind: Int
    public let changes: [GitChange]

    public var isClean: Bool { state == .clean }
    public var hasConflicts: Bool { state == .conflicted }
    public var workingTreeState: GitRepositoryState { state }

    public init(
        state: GitRepositoryState,
        branch: String?,
        ahead: Int,
        behind: Int,
        changes: [GitChange]
    ) {
        self.state = state
        self.branch = branch
        self.ahead = ahead
        self.behind = behind
        self.changes = changes
    }
}

public struct GitCommit: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let hash: String
    public let shortHash: String
    public let author: String
    public let date: Date?
    public let subject: String

    public init(hash: String, shortHash: String, author: String, date: Date?, subject: String) {
        self.id = hash
        self.hash = hash
        self.shortHash = shortHash
        self.author = author
        self.date = date
        self.subject = subject
    }
}

public struct GitOperationResult: Sendable, Hashable {
    public let output: String
    public let errorOutput: String

    public init(output: String, errorOutput: String) {
        self.output = output
        self.errorOutput = errorOutput
    }
}

public protocol GitClient: Sendable {
    func initialize() async throws -> GitOperationResult
    func status() async throws -> GitStatus
    func stage(paths: [String]) async throws -> GitOperationResult
    func stageAll() async throws -> GitOperationResult
    func commit(message: String) async throws -> String
    func history(limit: Int) async throws -> [GitCommit]
    func fetch() async throws -> GitOperationResult
    func pull() async throws -> GitOperationResult
    func push() async throws -> GitOperationResult
}

public actor GitRepository: GitClient {
    public let rootURL: URL
    private let runner: GitProcessRunner

    public init(
        rootURL: URL,
        executableURL: URL = URL(fileURLWithPath: "/usr/bin/git")
    ) {
        self.rootURL = rootURL.standardizedFileURL
        self.runner = GitProcessRunner(executableURL: executableURL)
    }

    @discardableResult
    public func initialize() async throws -> GitOperationResult {
        let result = try await run(["init"])
        return operationResult(result)
    }

    public func status() async throws -> GitStatus {
        let result = try await runner.run(
            arguments: ["status", "--porcelain=v2", "-z", "--branch", "--untracked-files=all"],
            at: rootURL
        )
        if result.exitCode != 0 {
            if result.message.localizedCaseInsensitiveContains("not a git repository") {
                return GitStatus(state: .noRepository, branch: nil, ahead: 0, behind: 0, changes: [])
            }
            throw GitError.commandFailed(arguments: result.arguments, exitCode: result.exitCode, message: result.message)
        }
        return parseStatus(result.stdout)
    }

    @discardableResult
    public func stage(paths: [String]) async throws -> GitOperationResult {
        let current = try await status()
        try ensureRepository(current)
        if current.hasConflicts {
            throw GitError.mergeConflict(current.changes.filter { $0.status == .conflicted }.map(\.path))
        }
        let validated = try paths.map(validateRelativePath)
        let arguments = validated.isEmpty ? ["add", "-A", "--"] : ["add", "--"] + validated
        return operationResult(try await run(arguments))
    }

    @discardableResult
    public func stageAll() async throws -> GitOperationResult {
        try await stage(paths: [])
    }

    public func commit(message: String) async throws -> String {
        let current = try await status()
        try ensureRepository(current)
        if current.hasConflicts {
            throw GitError.mergeConflict(current.changes.filter { $0.status == .conflicted }.map(\.path))
        }
        guard !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw GitError.invalidCommitMessage
        }
        _ = try await run(["commit", "-m", message])
        let hash = try await run(["rev-parse", "HEAD"])
        return hash.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public func history(limit: Int = 20) async throws -> [GitCommit] {
        let current = try await status()
        try ensureRepository(current)
        guard limit > 0 else { return [] }
        let format = "%H%x1f%h%x1f%an%x1f%aI%x1f%s%x1e"
        let result = try await runner.run(
            arguments: ["log", "-n", String(limit), "--date=iso-strict", "--pretty=format:\(format)"],
            at: rootURL
        )
        if result.exitCode != 0 {
            if result.message.localizedCaseInsensitiveContains("does not have any commits") {
                return []
            }
            throw GitError.commandFailed(arguments: result.arguments, exitCode: result.exitCode, message: result.message)
        }
        return parseHistory(result.stdout)
    }

    @discardableResult
    public func fetch() async throws -> GitOperationResult {
        let current = try await status()
        try ensureRepository(current)
        return operationResult(try await run(["fetch", "--all", "--prune"]))
    }

    @discardableResult
    public func pull() async throws -> GitOperationResult {
        let current = try await status()
        try ensureRepository(current)
        try ensureSafeToSync(current)
        return operationResult(try await run(["pull", "--ff-only"]))
    }

    @discardableResult
    public func push() async throws -> GitOperationResult {
        let current = try await status()
        try ensureRepository(current)
        try ensureSafeToSync(current)
        return operationResult(try await run(["push"]))
    }

    private func run(_ arguments: [String]) async throws -> GitCommandResult {
        let result = try await runner.run(arguments: arguments, at: rootURL)
        guard result.exitCode == 0 else {
            throw GitError.commandFailed(arguments: result.arguments, exitCode: result.exitCode, message: result.message)
        }
        return result
    }

    private func ensureRepository(_ status: GitStatus) throws {
        guard status.state != .noRepository else { throw GitError.noRepository(rootURL) }
    }

    private func ensureSafeToSync(_ status: GitStatus) throws {
        if status.hasConflicts {
            throw GitError.mergeConflict(status.changes.filter { $0.status == .conflicted }.map(\.path))
        }
        if !status.isClean {
            throw GitError.workingTreeDirty
        }
    }

    private func operationResult(_ result: GitCommandResult) -> GitOperationResult {
        GitOperationResult(output: result.stdout, errorOutput: result.stderr)
    }

    private func parseStatus(_ output: String) -> GitStatus {
        var branch: String?
        var ahead = 0
        var behind = 0
        var changes: [GitChange] = []

        for record in output.split(separator: "\0", omittingEmptySubsequences: true) {
            let line = String(record)
            if line.hasPrefix("# branch.head ") {
                branch = String(line.dropFirst("# branch.head ".count))
                if branch == "(detached)" { branch = nil }
                continue
            }
            if line.hasPrefix("# branch.ab ") {
                let parts = line.split(separator: " ")
                for part in parts.dropFirst(2) {
                    if part.hasPrefix("+") { ahead = Int(part.dropFirst()) ?? 0 }
                    if part.hasPrefix("-") { behind = Int(part.dropFirst()) ?? 0 }
                }
                continue
            }
            if line.hasPrefix("1 ") {
                let fields = line.split(separator: " ", maxSplits: 8, omittingEmptySubsequences: true)
                guard fields.count >= 9 else { continue }
                let xy = String(fields[1])
                changes.append(GitChange(
                    path: String(fields[8]),
                    status: changeStatus(code: xy),
                    isStaged: xy.first != ".",
                    hasWorktreeChanges: xy.dropFirst().first != "."
                ))
                continue
            }
            if line.hasPrefix("2 ") {
                let fields = line.split(separator: " ", maxSplits: 9, omittingEmptySubsequences: true)
                guard fields.count >= 10 else { continue }
                let xy = String(fields[1])
                changes.append(GitChange(
                    path: String(fields[9]),
                    status: changeStatus(code: xy),
                    isStaged: xy.first != ".",
                    hasWorktreeChanges: xy.dropFirst().first != "."
                ))
                continue
            }
            if line.hasPrefix("u ") {
                let fields = line.split(separator: " ", maxSplits: 10, omittingEmptySubsequences: true)
                if let path = fields.last {
                    changes.append(GitChange(path: String(path), status: .conflicted, isStaged: true, hasWorktreeChanges: true))
                }
                continue
            }
            if line.hasPrefix("? ") {
                changes.append(GitChange(path: String(line.dropFirst(2)), status: .untracked, isStaged: false, hasWorktreeChanges: true))
            }
        }
        let state: GitRepositoryState = changes.contains(where: { $0.status == .conflicted })
            ? .conflicted
            : (changes.isEmpty ? .clean : .changesPending)
        return GitStatus(state: state, branch: branch, ahead: ahead, behind: behind, changes: changes)
    }

    private func parseHistory(_ output: String) -> [GitCommit] {
        let formatter = ISO8601DateFormatter()
        return output
            .split(separator: "\u{1e}")
            .compactMap { record in
                let normalized = record.trimmingCharacters(in: .whitespacesAndNewlines)
                let fields = normalized.split(separator: "\u{1f}", maxSplits: 4, omittingEmptySubsequences: false).map(String.init)
                guard fields.count == 5 else { return nil }
                return GitCommit(
                    hash: fields[0],
                    shortHash: fields[1],
                    author: fields[2],
                    date: formatter.date(from: fields[3]),
                    subject: fields[4]
                )
            }
    }

    private func validateRelativePath(_ path: String) throws -> String {
        guard !path.isEmpty,
              !path.hasPrefix("/"),
              !path.contains("\0"),
              !path.split(separator: "/").contains("..") else {
            throw GitError.invalidPath(path)
        }
        return path
    }

    private func changeStatus(code: String) -> GitChangeStatus {
        guard let first = code.first, let second = code.dropFirst().first else { return .unknown }
        if first == "U" || second == "U" { return .conflicted }
        switch first == "." ? second : first {
        case "A": return .added
        case "M": return .modified
        case "D": return .deleted
        case "R": return .renamed
        case "C": return .copied
        case "T": return .typeChanged
        default: return .unknown
        }
    }
}
