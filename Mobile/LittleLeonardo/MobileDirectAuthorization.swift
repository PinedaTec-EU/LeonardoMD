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
    private var quarantinedProjectIDs: [UUID: Set<UUID>] = [:]

    subscript(connectionID: UUID) -> UInt64 { values[connectionID, default: 0] }

    mutating func invalidate(connectionID: UUID) {
        values[connectionID, default: 0] &+= 1
    }

    var denied: Set<UUID> { deniedConnections }

    var quarantined: Set<UUID> { quarantinedConnections }

    var projectsUnderQuarantine: Set<UUID> {
        quarantinedProjectIDs.values.reduce(into: Set<UUID>()) { $0.formUnion($1) }
    }

    func isDenied(connectionID: UUID) -> Bool {
        deniedConnections.contains(connectionID)
    }

    func isQuarantined(connectionID: UUID) -> Bool {
        quarantinedConnections.contains(connectionID)
    }

    func projectsPendingPurge(for connectionID: UUID) -> Set<UUID> {
        deniedProjectIDs[connectionID, default: []]
    }

    func projectsUnderQuarantine(for connectionID: UUID) -> Set<UUID> {
        quarantinedProjectIDs[connectionID, default: []]
    }

    mutating func confirmDenied(connectionID: UUID, projectIDs: Set<UUID>) {
        let inserted = deniedConnections.insert(connectionID).inserted
        deniedProjectIDs[connectionID, default: []].formUnion(projectIDs)
        if inserted { invalidate(connectionID: connectionID) }
        quarantinedConnections.remove(connectionID)
        quarantinedProjectIDs[connectionID] = nil
    }

    mutating func quarantine(connectionID: UUID, projectIDs: Set<UUID> = [],
                             advanceGeneration: Bool = false) {
        guard !deniedConnections.contains(connectionID) else { return }
        let inserted = quarantinedConnections.insert(connectionID).inserted
        let existingProjects = quarantinedProjectIDs[connectionID, default: []]
        let expanded = !projectIDs.isSubset(of: existingProjects)
        // Invalidate tokens that could otherwise finish after this quarantine.
        if inserted || expanded || advanceGeneration { invalidate(connectionID: connectionID) }
        quarantinedProjectIDs[connectionID, default: []].formUnion(projectIDs)
    }

    mutating func clearQuarantine(connectionID: UUID, authorizationGeneration: UInt64) {
        guard !deniedConnections.contains(connectionID),
              values[connectionID, default: 0] == authorizationGeneration else { return }
        quarantinedConnections.remove(connectionID)
        quarantinedProjectIDs[connectionID] = nil
    }
}
