import Foundation
import LeonardoSync

/// Selection metadata carried by a Little Leonardo publication commit.
///
/// The fields are part of the commit object, so the commit ID covers the
/// selected scope and its base revision. This authenticates the bytes that
/// were published with the commit; it does not authenticate the author.
public struct GitPublicationMetadata: Codable, Equatable, Sendable {
    public let projectID: UUID
    public let deviceID: UUID
    public let baseRevision: String
    public let scope: CorpusScope
    public let purpose: GitPublicationPurpose

    public init(projectID: UUID, deviceID: UUID, baseRevision: String, scope: CorpusScope,
                purpose: GitPublicationPurpose = .normalChanges) throws {
        guard Self.isObjectID(baseRevision) else { throw GitWireError.invalidObjectID }
        self.projectID = projectID
        self.deviceID = deviceID
        self.baseRevision = baseRevision
        self.scope = scope
        self.purpose = purpose
    }

    private enum CodingKeys: String, CodingKey {
        case projectID, deviceID, baseRevision, scope, purpose
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(projectID: container.decode(UUID.self, forKey: .projectID),
                      deviceID: container.decode(UUID.self, forKey: .deviceID),
                      baseRevision: container.decode(String.self, forKey: .baseRevision),
                      scope: container.decode(CorpusScope.self, forKey: .scope),
                      purpose: container.decode(GitPublicationPurpose.self, forKey: .purpose))
    }

    /// Parses and verifies metadata from one exact commit object.
    ///
    /// Verification recomputes the commit object ID and requires the metadata
    /// base to be the commit's single parent. A branch tip is never consulted
    /// here, which lets callers retain a proposal even if its branch advances.
    public static func parse(commit: GitObject, expectedCommitID: String? = nil) throws -> Self {
        guard commit.kind == .commit, Self.isObjectID(commit.id),
              expectedCommitID == nil || expectedCommitID == commit.id else {
            throw GitWireError.invalidObjectID
        }
        let sha256 = commit.id.count == 64
        guard GitObject.create(kind: .commit, data: commit.data, sha256: sha256).id == commit.id else {
            throw GitWireError.invalidObjectID
        }
        guard let text = String(data: commit.data, encoding: .utf8) else { throw GitWireError.invalidPack }
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard let separator = lines.firstIndex(of: ""), separator > 0 else { throw GitWireError.invalidPack }

        var values: [String: String] = [:]
        var parents: [String] = []
        for line in lines[..<separator] {
            guard !line.contains("\r"), let split = line.firstIndex(of: " ") else { throw GitWireError.invalidPack }
            let name = String(line[..<split])
            let value = String(line[line.index(after: split)...])
            guard !name.isEmpty, !value.isEmpty else { throw GitWireError.invalidPack }
            if name == "parent" {
                parents.append(value)
            } else if name.hasPrefix("little-leonardo-") {
                guard values[name] == nil else { throw GitWireError.invalidPack }
                values[name] = value
            }
        }
        guard parents.count == 1, isObjectID(parents[0]),
              let projectValue = values["little-leonardo-project"],
              let projectID = UUID(uuidString: projectValue),
              let deviceValue = values["little-leonardo-device"],
              let deviceID = UUID(uuidString: deviceValue),
              let baseRevision = values["little-leonardo-base"],
              baseRevision == parents[0],
              let scopeValue = values["little-leonardo-scope"] else {
            throw GitWireError.invalidPack
        }
        let scope = try decodeScope(scopeValue)
        guard let purposeValue = values["little-leonardo-purpose"],
              let purpose = GitPublicationPurpose(rawValue: purposeValue) else {
            throw GitWireError.invalidPack
        }
        return try Self(projectID: projectID, deviceID: deviceID,
                        baseRevision: baseRevision, scope: scope, purpose: purpose)
    }

    /// The canonical commit header lines. Their values contain no whitespace
    /// or control characters, so they are safe Git commit headers.
    public var commitHeaders: [String] {
        [
            "little-leonardo-project \(projectID.uuidString.lowercased())",
            "little-leonardo-device \(deviceID.uuidString.lowercased())",
            "little-leonardo-base \(baseRevision)",
            "little-leonardo-scope \(Self.encodeScope(scope))",
            "little-leonardo-purpose \(purpose.rawValue)"
        ]
    }

    private static func isObjectID(_ value: String) -> Bool {
        [40, 64].contains(value.utf8.count)
            && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
            && value.contains(where: { $0 != "0" })
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
            ($0 >= 65 && $0 <= 90) || ($0 >= 97 && $0 <= 122) || ($0 >= 48 && $0 <= 57) || $0 == 45 || $0 == 95
        }) else { throw GitWireError.invalidPack }
        var encoded = value.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        encoded += String(repeating: "=", count: (4 - encoded.count % 4) % 4)
        guard let data = Data(base64Encoded: encoded) else { throw GitWireError.invalidPack }
        let decoder = JSONDecoder()
        let scope: CorpusScope
        do { scope = try decoder.decode(CorpusScope.self, from: data) }
        catch { throw GitWireError.invalidPack }
        guard encodeScope(scope) == value else { throw GitWireError.invalidPack }
        return scope
    }
}
