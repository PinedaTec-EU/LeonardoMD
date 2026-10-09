import Foundation

public struct SharedProjectDescriptor: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public let name: String
    public let scope: CorpusScope
    public init(id: UUID, name: String, scope: CorpusScope) { self.id = id; self.name = name; self.scope = scope }
}

public struct SharedProjectSource: Sendable {
    public let descriptor: SharedProjectDescriptor
    public let snapshot: @Sendable () async throws -> CorpusSnapshot
    public init(descriptor: SharedProjectDescriptor, snapshot: @escaping @Sendable () async throws -> CorpusSnapshot) {
        self.descriptor = descriptor
        self.snapshot = snapshot
    }
}

public struct PairingChallenge: Codable, Sendable {
    public let id: UUID
    public let comparisonCode: String
    public let expiresAt: Date
}

public struct DirectDeviceStatus: Codable, Sendable {
    public let access: DeviceAccess
    public let projects: [SharedProjectDescriptor]
}

public enum DirectAuthorityError: Error, Sendable { case busy }

/// Single owner for consent state; a persisted mutation becomes visible atomically.
public actor DirectSyncAuthority {
    private var registry: PairingRegistry
    private let projects: [UUID: SharedProjectSource]
    private let fingerprint: Data
    private let persist: @Sendable (PairingRegistry) async throws -> Void
    private var changing = false

    public init(registry: PairingRegistry, projects: [SharedProjectSource], serverFingerprint: Data,
                persist: @escaping @Sendable (PairingRegistry) async throws -> Void) throws {
        guard serverFingerprint.count == 32, Set(projects.map { $0.descriptor.id }).count == projects.count else {
            throw PairingError.invalidProject
        }
        self.registry = registry
        self.projects = Dictionary(uniqueKeysWithValues: projects.map { ($0.descriptor.id, $0) })
        self.fingerprint = serverFingerprint
        self.persist = persist
    }

    public func consentState() -> PairingRegistry { registry }

    public func setEnabled(_ enabled: Bool) async throws {
        try await mutate { $0.setEnabled(enabled) }
    }

    public func createInvitation(now: Date) async throws -> PairingInvitation {
        try await mutate { try $0.createInvitation(now: now) }
    }

    public func beginPairing(deviceName: String, credential: String, invitation: PairingInvitation?, now: Date) async throws -> PairingChallenge {
        let request = try await mutate {
            try $0.requestPairing(deviceName: deviceName, credential: credential, invitation: invitation,
                                  serverFingerprint: fingerprint, now: now)
        }
        return PairingChallenge(id: request.id, comparisonCode: request.comparisonCode, expiresAt: request.expiresAt)
    }

    public func approve(requestID: UUID, code: String, projectIDs: Set<UUID>, now: Date) async throws {
        guard projectIDs.allSatisfy({ projects[$0] != nil }) else { throw PairingError.invalidProject }
        _ = try await mutate { try $0.approve(requestID: requestID, comparisonCode: code, projects: projectIDs, now: now) }
    }

    public func revoke(deviceID: UUID) async throws { try await mutate { try $0.revoke(deviceID: deviceID) } }

    public func status(deviceID: UUID, credential: String, now: Date) throws -> DirectDeviceStatus {
        guard !changing else { throw DirectAuthorityError.busy }
        let access = try registry.pairingStatus(requestID: deviceID, credential: credential, now: now)
        let granted = access == .authorized ? registry.devices.first(where: { $0.id == deviceID })?.projects ?? [] : []
        return DirectDeviceStatus(access: access,
            projects: granted.compactMap { projects[$0]?.descriptor }.sorted { $0.name < $1.name })
    }

    public func snapshot(deviceID: UUID, credential: String, projectID: UUID) async throws -> CorpusSnapshot {
        try checkAccess(deviceID: deviceID, credential: credential, projectID: projectID)
        guard let project = projects[projectID] else { throw PairingError.invalidProject }
        let snapshot = try await project.snapshot()
        // Revocation/disable can happen while disk reads or main-actor buffer collection suspend.
        try checkAccess(deviceID: deviceID, credential: credential, projectID: projectID)
        try snapshot.validate(scope: project.descriptor.scope, limits: CorpusLimits())
        return snapshot
    }

    private func checkAccess(deviceID: UUID, credential: String, projectID: UUID) throws {
        guard !changing else { throw DirectAuthorityError.busy }
        guard try registry.access(deviceID: deviceID, credential: credential, projectID: projectID) == .authorized else {
            throw SyncError.revoked
        }
    }

    private func mutate<Result: Sendable>(_ operation: (inout PairingRegistry) throws -> Result) async throws -> Result {
        guard !changing else { throw DirectAuthorityError.busy }
        changing = true
        defer { changing = false }
        var updated = registry
        let result = try operation(&updated)
        try await persist(updated)
        registry = updated
        return result
    }
}
