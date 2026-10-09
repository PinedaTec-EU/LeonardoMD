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

public struct DesktopPeerUploadProgress: Codable, Equatable, Sendable {
    public let proposalID: UUID
    public let receivedBytes: Int
    public let submitted: Bool
    public init(proposalID: UUID, receivedBytes: Int, submitted: Bool = false) {
        self.proposalID = proposalID; self.receivedBytes = receivedBytes; self.submitted = submitted
    }
}

public struct DesktopPeerUploadChunk: Codable, Sendable {
    public let upload: DesktopPeerUpload
    public let offset: Int
    public let bytes: Data
    public init(upload: DesktopPeerUpload, offset: Int, bytes: Data) {
        self.upload = upload; self.offset = offset; self.bytes = bytes
    }
}

public protocol DesktopPeerUploadStore: Sendable {
    func begin(deviceID: UUID, upload: DesktopPeerUpload, selection: CorpusSelection) async throws -> Int
    func append(deviceID: UUID, upload: DesktopPeerUpload, offset: Int, bytes: Data, selection: CorpusSelection) async throws -> Int
    func submit(deviceID: UUID, upload: DesktopPeerUpload, selection: CorpusSelection) async throws
    func pending(deviceID: UUID, projectID: UUID, selection: CorpusSelection) async throws -> DesktopPeerUpload?
    func finish(deviceID: UUID, upload: DesktopPeerUpload, selection: CorpusSelection) async throws -> DesktopPeerProposal
}

public struct DesktopPeerIncomingProposal: Sendable, Identifiable {
    public let deviceID: UUID
    public let deviceName: String
    public let upload: DesktopPeerUpload
    public var id: String { deviceID.uuidString + "/" + upload.projectID.uuidString + "/" + upload.proposalID.uuidString }
    public init(deviceID: UUID, deviceName: String, upload: DesktopPeerUpload) {
        self.deviceID = deviceID; self.deviceName = deviceName; self.upload = upload
    }
}
