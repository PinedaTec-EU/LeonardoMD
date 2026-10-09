import Foundation

public enum GitPushError: Error, Equatable, Sendable {
    case invalidAdvertisement, unsupportedStatus, staleReference, invalidResponse, rejected
}

/// receive-pack advertises protocol-v0 references even when fetch uses protocol v2.
public struct GitPushAdvertisement: Sendable {
    public let references: [String: String]
    public let capabilities: Set<String>
    public let sha256: Bool

    public init(data: Data) throws {
        var packets = try GitPacket.decode(data)
        if packets.first == .data(Data("# service=git-receive-pack\n".utf8)) {
            guard packets.count >= 4, packets[1] == .flush else { throw GitPushError.invalidAdvertisement }
            packets.removeFirst(2)
        }
        guard packets.last == .flush, packets.count >= 2 else { throw GitPushError.invalidAdvertisement }
        var lines: [String] = []
        var capabilities: Set<String> = []
        for (index, packet) in packets.dropLast().enumerated() {
            guard case .data(let data) = packet, var text = String(data: data, encoding: .utf8) else { throw GitPushError.invalidAdvertisement }
            if text.hasSuffix("\n") { text.removeLast() }
            let fields = text.split(separator: "\0", omittingEmptySubsequences: false)
            if index == 0 {
                guard fields.count == 2, !fields[1].isEmpty else { throw GitPushError.invalidAdvertisement }
                let tokens = fields[1].split(separator: " ", omittingEmptySubsequences: false).map(String.init)
                guard tokens.allSatisfy({ !$0.isEmpty && !$0.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) }),
                      Set(tokens).count == tokens.count else { throw GitPushError.invalidAdvertisement }
                capabilities = Set(tokens)
            } else { guard fields.count == 1 else { throw GitPushError.invalidAdvertisement } }
            guard let line = fields.first, !line.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
                throw GitPushError.invalidAdvertisement
            }
            lines.append(String(line))
        }
        let formats = capabilities.filter { $0.hasPrefix("object-format=") }
        guard formats.count <= 1, formats.isEmpty || formats == ["object-format=sha1"] || formats == ["object-format=sha256"] else {
            throw GitWireError.unsupportedObjectFormat
        }
        let sha256 = formats.contains("object-format=sha256")
        var refs: [String: String] = [:]
        for line in lines {
            let fields = line.split(separator: " ", omittingEmptySubsequences: false)
            guard fields.count == 2 else { throw GitPushError.invalidAdvertisement }
            let oid = String(fields[0]), name = String(fields[1])
            guard Self.validID(oid, sha256: sha256) else { throw GitWireError.invalidObjectID }
            if name == "capabilities^{}" {
                guard lines.count == 1, oid.allSatisfy({ $0 == "0" }) else { throw GitPushError.invalidAdvertisement }
                continue
            }
            guard GitReference.isValidName(name), oid.contains(where: { $0 != "0" }), refs[name] == nil else { throw GitPushError.invalidAdvertisement }
            refs[name] = oid
        }
        self.references = refs; self.capabilities = capabilities; self.sha256 = sha256
    }

    public func request(branch: String, expectedOldID: String?, commit: GitBuiltCommit) throws -> Data {
        guard branch.hasPrefix("refs/heads/little-leonardo/"), GitReference.isValidName(branch) else { throw GitWireError.invalidObjectID }
        guard capabilities.contains("report-status") else { throw GitPushError.unsupportedStatus }
        guard references[branch] == expectedOldID else { throw GitPushError.staleReference }
        let old = expectedOldID ?? String(repeating: "0", count: sha256 ? 64 : 40)
        guard Self.validID(old, sha256: sha256), Self.validID(commit.commit.id, sha256: sha256),
              commit.commit.id.contains(where: { $0 != "0" }) else { throw GitWireError.invalidObjectID }
        var requested = ["report-status"]
        if capabilities.contains("object-format=sha256") || capabilities.contains("object-format=sha1") {
            requested.append("object-format=\(sha256 ? "sha256" : "sha1")")
        }
        let line = "\(old) \(commit.commit.id) \(branch)\0\(requested.joined(separator: " "))\n"
        return try GitPacket.data(Data(line.utf8)).encoded() + GitPacket.flush.encoded()
            + GitPackWriter.encode(objects: commit.objects, sha256: sha256)
    }

    private static func validID(_ id: String, sha256: Bool) -> Bool {
        id.utf8.count == (sha256 ? 64 : 40) && id.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }
}
