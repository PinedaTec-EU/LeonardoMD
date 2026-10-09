import Foundation

/// Metadata is bound to authenticated device/project identity by the receiving adapter.
public struct DesktopPeerUpload: Codable, Equatable, Sendable {
    public static let maximumChunkBytes = 20 * 1_024
    public let proposalID: UUID
    public let projectID: UUID
    public let byteCount: Int
    public let sha256: String

    public init(proposalID: UUID, projectID: UUID, byteCount: Int, sha256: String) throws {
        guard byteCount > 0, byteCount <= (try DesktopPeerArchiveBudget.maximumEncodedBytes()),
              sha256.utf8.count == 64, sha256.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else {
            throw SyncError.invalidSnapshot
        }
        self.proposalID = proposalID; self.projectID = projectID
        self.byteCount = byteCount; self.sha256 = sha256
    }
    private enum CodingKeys: String, CodingKey { case proposalID, projectID, byteCount, sha256 }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(proposalID: c.decode(UUID.self, forKey: .proposalID), projectID: c.decode(UUID.self, forKey: .projectID),
                      byteCount: c.decode(Int.self, forKey: .byteCount), sha256: c.decode(String.self, forKey: .sha256))
    }
}
