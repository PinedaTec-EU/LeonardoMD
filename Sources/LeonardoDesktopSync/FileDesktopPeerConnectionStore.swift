#if os(macOS)
import Foundation
import LeonardoSync
import LeonardoSyncTransport

public actor FileDesktopPeerConnectionStore: DesktopPeerConnectionStore {
    private let root: URL
    private static let maximumBytes = 300 * 1_024 * 1_024
    public init(root: URL) { self.root = root.standardizedFileURL.resolvingSymlinksInPath() }
    public func connectionIDs() throws -> [UUID] {
        guard FileManager.default.fileExists(atPath: root.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }.compactMap { UUID(uuidString: $0.deletingPathExtension().lastPathComponent) }
            .sorted { $0.uuidString < $1.uuidString }
    }
    public func load(id: UUID) throws -> DesktopPeerConnection? {
        let url = try location(id)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true else { throw SyncError.invalidPath }
        guard (values.fileSize ?? 0) <= Self.maximumBytes else { throw SyncError.sizeLimitExceeded }
        let connection = try JSONDecoder().decode(DesktopPeerConnection.self, from: Data(contentsOf: url))
        guard connection.id == id else { throw SyncError.invalidSnapshot }
        try validate(connection)
        return connection
    }
    public func save(_ connection: DesktopPeerConnection) throws {
        try validate(connection)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.withoutEscapingSlashes, .sortedKeys]
        let data = try encoder.encode(connection)
        guard data.count <= Self.maximumBytes else { throw SyncError.sizeLimitExceeded }
        try PrivateDesktopFile.write(data, to: location(connection.id))
    }
    public func remove(id: UUID) throws {
        let url = try location(id)
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
    }
    private func validate(_ connection: DesktopPeerConnection) throws {
        _ = try PinnedHTTPSClient(endpoint: connection.endpoint, certificateFingerprint: connection.fingerprint,
                                  allowPrivateOverlay: true)
    }
    private func location(_ id: UUID) throws -> URL {
        let url = root.appendingPathComponent(id.uuidString).appendingPathExtension("json")
        guard (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true else { throw SyncError.invalidPath }
        return url
    }
}
#endif
