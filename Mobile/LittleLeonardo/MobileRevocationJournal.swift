import Foundation
import LeonardoSync

enum MobileRevocationMarkerState: String, Codable, Sendable {
    case uncertain
    case denied
}

enum MobileRevocationOutcome: Sendable {
    case authorized
    case transient
    case denied
}

struct MobileRevocationOperation: Codable, Equatable, Sendable {
    let sessionID: UUID
    let operationID: UUID
}

struct MobileRevocationTicket: Equatable, Sendable {
    let sessionID: UUID
    let operationID: UUID
    let connectionID: UUID
    let deviceID: UUID
    let fingerprint: Data
    let generation: UInt64
}

struct MobileRevocationMarker: Codable, Equatable, Sendable {
    let connectionID: UUID
    let deviceID: UUID
    let fingerprint: Data
    var projectIDs: Set<UUID>
    var state: MobileRevocationMarkerState
    var generation: UInt64
    var operations: [MobileRevocationOperation]
}

protocol MobileRevocationJournalStore: Sendable {
    func load() throws -> [MobileRevocationMarker]
    func begin(connectionID: UUID, deviceID: UUID, fingerprint: Data,
               projectIDs: Set<UUID>) throws -> MobileRevocationTicket
    func complete(_ ticket: MobileRevocationTicket, outcome: MobileRevocationOutcome) throws
    func recordDenied(connectionID: UUID, deviceID: UUID, fingerprint: Data,
                      projectIDs: Set<UUID>) throws
}

/// A write-ahead journal for authenticated direct operations.
///
/// The marker is deliberately independent from the connection snapshot and the
/// Keychain. It is written before an authenticated request, so a failure while
/// recording the eventual outcome cannot erase the only restart-safe evidence
/// that the request was in flight.
struct MobileRevocationJournal: MobileRevocationJournalStore {
    static let maximumBytes = 1 * 1_024 * 1_024
    private static let maximumMarkers = 256
    private static let maximumProjectsPerMarker = 10_000

    let url: URL
    let sessionID: UUID

    init(url: URL, sessionID: UUID = UUID()) {
        let standardized = url.standardizedFileURL
        let parent = standardized.deletingLastPathComponent().resolvingSymlinksInPath()
        self.url = parent.appendingPathComponent(standardized.lastPathComponent)
        self.sessionID = sessionID
    }

    func load() throws -> [MobileRevocationMarker] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let values = try url.resourceValues(forKeys: [.isSymbolicLinkKey, .fileSizeKey])
        guard values.isSymbolicLink != true, (values.fileSize ?? 0) <= Self.maximumBytes else {
            throw SyncError.invalidSnapshot
        }
        let markers = try JSONDecoder().decode([MobileRevocationMarker].self, from: Data(contentsOf: url))
        guard markers.count <= Self.maximumMarkers,
              Set(markers.map(\.connectionID)).count == markers.count,
              markers.allSatisfy({ $0.projectIDs.count <= Self.maximumProjectsPerMarker }) else {
            throw SyncError.invalidSnapshot
        }
        return markers
    }

    func begin(connectionID: UUID, deviceID: UUID, fingerprint: Data,
               projectIDs: Set<UUID>) throws -> MobileRevocationTicket {
        var markers = try load()
        let operationID = UUID()
        let operation = MobileRevocationOperation(sessionID: sessionID, operationID: operationID)
        let generation: UInt64
        if let index = markers.firstIndex(where: { $0.connectionID == connectionID }) {
            guard markers[index].deviceID == deviceID, markers[index].fingerprint == fingerprint else {
                throw SyncError.invalidSnapshot
            }
            guard markers[index].state != .denied else { throw SyncError.revoked }
            guard markers[index].projectIDs.union(projectIDs).count <= Self.maximumProjectsPerMarker else {
                throw SyncError.sizeLimitExceeded
            }
            markers[index].projectIDs.formUnion(projectIDs)
            markers[index].operations.append(operation)
            generation = markers[index].generation &+ 1
            markers[index].generation = generation
        } else {
            guard markers.count < Self.maximumMarkers,
                  projectIDs.count <= Self.maximumProjectsPerMarker else {
                throw SyncError.sizeLimitExceeded
            }
            generation = 1
            markers.append(MobileRevocationMarker(connectionID: connectionID, deviceID: deviceID,
                                                  fingerprint: fingerprint, projectIDs: projectIDs,
                                                  state: .uncertain, generation: generation,
                                                  operations: [operation]))
        }
        try save(markers)
        return MobileRevocationTicket(sessionID: sessionID, operationID: operationID,
                                      connectionID: connectionID, deviceID: deviceID,
                                      fingerprint: fingerprint, generation: generation)
    }

    func complete(_ ticket: MobileRevocationTicket, outcome: MobileRevocationOutcome) throws {
        var markers = try load()
        guard let index = markers.firstIndex(where: { $0.connectionID == ticket.connectionID }) else { return }
        guard markers[index].deviceID == ticket.deviceID,
              markers[index].fingerprint == ticket.fingerprint,
              markers[index].generation >= ticket.generation else {
            throw SyncError.invalidSnapshot
        }
        if markers[index].state == .denied {
            return
        }
        switch outcome {
        case .denied:
            markers[index].state = .denied
            markers[index].operations.removeAll()
            try save(markers)
        case .authorized:
            markers[index].operations.removeAll {
                $0.sessionID == ticket.sessionID && $0.operationID == ticket.operationID
            }
            let hasCurrentSessionOperation = markers[index].operations.contains { $0.sessionID == sessionID }
            if hasCurrentSessionOperation {
                try save(markers)
            } else {
                markers.remove(at: index)
                try save(markers)
            }
        case .transient:
            markers[index].operations.removeAll {
                $0.sessionID == ticket.sessionID && $0.operationID == ticket.operationID
            }
            // An inherited operation represents a crash/unknown outcome. A
            // transient result is not authenticated revalidation, so retain
            // that marker until a later successful STATUS can clear it.
            if markers[index].operations.isEmpty {
                markers.remove(at: index)
            }
            try save(markers)
        }
    }

    func recordDenied(connectionID: UUID, deviceID: UUID, fingerprint: Data,
                      projectIDs: Set<UUID>) throws {
        var markers = try load()
        if let index = markers.firstIndex(where: { $0.connectionID == connectionID }) {
            guard markers[index].deviceID == deviceID, markers[index].fingerprint == fingerprint else {
                throw SyncError.invalidSnapshot
            }
            guard markers[index].projectIDs.union(projectIDs).count <= Self.maximumProjectsPerMarker else {
                throw SyncError.sizeLimitExceeded
            }
            markers[index].projectIDs.formUnion(projectIDs)
            markers[index].state = .denied
            markers[index].operations.removeAll()
        } else {
            guard markers.count < Self.maximumMarkers,
                  projectIDs.count <= Self.maximumProjectsPerMarker else {
                throw SyncError.sizeLimitExceeded
            }
            markers.append(MobileRevocationMarker(connectionID: connectionID, deviceID: deviceID,
                                                  fingerprint: fingerprint, projectIDs: projectIDs,
                                                  state: .denied, generation: 1, operations: []))
        }
        try save(markers)
    }

    private func save(_ markers: [MobileRevocationMarker]) throws {
        let parent = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        let values = try? url.resourceValues(forKeys: [.isSymbolicLinkKey])
        guard values?.isSymbolicLink != true else { throw SyncError.invalidPath }
        let data = try JSONEncoder().encode(markers)
        guard data.count <= Self.maximumBytes else { throw SyncError.sizeLimitExceeded }

        let temporary = parent.appendingPathComponent(".revocation-\(UUID().uuidString).tmp")
        defer { try? FileManager.default.removeItem(at: temporary) }
        try data.write(to: temporary)
        try FileManager.default.setAttributes([.posixPermissions: NSNumber(value: Int16(0o600))],
                                              ofItemAtPath: temporary.path)
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
}
