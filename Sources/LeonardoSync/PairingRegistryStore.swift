import Foundation

/// Host-local authorization metadata. Contains hashes and consent scope, never raw credentials.
public actor PairingRegistryStore {
    private let url: URL
    private static let maximumBytes = 2 * 1_024 * 1_024

    public init(url: URL) {
        // Resolve the trusted host directory, preserving the final entry for symlink rejection.
        self.url = url.deletingLastPathComponent().standardizedFileURL.resolvingSymlinksInPath()
            .appendingPathComponent(url.lastPathComponent)
    }

    public func load() throws -> PairingRegistry {
        try rejectSymlinks()
        guard FileManager.default.fileExists(atPath: url.path) else { return PairingRegistry() }
        let count = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard count <= Self.maximumBytes else { throw SyncError.sizeLimitExceeded }
        return try JSONDecoder().decode(PairingRegistry.self, from: Data(contentsOf: url))
    }

    public func save(_ registry: PairingRegistry) throws {
        try rejectSymlinks()
        let data = try JSONEncoder().encode(registry)
        guard data.count <= Self.maximumBytes else { throw SyncError.sizeLimitExceeded }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    private func rejectSymlinks() throws {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        if attributes?[.type] as? FileAttributeType == .typeSymbolicLink { throw SyncError.invalidPath }
    }
}
