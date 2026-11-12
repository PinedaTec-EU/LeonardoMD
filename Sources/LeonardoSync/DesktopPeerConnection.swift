import Foundation

/// Local identity is independent of the server-issued device ID, including its credential account.
public struct DesktopPeerConnection: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public let remoteDeviceID: UUID
    public let endpoint: URL
    public let fingerprint: Data
    public private(set) var comparisonCode: String?
    public private(set) var grants: [UUID: CorpusSelection]
    public private(set) var copies: [UUID: UUID]
    public private(set) var revoked: Bool

    public init(id: UUID = UUID(), remoteDeviceID: UUID, endpoint: URL, fingerprint: Data,
                comparisonCode: String? = nil, grants: [UUID: CorpusSelection] = [:],
                copies: [UUID: UUID] = [:], revoked: Bool = false) throws {
        guard endpoint.scheme == "https", endpoint.host != nil, endpoint.user == nil, endpoint.password == nil,
              endpoint.query == nil, endpoint.fragment == nil, endpoint.path.isEmpty || endpoint.path == "/",
              endpoint.absoluteString.utf8.count <= 4_096, fingerprint.count == 32,
              Set(copies.values).count == copies.count else { throw SyncError.invalidSnapshot }
        if let comparisonCode {
            guard comparisonCode.utf8.count == 8, comparisonCode.utf8.allSatisfy({ (48...57).contains($0) }) else { throw SyncError.invalidSnapshot }
        }
        guard !revoked || (grants.isEmpty && comparisonCode == nil) else { throw SyncError.invalidSnapshot }
        self.id = id; self.remoteDeviceID = remoteDeviceID; self.endpoint = endpoint; self.fingerprint = fingerprint
        self.comparisonCode = comparisonCode; self.grants = grants; self.copies = copies; self.revoked = revoked
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(id: values.decode(UUID.self, forKey: .id), remoteDeviceID: values.decode(UUID.self, forKey: .remoteDeviceID),
            endpoint: values.decode(URL.self, forKey: .endpoint), fingerprint: values.decode(Data.self, forKey: .fingerprint),
            comparisonCode: values.decodeIfPresent(String.self, forKey: .comparisonCode),
            grants: values.decode([UUID: CorpusSelection].self, forKey: .grants), copies: values.decode([UUID: UUID].self, forKey: .copies),
            revoked: values.decode(Bool.self, forKey: .revoked))
    }
    private enum CodingKeys: String, CodingKey { case id, remoteDeviceID, endpoint, fingerprint, comparisonCode, grants, copies, revoked }

    public mutating func authorize(_ grants: [UUID: CorpusSelection]) throws {
        guard !revoked else { throw SyncError.revoked }
        self.grants = grants; comparisonCode = nil
    }
    public mutating func revoke() { revoked = true; grants = [:]; comparisonCode = nil }
    public mutating func track(projectID: UUID, copyID: UUID) throws {
        guard !revoked, grants[projectID] != nil else { throw SyncError.revoked }
        guard copies[projectID] == nil || copies[projectID] == copyID,
              !copies.contains(where: { $0.key != projectID && $0.value == copyID }) else { throw SyncError.invalidSnapshot }
        copies[projectID] = copyID
    }
    public mutating func forgetCopy(projectID: UUID) { copies[projectID] = nil }
}

public protocol DesktopPeerConnectionStore: Sendable {
    func connectionIDs() async throws -> [UUID]
    func load(id: UUID) async throws -> DesktopPeerConnection?
    func save(_ connection: DesktopPeerConnection) async throws
    func remove(id: UUID) async throws
}
