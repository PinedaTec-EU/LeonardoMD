import Foundation
import LeonardoSync
import LeonardoSyncTransport

struct MobileDirectConnection: Codable, Identifiable {
    let connectionID: UUID
    var id: UUID { connectionID }
    let deviceID: UUID
    let endpoint: URL
    /// A user-defined label local to Little Leonardo. It is never sent to the host.
    var displayName: String?
    let fingerprint: Data
    /// Projects the Mac currently grants to this connection. This is the
    /// authorization boundary and is independent from the user's local choice.
    var projectIDs: Set<UUID>
    var projectDescriptors: [SharedProjectDescriptor]
    var acceptedProjectIDs: Set<UUID>
    var ignoredProjectIDs: Set<UUID>
    var newFilePaths: [UUID: Set<String>]
    var selectionMigrationCompleted: Bool
    var comparisonCode: String?
    var capabilities: Set<DirectCapability>
    var capabilityRefreshAttempted: Bool
    var revoked: Bool
    var pendingPurgeProjectIDs: Set<UUID>

    init(connectionID: UUID = UUID(), deviceID: UUID, endpoint: URL, fingerprint: Data,
         projectIDs: Set<UUID>, comparisonCode: String?, capabilities: Set<DirectCapability>,
         capabilityRefreshAttempted: Bool = false, revoked: Bool = false,
         pendingPurgeProjectIDs: Set<UUID> = [], projectDescriptors: [SharedProjectDescriptor] = [],
         acceptedProjectIDs: Set<UUID>? = nil, ignoredProjectIDs: Set<UUID> = [],
         newFilePaths: [UUID: Set<String>] = [:], selectionMigrationCompleted: Bool = true,
         displayName: String? = nil) {
        self.connectionID = connectionID
        self.deviceID = deviceID
        self.endpoint = endpoint
        self.displayName = displayName
        self.fingerprint = fingerprint
        self.projectIDs = projectIDs
        self.projectDescriptors = projectDescriptors
        self.acceptedProjectIDs = acceptedProjectIDs ?? projectIDs
        self.ignoredProjectIDs = ignoredProjectIDs
        self.newFilePaths = newFilePaths
        self.selectionMigrationCompleted = selectionMigrationCompleted
        self.comparisonCode = comparisonCode
        self.capabilities = capabilities
        self.capabilityRefreshAttempted = capabilityRefreshAttempted
        self.revoked = revoked
        self.pendingPurgeProjectIDs = pendingPurgeProjectIDs
    }

    private enum CodingKeys: String, CodingKey {
        case connectionID, deviceID, endpoint, displayName, fingerprint, projectIDs, comparisonCode, capabilities,
             capabilityRefreshAttempted, revoked, pendingPurgeProjectIDs, projectDescriptors,
             acceptedProjectIDs, ignoredProjectIDs, newFilePaths, selectionMigrationCompleted
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let deviceID = try container.decode(UUID.self, forKey: .deviceID)
        let projectIDs = try container.decodeIfPresent(Set<UUID>.self, forKey: .projectIDs) ?? []
        self.init(connectionID: try container.decodeIfPresent(UUID.self, forKey: .connectionID) ?? deviceID,
                  deviceID: deviceID,
                  endpoint: try container.decode(URL.self, forKey: .endpoint),
                  fingerprint: try container.decode(Data.self, forKey: .fingerprint),
                  projectIDs: projectIDs,
                  comparisonCode: try container.decodeIfPresent(String.self, forKey: .comparisonCode),
                  capabilities: try container.decodeIfPresent(Set<DirectCapability>.self, forKey: .capabilities) ?? [],
                  capabilityRefreshAttempted: try container.decodeIfPresent(Bool.self,
                      forKey: .capabilityRefreshAttempted) ?? false,
                  revoked: try container.decodeIfPresent(Bool.self, forKey: .revoked) ?? false,
                  pendingPurgeProjectIDs: try container.decodeIfPresent(Set<UUID>.self,
                      forKey: .pendingPurgeProjectIDs) ?? [],
                  projectDescriptors: try container.decodeIfPresent([SharedProjectDescriptor].self,
                      forKey: .projectDescriptors) ?? [],
                  acceptedProjectIDs: try container.decodeIfPresent(Set<UUID>.self,
                      forKey: .acceptedProjectIDs) ?? projectIDs,
                  ignoredProjectIDs: try container.decodeIfPresent(Set<UUID>.self,
                      forKey: .ignoredProjectIDs) ?? [],
                  newFilePaths: try container.decodeIfPresent([UUID: Set<String>].self,
                      forKey: .newFilePaths) ?? [:],
                  selectionMigrationCompleted: try container.decodeIfPresent(Bool.self,
                      forKey: .selectionMigrationCompleted) ?? false,
                  displayName: try container.decodeIfPresent(String.self, forKey: .displayName))
    }

    var suggestedDisplayName: String {
        guard let rawHost = endpoint.host, !rawHost.isEmpty else { return "Mac conectado" }
        let lowercasedHost = rawHost.lowercased()
        if rawHost.contains(":") || rawHost.allSatisfy({ $0.isNumber || $0 == "." }) {
            return "Mac conectado"
        }
        var host = rawHost
        if lowercasedHost.hasSuffix(".local") { host.removeLast(6) }
        host = host.replacingOccurrences(of: "-", with: " ")
        return host.prefix(1).uppercased() + String(host.dropFirst())
    }

    var visibleDisplayName: String {
        let stored = displayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return stored.isEmpty ? suggestedDisplayName : stored
    }

    func hasSameIdentity(as other: MobileDirectConnection) -> Bool {
        connectionID == other.connectionID && deviceID == other.deviceID && fingerprint == other.fingerprint
    }

    var showsEndpointAddressInHostRow: Bool {
        (displayName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
            && suggestedDisplayName == "Mac conectado"
    }

    var endpointAddress: String {
        guard let host = endpoint.host, !host.isEmpty else { return endpoint.absoluteString }
        let addressHost = host.contains(":") && !host.hasPrefix("[") ? "[\(host)]" : host
        guard let port = endpoint.port else { return addressHost }
        return "\(addressHost):\(port)"
    }

    func hasChanges(from other: MobileDirectConnection) -> Bool {
        projectIDs != other.projectIDs || comparisonCode != other.comparisonCode
            || projectDescriptors != other.projectDescriptors
            || acceptedProjectIDs != other.acceptedProjectIDs
            || ignoredProjectIDs != other.ignoredProjectIDs
            || newFilePaths != other.newFilePaths
            || selectionMigrationCompleted != other.selectionMigrationCompleted
            || capabilities != other.capabilities
            || capabilityRefreshAttempted != other.capabilityRefreshAttempted
            || revoked != other.revoked
            || pendingPurgeProjectIDs != other.pendingPurgeProjectIDs
    }

    mutating func reconcileIgnoredProjectGrants(with currentDescriptors: [SharedProjectDescriptor]) {
        let currentIDs = Set(currentDescriptors.map(\.id))
        ignoredProjectIDs.formIntersection(currentIDs)
        for projectID in Array(ignoredProjectIDs) {
            guard let previous = projectDescriptors.first(where: { $0.id == projectID }),
                  let current = currentDescriptors.first(where: { $0.id == projectID }) else { continue }
            if !previous.representsSameGrant(as: current) {
                ignoredProjectIDs.remove(projectID)
            }
        }
    }
}

/// Atomic, owner-only persistence for mobile connection snapshots.
struct MobileDirectConnectionStore {
    private static let maximumBytes = 2 * 1_024 * 1_024
    private let url: URL

    init(url: URL) {
        let standardized = url.standardizedFileURL
        let parent = standardized.deletingLastPathComponent().resolvingSymlinksInPath()
        self.url = parent.appendingPathComponent(standardized.lastPathComponent)
    }

    struct RevocationRecovery {
        let connections: [MobileDirectConnection]
        let quarantinedConnectionIDs: Set<UUID>
    }

    /// Applies the independent write-ahead journal before ordinary connection
    /// reconciliation. An uncertain marker quarantines only that link until a
    /// fresh authenticated STATUS; a denied marker is an absorbing local deny.
    static func applyRevocationMarkers(_ markers: [MobileRevocationMarker],
                                       to stored: [MobileDirectConnection]) -> RevocationRecovery {
        var connections = stored
        var quarantined = Set<UUID>()
        for marker in markers {
            guard let index = connections.firstIndex(where: {
                $0.connectionID == marker.connectionID
                    && $0.deviceID == marker.deviceID
                    && $0.fingerprint == marker.fingerprint
            }) else { continue }
            switch marker.state {
            case .uncertain:
                if !connections[index].revoked { quarantined.insert(marker.connectionID) }
            case .denied:
                let previousProjects = connections[index].projectIDs
                connections[index].capabilities = []
                connections[index].projectIDs = []
                connections[index].acceptedProjectIDs = []
                connections[index].ignoredProjectIDs = []
                connections[index].projectDescriptors = []
                connections[index].newFilePaths = [:]
                connections[index].comparisonCode = nil
                connections[index].revoked = true
                connections[index].pendingPurgeProjectIDs.formUnion(previousProjects)
                connections[index].pendingPurgeProjectIDs.formUnion(marker.projectIDs)
            }
        }
        return RevocationRecovery(connections: connections, quarantinedConnectionIDs: quarantined)
    }

    static func refreshCapabilities(_ status: DirectDeviceStatus,
                                    connection: inout MobileDirectConnection,
                                    client: DirectEnrollmentClient,
                                    credential: String) async throws -> DirectDeviceStatus {
        guard status.capabilities.contains(.rubricExchangeV1) else {
            connection.capabilities = []
            return status
        }
        guard !connection.capabilities.contains(.rubricExchangeV1),
              !connection.capabilityRefreshAttempted else { return status }
        do {
            let receipt = try await client.updateCapabilities(deviceID: connection.deviceID,
                                                               credential: credential)
            guard receipt.acceptedCapabilities?.contains(.rubricExchangeV1) == true else {
                throw RubricExchangeError.unsupported
            }
            connection.capabilities = [.rubricExchangeV1]
            connection.capabilityRefreshAttempted = false
        } catch RubricExchangeError.unsupported {
            connection.capabilityRefreshAttempted = true
            connection.capabilities = []
        }
        return status
    }

    func load() throws -> [MobileDirectConnection] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let values = try url.resourceValues(forKeys: [.isSymbolicLinkKey, .fileSizeKey])
        guard values.isSymbolicLink != true, (values.fileSize ?? 0) <= Self.maximumBytes else {
            throw SyncError.invalidSnapshot
        }
        return try JSONDecoder().decode([MobileDirectConnection].self, from: Data(contentsOf: url))
    }

    static func preservingCurrentDisplayNames(in snapshot: [MobileDirectConnection],
                                              current: [MobileDirectConnection]) -> [MobileDirectConnection] {
        var reconciled = snapshot
        for index in reconciled.indices {
            guard let latest = current.first(where: { reconciled[index].hasSameIdentity(as: $0) }) else { continue }
            reconciled[index].displayName = latest.displayName
        }
        return reconciled
    }

    /// A missing Keychain item is a durable loss of authorization, while a
    /// Keychain read error must remain a retryable load failure. Reclassify
    /// only the former so an interrupted revocation journal can be repaired
    /// on the next launch without hiding a still-authorized connection.
    func reconcileMissingCredentials(_ connections: [MobileDirectConnection],
                                     credentials: DeviceCredentialStore) async throws -> [MobileDirectConnection] {
        var repaired = connections
        for index in repaired.indices where !repaired[index].revoked {
            guard try await credentials.credential(deviceID: repaired[index].deviceID) == nil else { continue }
            let projectIDs = repaired[index].projectIDs
            repaired[index].capabilities = []
            repaired[index].projectIDs = []
            repaired[index].acceptedProjectIDs = []
            repaired[index].ignoredProjectIDs = []
            repaired[index].projectDescriptors = []
            repaired[index].newFilePaths = [:]
            repaired[index].comparisonCode = nil
            repaired[index].revoked = true
            repaired[index].pendingPurgeProjectIDs.formUnion(projectIDs)
        }
        return repaired
    }

    func loadVisibleProjects(connections: [MobileDirectConnection],
                             quarantinedConnectionIDs: Set<UUID> = [],
                             excludedProjectIDs: Set<UUID> = [],
                             credentials: DeviceCredentialStore,
                             corpus: OfflineCorpusStore) async throws -> [OfflineProject] {
        var activeProjectIDs = Set<UUID>()
        var revokedProjectIDs = Set<UUID>()
        var unavailableProjectIDs = Set<UUID>()
        for connection in connections where !connection.revoked {
            if quarantinedConnectionIDs.contains(connection.connectionID) {
                unavailableProjectIDs.formUnion(connection.projectIDs)
                continue
            }
            guard try await credentials.credential(deviceID: connection.deviceID) != nil else {
                unavailableProjectIDs.formUnion(connection.projectIDs)
                continue
            }
            activeProjectIDs.formUnion(connection.acceptedProjectIDs.intersection(connection.projectIDs))
        }
        for connection in connections where connection.revoked {
            revokedProjectIDs.formUnion(connection.projectIDs)
            revokedProjectIDs.formUnion(connection.pendingPurgeProjectIDs)
        }
        let hiddenProjectIDs = revokedProjectIDs.union(unavailableProjectIDs)
        var loaded: [OfflineProject] = []
        for id in try await corpus.projectIDs() {
            // Device-local deletion is a tombstone, not a post-load display
            // filter. A late or malformed cache must not be decoded before
            // the user's removal intent is applied.
            guard !excludedProjectIDs.contains(id) else { continue }
            guard !hiddenProjectIDs.contains(id) || activeProjectIDs.contains(id) else { continue }
            if let project = try await corpus.load(id: id) {
                loaded.append(project)
            }
        }
        return loaded.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func save(_ snapshot: [MobileDirectConnection]) throws {
        let parent = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        let values = try? url.resourceValues(forKeys: [.isSymbolicLinkKey])
        guard values?.isSymbolicLink != true else { throw SyncError.invalidPath }
        let data = try JSONEncoder().encode(snapshot)
        guard data.count <= Self.maximumBytes else { throw SyncError.sizeLimitExceeded }

        let temporary = parent.appendingPathComponent(".connections-\(UUID().uuidString).tmp")
        defer { try? FileManager.default.removeItem(at: temporary) }
        try data.write(to: temporary)
        try setOwnerOnlyPermissions(at: temporary)
        let attributes = try FileManager.default.attributesOfItem(atPath: temporary.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular,
              (attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600 else {
            throw SyncError.invalidPath
        }
        if FileManager.default.fileExists(atPath: url.path) {
            _ = try FileManager.default.replaceItemAt(url, withItemAt: temporary,
                                                      options: .usingNewMetadataOnly)
        } else {
            try FileManager.default.moveItem(at: temporary, to: url)
        }
    }

    private func setOwnerOnlyPermissions(at url: URL) throws {
        try FileManager.default.setAttributes([.posixPermissions: NSNumber(value: Int16(0o600))],
                                              ofItemAtPath: url.path)
    }
}
