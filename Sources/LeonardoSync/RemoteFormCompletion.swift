import Foundation
import LeonardoCore

/// Commands address only one existing form within a granted project. A mobile
/// client never supplies a destination or replacement document.
public struct RemoteFormCompletionCommand: Codable, Sendable {
    public enum Action: String, Codable, Sendable {
        case acquire, status, finish, cancel
    }

    public let action: Action
    public let sessionID: UUID
    public let path: String
    public let revision: String
    public let values: [String: LeonardoJSONValue]?

    public init(action: Action, sessionID: UUID, path: String, revision: String,
                values: [String: LeonardoJSONValue]? = nil) {
        self.action = action
        self.sessionID = sessionID
        self.path = path
        self.revision = revision
        self.values = values
    }
}

public struct RemoteFormCompletionReceipt: Codable, Sendable {
    public enum State: String, Codable, Sendable {
        case active, completed, cancelled, revoked
    }

    public let sessionID: UUID
    public let state: State

    public init(sessionID: UUID, state: State) {
        self.sessionID = sessionID
        self.state = state
    }
}

public enum RemoteFormCompletionError: Error, Equatable, Sendable {
    case unsupported
    case invalidCommand
    case busy
    case staleRevision
    case inactive
    case invalidResponse
    case unexpectedStatus(Int)
}

/// The authority calls this synchronously so a local persistence transaction
/// cannot commit after a concurrent grant or device revocation.
public protocol RemoteFormCompletionHosting: Sendable {
    func handle(_ command: RemoteFormCompletionCommand, deviceID: UUID,
                source: SharedProjectSource) throws -> RemoteFormCompletionReceipt
}

/// Computes the same revision from either the authorized offline cache or the
/// saved Mac source. Missing or disallowed resources prevent acquisition.
public struct RemoteFormSource: Sendable {
    public let document: LeonardoDocument
    public let revision: String

    public init(file: CorpusFile, resource: (String) throws -> CorpusFile) throws {
        guard !file.isUnsavedBuffer, let source = String(data: file.content, encoding: .utf8) else {
            throw RemoteFormCompletionError.staleRevision
        }

        let document: LeonardoDocument
        let references: [String]
        do {
            document = try LeonardoFormatParser.parse(source)
            references = try LeonardoLocalImagePolicy.signingReferences(in: document)
        } catch {
            throw RemoteFormCompletionError.invalidCommand
        }
        guard document.isForm, document.metadata.document.signing == nil,
              document.metadata.fields.values.contains(where: { !$0.readOnly }) else {
            throw RemoteFormCompletionError.invalidCommand
        }

        let parent = file.path.split(separator: "/").dropLast().joined(separator: "/")
        let paths = Set(try references.map { reference in
            guard let path = LeonardoLocalImagePolicy.portableSigningImagePath(reference) else {
                throw RemoteFormCompletionError.invalidCommand
            }
            return parent.isEmpty ? path : parent + "/" + path
        })
        let maximumBytes = 32 * 1_024 * 1_024
        guard paths.count <= 128, file.content.count <= maximumBytes else { throw SyncError.sizeLimitExceeded }
        var totalBytes = file.content.count
        var files = [file]
        for path in paths.sorted() {
            let asset = try resource(path)
            guard asset.path == path, !asset.isUnsavedBuffer else {
                throw RemoteFormCompletionError.staleRevision
            }
            guard asset.content.count <= maximumBytes - totalBytes else { throw SyncError.sizeLimitExceeded }
            totalBytes += asset.content.count
            files.append(asset)
        }
        self.document = document
        self.revision = CorpusRevision.make(files: files)
    }
}
