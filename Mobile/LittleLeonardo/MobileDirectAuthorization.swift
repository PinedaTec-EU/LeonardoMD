import Foundation

struct MobileConnectionToken: Sendable {
    let connectionID: UUID
    let deviceID: UUID
    let fingerprint: Data
    let cacheEpoch: UInt64
    let authorizationGeneration: UInt64
}

struct MobileAuthorizationGenerations {
    private var values: [UUID: UInt64] = [:]
    private var deniedConnections: Set<UUID> = []
    private var deniedProjectIDs: [UUID: Set<UUID>] = [:]
    private var quarantinedConnections: Set<UUID> = []

    subscript(connectionID: UUID) -> UInt64 { values[connectionID, default: 0] }

    mutating func invalidate(connectionID: UUID) {
        values[connectionID, default: 0] &+= 1
    }

    var denied: Set<UUID> { deniedConnections }

    var quarantined: Set<UUID> { quarantinedConnections }

    func isDenied(connectionID: UUID) -> Bool {
        deniedConnections.contains(connectionID)
    }

    func isQuarantined(connectionID: UUID) -> Bool {
        quarantinedConnections.contains(connectionID)
    }

    func projectsPendingPurge(for connectionID: UUID) -> Set<UUID> {
        deniedProjectIDs[connectionID, default: []]
    }

    mutating func confirmDenied(connectionID: UUID, projectIDs: Set<UUID>) {
        let inserted = deniedConnections.insert(connectionID).inserted
        deniedProjectIDs[connectionID, default: []].formUnion(projectIDs)
        if inserted { invalidate(connectionID: connectionID) }
        quarantinedConnections.remove(connectionID)
    }

    mutating func quarantine(connectionID: UUID) {
        guard !deniedConnections.contains(connectionID) else { return }
        quarantinedConnections.insert(connectionID)
    }

    mutating func clearQuarantine(connectionID: UUID) {
        guard !deniedConnections.contains(connectionID) else { return }
        quarantinedConnections.remove(connectionID)
    }
}
