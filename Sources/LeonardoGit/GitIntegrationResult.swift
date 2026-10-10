import Foundation
import LeonardoSync

/// The hash-bound metadata of one desktop integration commit.
///
/// `proposalCommitID` identifies the reviewed publication. The generated
/// integration commit uses that exact proposal commit as its single parent so
/// a later mobile publication can fast-forward the same device/project branch.
/// Its tree may be based on a newer desktop checkout. `sourceRevision` records
/// that tree basis so a mobile receiver can later accept an explicitly newer
/// normal Git branch only after proving it descends from the same source.
///
/// The commit hash protects this metadata and the referenced tree; it does not
/// establish the identity or authenticity of the person who created the commit.
public struct GitIntegrationResult: Codable, Equatable, Sendable {
    public let projectID: UUID
    public let deviceID: UUID
    public let proposalCommitID: String
    public let integrationCommitID: String
    public let parentCommitID: String
    public let treeID: String
    public let baseRevision: String
    public let sourceRevision: String
    public let scope: CorpusScope
    public let acceptedDigest: String

    public var integrationRef: GitIntegrationRef {
        // All fields used by the ref are validated by every initializer.
        try! GitIntegrationRef(deviceID: deviceID, projectID: projectID,
                               proposalCommitID: proposalCommitID)
    }

    /// The digest is the exact persisted selected content that the mobile
    /// receiver must compare after reading this commit's selected blobs.
    public var acceptedContentDigest: String { acceptedDigest }

    private enum CodingKeys: String, CodingKey {
        case projectID, deviceID, proposalCommitID, integrationCommitID,
             parentCommitID, treeID, baseRevision, sourceRevision, scope, acceptedDigest
    }

    public init(receipt: GitIntegrationReceipt, integrationCommitID: String,
                parentCommitID: String, treeID: String,
                sourceRevision: String? = nil,
                limits: CorpusLimits = CorpusLimits()) throws {
        let sourceRevision = sourceRevision ?? receipt.baseRevision
        try Self.validateIDs(projectID: receipt.projectID, deviceID: receipt.deviceID,
                             proposalCommitID: receipt.commitID, integrationCommitID: integrationCommitID,
                             parentCommitID: parentCommitID, treeID: treeID,
                             baseRevision: receipt.baseRevision, sourceRevision: sourceRevision)
        try receipt.accepted.validate(scope: receipt.scope, limits: limits)
        guard receipt.accepted.files.allSatisfy({ !$0.isUnsavedBuffer }) else {
            throw SyncError.invalidSnapshot
        }
        self.projectID = receipt.projectID
        self.deviceID = receipt.deviceID
        self.proposalCommitID = receipt.commitID
        self.integrationCommitID = integrationCommitID
        self.parentCommitID = parentCommitID
        self.treeID = treeID
        self.baseRevision = receipt.baseRevision
        self.sourceRevision = sourceRevision
        self.scope = receipt.scope
        self.acceptedDigest = CorpusRevision.make(files: receipt.accepted.files)
    }

    public init(projectID: UUID, deviceID: UUID, proposalCommitID: String,
                integrationCommitID: String, parentCommitID: String, treeID: String,
                baseRevision: String, scope: CorpusScope, acceptedDigest: String,
                sourceRevision: String? = nil) throws {
        let sourceRevision = sourceRevision ?? baseRevision
        try Self.validateIDs(projectID: projectID, deviceID: deviceID,
                             proposalCommitID: proposalCommitID, integrationCommitID: integrationCommitID,
                             parentCommitID: parentCommitID, treeID: treeID, baseRevision: baseRevision,
                             sourceRevision: sourceRevision)
        guard Self.isDigest(acceptedDigest) else { throw GitWireError.invalidObjectID }
        self.projectID = projectID
        self.deviceID = deviceID
        self.proposalCommitID = proposalCommitID
        self.integrationCommitID = integrationCommitID
        self.parentCommitID = parentCommitID
        self.treeID = treeID
        self.baseRevision = baseRevision
        self.sourceRevision = sourceRevision
        self.scope = scope
        self.acceptedDigest = acceptedDigest
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(projectID: container.decode(UUID.self, forKey: .projectID),
                      deviceID: container.decode(UUID.self, forKey: .deviceID),
                      proposalCommitID: container.decode(String.self, forKey: .proposalCommitID),
                      integrationCommitID: container.decode(String.self, forKey: .integrationCommitID),
                      parentCommitID: container.decode(String.self, forKey: .parentCommitID),
                      treeID: container.decode(String.self, forKey: .treeID),
                      baseRevision: container.decode(String.self, forKey: .baseRevision),
                      scope: container.decode(CorpusScope.self, forKey: .scope),
                      acceptedDigest: container.decode(String.self, forKey: .acceptedDigest),
                      sourceRevision: container.decode(String.self, forKey: .sourceRevision))
    }

    /// Parses and authenticates the metadata in one exact integration commit.
    /// The caller must fetch the selected blobs separately and call
    /// `validate(accepted:)` before treating them as the new baseline.
    public static func parse(commit: GitObject, expectedCommitID: String? = nil) throws -> Self {
        guard commit.kind == .commit, Self.isObjectID(commit.id),
              expectedCommitID == nil || expectedCommitID == commit.id else {
            throw GitWireError.invalidObjectID
        }
        let sha256 = commit.id.count == 64
        guard GitObject.create(kind: .commit, data: commit.data, sha256: sha256).id == commit.id else {
            throw GitWireError.invalidObjectID
        }
        guard let text = String(data: commit.data, encoding: .utf8) else {
            throw GitWireError.invalidPack
        }
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard let separator = lines.firstIndex(of: ""), separator > 0 else {
            throw GitWireError.invalidPack
        }

        var treeID: String?
        var parentID: String?
        var values: [String: String] = [:]
        for line in lines[..<separator] {
            guard !line.contains("\r"), let split = line.firstIndex(of: " ") else {
                throw GitWireError.invalidPack
            }
            let key = String(line[..<split])
            let value = String(line[line.index(after: split)...])
            guard !key.isEmpty, !value.isEmpty,
                  !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
                throw GitWireError.invalidPack
            }
            switch key {
            case "tree":
                guard treeID == nil else { throw GitWireError.invalidPack }
                treeID = value
            case "parent":
                guard parentID == nil else { throw GitWireError.invalidPack }
                parentID = value
            case "little-leonardo-integration-project",
                 "little-leonardo-integration-device",
                 "little-leonardo-integration-proposal",
                 "little-leonardo-integration-base",
                 "little-leonardo-integration-source",
                 "little-leonardo-integration-scope",
                 "little-leonardo-integration-accepted":
                guard values[key] == nil else { throw GitWireError.invalidPack }
                values[key] = value
            default:
                continue
            }
        }
        guard let treeID, let parentID,
              let projectValue = values["little-leonardo-integration-project"],
              let projectID = UUID(uuidString: projectValue),
              projectValue == projectID.uuidString.lowercased(),
              let deviceValue = values["little-leonardo-integration-device"],
              let deviceID = UUID(uuidString: deviceValue),
              deviceValue == deviceID.uuidString.lowercased(),
              let proposalCommitID = values["little-leonardo-integration-proposal"],
              let baseRevision = values["little-leonardo-integration-base"],
              let sourceRevision = values["little-leonardo-integration-source"],
              let scopeValue = values["little-leonardo-integration-scope"],
              let acceptedDigest = values["little-leonardo-integration-accepted"],
              Self.isObjectID(treeID), Self.isObjectID(parentID),
              treeID.count == commit.id.count, parentID.count == commit.id.count,
              Self.isObjectID(proposalCommitID), Self.isObjectID(baseRevision),
              Self.isObjectID(sourceRevision),
              proposalCommitID.count == commit.id.count, baseRevision.count == commit.id.count,
              sourceRevision.count == commit.id.count else {
            throw GitWireError.invalidPack
        }
        let scope = try decodeScope(scopeValue)
        let result = try Self(projectID: projectID, deviceID: deviceID,
                              proposalCommitID: proposalCommitID, integrationCommitID: commit.id,
                              parentCommitID: parentID, treeID: treeID, baseRevision: baseRevision,
                              scope: scope, acceptedDigest: acceptedDigest,
                              sourceRevision: sourceRevision)
        guard result.commitHeaders.contains("little-leonardo-integration-scope \(scopeValue)") else {
            throw GitWireError.invalidPack
        }
        return result
    }

    /// Parses a commit payload returned by a local Git process while keeping
    /// object construction inside the Git module. The expected object ID is
    /// mandatory so callers cannot turn untrusted bytes into metadata by
    /// inferring an ID from the payload itself.
    public static func parse(commitData: Data, expectedCommitID: String) throws -> Self {
        guard Self.isObjectID(expectedCommitID) else {
            throw GitWireError.invalidObjectID
        }
        let commit = GitObject.create(kind: .commit, data: commitData,
                                      sha256: expectedCommitID.count == 64)
        guard commit.id == expectedCommitID else {
            throw GitWireError.invalidObjectID
        }
        return try parse(commit: commit, expectedCommitID: expectedCommitID)
    }

    /// Validates the selected snapshot fetched from `integrationCommitID`.
    /// This is the check that prevents a receiver from accepting a different
    /// branch tip or a different set of bytes under the same scope.
    public func validate(accepted snapshot: CorpusSnapshot,
                         limits: CorpusLimits = CorpusLimits()) throws {
        guard snapshot.revision == integrationCommitID,
              snapshot.files.allSatisfy({ !$0.isUnsavedBuffer }) else {
            throw SyncError.invalidSnapshot
        }
        try snapshot.validate(scope: scope, limits: limits)
        guard CorpusRevision.make(files: snapshot.files) == acceptedDigest else {
            throw GitWireError.invalidPack
        }
    }

    /// Canonical extension headers for the integration commit object.
    public var commitHeaders: [String] {
        [
            "little-leonardo-integration-project \(projectID.uuidString.lowercased())",
            "little-leonardo-integration-device \(deviceID.uuidString.lowercased())",
            "little-leonardo-integration-proposal \(proposalCommitID)",
            "little-leonardo-integration-base \(baseRevision)",
            "little-leonardo-integration-source \(sourceRevision)",
            "little-leonardo-integration-scope \(Self.encodeScope(scope))",
            "little-leonardo-integration-accepted \(acceptedDigest)",
        ]
    }

    /// Builds the exact commit bytes represented by this result. The computed
    /// object ID must equal `integrationCommitID`, otherwise the result was
    /// paired with a different commit and is rejected.
    public func commitData(identity: GitCommitIdentity,
                           message: String = "Little Leonardo integration") throws -> Data {
        let data = try Self.makeCommitData(treeID: treeID, parentCommitID: parentCommitID,
                                           identity: identity, message: message,
                                           headers: commitHeaders)
        guard GitObject.create(kind: .commit, data: data, sha256: integrationCommitID.count == 64).id == integrationCommitID else {
            throw GitWireError.invalidObjectID
        }
        return data
    }

    /// Builds a result and its real Git commit after the desktop has written
    /// the resolved tree. The returned ID is the object ID of the generated
    /// commit, never the proposal's virtual receipt revision.
    public static func buildCommit(receipt: GitIntegrationReceipt, parentCommitID: String,
                                   treeID: String, identity: GitCommitIdentity,
                                   sourceRevision: String? = nil,
                                   message: String = "Little Leonardo integration") throws -> GitIntegrationBuiltCommit {
        guard parentCommitID == receipt.commitID else { throw SyncError.invalidSnapshot }
        let sourceRevision = sourceRevision ?? receipt.baseRevision
        let digest = try acceptedDigest(for: receipt)
        try validateIDs(projectID: receipt.projectID, deviceID: receipt.deviceID,
                        proposalCommitID: receipt.commitID, integrationCommitID: parentCommitID,
                        parentCommitID: parentCommitID, treeID: treeID,
                        baseRevision: receipt.baseRevision, sourceRevision: sourceRevision)
        let headers = [
            "little-leonardo-integration-project \(receipt.projectID.uuidString.lowercased())",
            "little-leonardo-integration-device \(receipt.deviceID.uuidString.lowercased())",
            "little-leonardo-integration-proposal \(receipt.commitID)",
            "little-leonardo-integration-base \(receipt.baseRevision)",
            "little-leonardo-integration-source \(sourceRevision)",
            "little-leonardo-integration-scope \(encodeScope(receipt.scope))",
            "little-leonardo-integration-accepted \(digest)",
        ]
        let data = try makeCommitData(treeID: treeID, parentCommitID: parentCommitID,
                                      identity: identity, message: message, headers: headers)
        let commit = GitObject.create(kind: .commit, data: data, sha256: parentCommitID.count == 64)
        let result = try Self(receipt: receipt, integrationCommitID: commit.id,
                              parentCommitID: parentCommitID, treeID: treeID,
                              sourceRevision: sourceRevision)
        return try GitIntegrationBuiltCommit(result: result, commit: commit)
    }

    private static func acceptedDigest(for receipt: GitIntegrationReceipt) throws -> String {
        try receipt.accepted.validate(scope: receipt.scope, limits: CorpusLimits())
        guard receipt.accepted.files.allSatisfy({ !$0.isUnsavedBuffer }) else {
            throw SyncError.invalidSnapshot
        }
        return CorpusRevision.make(files: receipt.accepted.files)
    }

    private static func makeCommitData(treeID: String, parentCommitID: String,
                                       identity: GitCommitIdentity, message: String,
                                       headers: [String]) throws -> Data {
        guard Self.isObjectID(treeID), Self.isObjectID(parentCommitID),
              treeID.count == parentCommitID.count,
              !message.isEmpty, message.utf8.count <= 4_096, !message.contains("\0"),
              !message.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) && $0 != "\n" }) else {
            throw GitWireError.invalidPack
        }
        guard headers.allSatisfy({ line in
            !line.isEmpty && !line.contains("\r") && !line.contains("\n") &&
            !line.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
        }) else { throw GitWireError.invalidPack }
        let standard = ["tree \(treeID)", "parent \(parentCommitID)",
                        "author \(identity.header)", "committer \(identity.header)"]
        return Data(((standard + headers).joined(separator: "\n") + "\n\n" + message + "\n").utf8)
    }

    private static func validateIDs(projectID: UUID, deviceID: UUID,
                                    proposalCommitID: String, integrationCommitID: String,
                                    parentCommitID: String, treeID: String,
                                    baseRevision: String, sourceRevision: String) throws {
        guard Self.isObjectID(proposalCommitID), Self.isObjectID(integrationCommitID),
              Self.isObjectID(parentCommitID), Self.isObjectID(treeID), Self.isObjectID(baseRevision),
              Self.isObjectID(sourceRevision),
              parentCommitID == proposalCommitID,
              proposalCommitID.count == integrationCommitID.count,
              parentCommitID.count == integrationCommitID.count,
              treeID.count == integrationCommitID.count,
              baseRevision.count == integrationCommitID.count,
              sourceRevision.count == integrationCommitID.count,
              GitIntegrationRef.name(deviceID: deviceID, projectID: projectID,
                                     proposalCommitID: proposalCommitID).hasPrefix("refs/heads/") else {
            throw GitWireError.invalidObjectID
        }
    }

    private static func isObjectID(_ value: String) -> Bool {
        [40, 64].contains(value.utf8.count)
            && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
            && value.contains(where: { $0 != "0" })
    }

    private static func isDigest(_ value: String) -> Bool {
        guard value.hasPrefix("sha256:"), value.utf8.count == 71 else { return false }
        let hex = value.dropFirst("sha256:".count)
        return hex.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
            && hex.contains(where: { $0 != "0" })
    }

    private static func encodeScope(_ scope: CorpusScope) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = (try? encoder.encode(scope)) ?? Data()
        return data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func decodeScope(_ value: String) throws -> CorpusScope {
        guard !value.isEmpty, value.utf8.allSatisfy({
            ($0 >= 65 && $0 <= 90) || ($0 >= 97 && $0 <= 122) ||
            ($0 >= 48 && $0 <= 57) || $0 == 45 || $0 == 95
        }) else { throw GitWireError.invalidPack }
        var encoded = value.replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        encoded += String(repeating: "=", count: (4 - encoded.count % 4) % 4)
        guard let data = Data(base64Encoded: encoded),
              let scope = try? JSONDecoder().decode(CorpusScope.self, from: data),
              encodeScope(scope) == value else { throw GitWireError.invalidPack }
        return scope
    }
}

/// The commit object and its authenticated result metadata as one immutable
/// value passed from the tree builder to the push/outbox layer.
public struct GitIntegrationBuiltCommit: Sendable, Equatable {
    public let result: GitIntegrationResult
    public let commit: GitObject

    public init(result: GitIntegrationResult, commit: GitObject) throws {
        guard commit.kind == .commit, commit.id == result.integrationCommitID,
              GitObject.create(kind: .commit, data: commit.data,
                               sha256: commit.id.count == 64).id == commit.id,
              try GitIntegrationResult.parse(commit: commit, expectedCommitID: commit.id) == result else {
            throw GitWireError.invalidObjectID
        }
        self.result = result
        self.commit = commit
    }
}

public extension GitRemoteReader {
    /// Reads one integration commit's metadata without requesting selected
    /// blobs. The object ID is taken from the same advertisement that yielded
    /// the ref; no branch advancement or range calculation is involved.
    func integrationResult(from ref: GitIntegrationRef,
                           discovery: GitRemoteDiscovery) async throws -> GitIntegrationResult {
        guard let reference = discovery.references.first(where: { $0.name == ref.name }),
              let integrationCommitID = reference.objectID else {
            throw GitWireError.invalidObjectID
        }
        let metadata = try await self.metadata(commitID: integrationCommitID, discovery: discovery)
        guard let commit = metadata.objects.first(where: {
            $0.id == integrationCommitID && $0.kind == .commit
        }) else { throw GitWireError.invalidPack }
        let result = try GitIntegrationResult.parse(commit: commit, expectedCommitID: integrationCommitID)
        guard result.integrationRef == ref else { throw GitWireError.invalidPack }
        return result
    }

    /// Transfers only the selected blobs after metadata has been authenticated,
    /// then checks the exact content digest bound by the integration commit.
    func integrationSnapshot(result: GitIntegrationResult,
                             discovery: GitRemoteDiscovery,
                             limits: CorpusLimits = CorpusLimits()) async throws -> CorpusSnapshot {
        guard let reference = discovery.references.first(where: { $0.name == result.integrationRef.name }),
              reference.objectID == result.integrationCommitID else {
            throw GitWireError.invalidObjectID
        }
        let metadata = try await self.metadata(commitID: result.integrationCommitID, discovery: discovery)
        let snapshot = try await self.snapshot(metadata: metadata, scope: result.scope, limits: limits)
        try result.validate(accepted: snapshot, limits: limits)
        return snapshot
    }
}
