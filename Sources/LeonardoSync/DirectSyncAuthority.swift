import Foundation

public struct SharedProjectDescriptor: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public let name: String
    public let scope: CorpusScope
    public let selection: CorpusSelection?
    public init(id: UUID, name: String, scope: CorpusScope, selection: CorpusSelection? = nil) {
        self.id = id; self.name = name; self.scope = scope; self.selection = selection
    }
}

public struct SharedProjectSource: Sendable {
    public let descriptor: SharedProjectDescriptor
    public let rootURL: URL?
    public let snapshot: @Sendable () async throws -> CorpusSnapshot
    public init(descriptor: SharedProjectDescriptor, rootURL: URL? = nil, snapshot: @escaping @Sendable () async throws -> CorpusSnapshot) {
        self.descriptor = descriptor
        self.rootURL = rootURL?.standardizedFileURL.resolvingSymlinksInPath()
        self.snapshot = snapshot
    }
}

public struct PairingChallenge: Codable, Sendable {
    public let id: UUID
    public let comparisonCode: String
    public let expiresAt: Date
    public init(id: UUID, comparisonCode: String, expiresAt: Date) {
        self.id = id; self.comparisonCode = comparisonCode; self.expiresAt = expiresAt
    }
}

public struct DirectDeviceStatus: Codable, Sendable {
    public let access: DeviceAccess
    public let projects: [SharedProjectDescriptor]
    public init(access: DeviceAccess, projects: [SharedProjectDescriptor]) { self.access = access; self.projects = projects }
}

public enum DirectAuthorityError: Error, Sendable { case busy }

/// Single owner for consent state; a persisted mutation becomes visible atomically.
public actor DirectSyncAuthority {
    private var registry: PairingRegistry
    private let projects: [UUID: SharedProjectSource]
    private let fingerprint: Data
    private let persist: @Sendable (PairingRegistry) async throws -> Void
    private var changing = false
    private var sourceEpoch = UUID()
    private let uploads: (any DesktopPeerUploadStore)?
    private let receipts: (any DesktopPeerReceiptStore)?

    public init(registry: PairingRegistry, projects: [SharedProjectSource], serverFingerprint: Data,
                persist: @escaping @Sendable (PairingRegistry) async throws -> Void, uploads: (any DesktopPeerUploadStore)? = nil, receipts: (any DesktopPeerReceiptStore)? = nil) throws {
        guard serverFingerprint.count == 32, Set(projects.map { $0.descriptor.id }).count == projects.count else {
            throw PairingError.invalidProject
        }
        self.registry = registry
        self.projects = Dictionary(uniqueKeysWithValues: projects.map { ($0.descriptor.id, $0) })
        self.fingerprint = serverFingerprint
        self.persist = persist
        self.uploads = uploads
        self.receipts = receipts
    }

    public func consentState() -> PairingRegistry { registry }

    public func setEnabled(_ enabled: Bool) async throws {
        try await mutate { $0.setEnabled(enabled) }
    }

    public func createInvitation(now: Date) async throws -> PairingInvitation {
        try await mutate { try $0.createInvitation(now: now) }
    }

    public func beginPairing(deviceName: String, credential: String, invitation: PairingInvitation?, now: Date, kind: PairingClientKind = .readOnly) async throws -> PairingChallenge {
        let request = try await mutate {
            try $0.requestPairing(deviceName: deviceName, credential: credential, invitation: invitation,
                                  serverFingerprint: fingerprint, now: now, kind: kind)
        }
        return PairingChallenge(id: request.id, comparisonCode: request.comparisonCode, expiresAt: request.expiresAt)
    }

    public func approve(requestID: UUID, code: String, projectIDs: Set<UUID>, now: Date) async throws {
        guard projectIDs.allSatisfy({ projects[$0] != nil }) else { throw PairingError.invalidProject }
        _ = try await mutate { try $0.approve(requestID: requestID, comparisonCode: code, projects: projectIDs, now: now) }
    }

    public func reconciliationDescriptor(deviceID: UUID, credential: String, projectID: UUID) throws -> SharedProjectDescriptor {
        guard !changing else { throw DirectAuthorityError.busy }
        try registry.authorizeReconciliation(deviceID: deviceID, credential: credential, projectID: projectID)
        guard let source = projects[projectID] else { throw PairingError.invalidProject }
        return source.descriptor
    }

    public func reject(requestID: UUID) async throws { try await mutate { $0.reject(requestID: requestID) } }

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
        let epoch = sourceEpoch
        let snapshot = try await project.snapshot()
        // Revocation/disable can happen while disk reads or main-actor buffer collection suspend.
        try checkAccess(deviceID: deviceID, credential: credential, projectID: projectID)
        guard sourceEpoch == epoch else { throw DirectAuthorityError.busy }
        try snapshot.validate(scope: project.descriptor.scope, limits: CorpusLimits())
        try project.descriptor.selection?.validate(snapshot)
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


extension DirectSyncAuthority {
    /// An authenticated client may close only the exact proposal whose durable result it
    /// incorporated. Keep consent stable across storage awaits and retain the receipt.
    public func acknowledgeProposal(deviceID: UUID, credential: String, projectID: UUID,
                                    proposalID: UUID, proof: DesktopPeerReceiptAcknowledgement) async throws {
        let selection = try uploadSelection(deviceID: deviceID, credential: credential, projectID: projectID)
        guard let receipts, let uploads else { throw DirectAuthorityError.busy }
        changing = true
        defer { changing = false }
        guard let receipt = try await receipts.load(deviceID: deviceID, projectID: projectID,
                                                    proposalID: proposalID, selection: selection),
              receipt.projectID == projectID, receipt.proposalID == proposalID else {
            throw SyncError.invalidSnapshot
        }
        try selection.validate(receipt.accepted)
        guard try DesktopPeerReceiptAcknowledgement(receipt: receipt) == proof else {
            throw SyncError.invalidSnapshot
        }
        try await uploads.acknowledge(deviceID: deviceID, projectID: projectID,
                                      proposalID: proposalID, selection: selection)
    }

    /// Historical accepted result; authorization is rechecked after suspended storage reads.
    public func proposalReceipt(deviceID: UUID, credential: String, projectID: UUID, proposalID: UUID) async throws -> DesktopPeerProposalReceipt? {
        let selection = try uploadSelection(deviceID: deviceID, credential: credential, projectID: projectID)
        guard let receipts else { throw DirectAuthorityError.busy }
        let receipt = try await receipts.load(deviceID: deviceID, projectID: projectID, proposalID: proposalID, selection: selection)
        guard try uploadSelection(deviceID: deviceID, credential: credential, projectID: projectID) == selection else { throw SyncError.outsideScope }
        if let receipt {
            guard receipt.projectID == projectID, receipt.proposalID == proposalID else { throw SyncError.invalidSnapshot }
            try selection.validate(receipt.accepted)
        }
        return receipt
    }

    public func beginUpload(deviceID: UUID, credential: String, upload: DesktopPeerUpload) async throws -> DesktopPeerUploadProgress {
        let selection = try uploadSelection(deviceID: deviceID, credential: credential, projectID: upload.projectID)
        guard let uploads else { throw DirectAuthorityError.busy }
        let count = try await uploads.begin(deviceID: deviceID, upload: upload, selection: selection)
        guard try uploadSelection(deviceID: deviceID, credential: credential, projectID: upload.projectID) == selection else { throw SyncError.outsideScope }
        return DesktopPeerUploadProgress(proposalID: upload.proposalID, receivedBytes: count)
    }

    public func appendUpload(deviceID: UUID, credential: String, chunk: DesktopPeerUploadChunk) async throws -> DesktopPeerUploadProgress {
        let selection = try uploadSelection(deviceID: deviceID, credential: credential, projectID: chunk.upload.projectID)
        guard let uploads else { throw DirectAuthorityError.busy }
        let count = try await uploads.append(deviceID: deviceID, upload: chunk.upload, offset: chunk.offset, bytes: chunk.bytes, selection: selection)
        guard try uploadSelection(deviceID: deviceID, credential: credential, projectID: chunk.upload.projectID) == selection else { throw SyncError.outsideScope }
        return DesktopPeerUploadProgress(proposalID: chunk.upload.proposalID, receivedBytes: count)
    }

    public func submitUpload(deviceID: UUID, credential: String, upload: DesktopPeerUpload) async throws -> DesktopPeerUploadProgress {
        let selection = try uploadSelection(deviceID: deviceID, credential: credential, projectID: upload.projectID)
        guard let uploads else { throw DirectAuthorityError.busy }
        try await uploads.submit(deviceID: deviceID, upload: upload, selection: selection)
        guard try uploadSelection(deviceID: deviceID, credential: credential, projectID: upload.projectID) == selection else { throw SyncError.outsideScope }
        return DesktopPeerUploadProgress(proposalID: upload.proposalID, receivedBytes: upload.byteCount, submitted: true)
    }

    /// Owner-only API; intentionally not an HTTP endpoint. Payloads are loaded only on selection.
    public func incomingProposals() async throws -> [DesktopPeerIncomingProposal] {
        guard !changing else { throw DirectAuthorityError.busy }
        guard let uploads else { return [] }
        var result: [DesktopPeerIncomingProposal] = []
        for device in registry.devices where !device.revoked && device.kind == .desktopPeer {
            for projectID in device.projects {
                guard let descriptor = projects[projectID]?.descriptor else { continue }
                let selection = try descriptor.selection ?? CorpusSelection(folders: [descriptor.scope.folder], documents: [])
                if let upload = try await uploads.pending(deviceID: device.id, projectID: projectID, selection: selection),
                   ownerCanReview(deviceID: device.id, projectID: projectID) {
                    if let receipts, try await receipts.contains(deviceID: device.id, projectID: projectID, proposalID: upload.proposalID, selection: selection) { continue }
                    guard ownerCanReview(deviceID: device.id, projectID: projectID) else { continue }
                    result.append(DesktopPeerIncomingProposal(deviceID: device.id, deviceName: device.name, upload: upload))
                }
            }
        }
        return result.filter { ownerCanReview(deviceID: $0.deviceID, projectID: $0.upload.projectID) }
    }

    public func incomingProposal(deviceID: UUID, upload: DesktopPeerUpload) async throws -> DesktopPeerProposal {
        guard ownerCanReview(deviceID: deviceID, projectID: upload.projectID),
              let descriptor = projects[upload.projectID]?.descriptor, let uploads else { throw SyncError.revoked }
        let selection = try descriptor.selection ?? CorpusSelection(folders: [descriptor.scope.folder], documents: [])
        guard try await uploads.pending(deviceID: deviceID, projectID: upload.projectID, selection: selection) == upload else { throw SyncError.invalidSnapshot }
        let proposal = try await uploads.finish(deviceID: deviceID, upload: upload, selection: selection)
        guard ownerCanReview(deviceID: deviceID, projectID: upload.projectID) else { throw SyncError.revoked }
        return proposal
    }

    public func reviewIncomingProposal(deviceID: UUID, upload: DesktopPeerUpload) async throws -> DesktopPeerProposalReview {
        let proposal = try await incomingProposal(deviceID: deviceID, upload: upload)
        guard let source = projects[upload.projectID], ownerCanReview(deviceID: deviceID, projectID: upload.projectID) else { throw SyncError.revoked }
        let epoch = sourceEpoch
        let snapshot = try await source.snapshot()
        guard sourceEpoch == epoch else { throw ReconciliationError.staleComparison }
        guard ownerCanReview(deviceID: deviceID, projectID: upload.projectID) else { throw SyncError.revoked }
        return try DesktopPeerProposalReview(proposal: proposal, source: snapshot)
    }

    /// Owner-only critical section: consent changes and service reads cannot interleave with
    /// application. The operation must additionally hold the native editor lease.
    public func withOwnerApplication(deviceID: UUID, upload: DesktopPeerUpload,
        operation: @Sendable (DesktopPeerProposal, URL) async throws -> DesktopPeerProposalReceipt) async throws -> DesktopPeerProposalReceipt {
        try await withOwnerApplicationResult(deviceID: deviceID, upload: upload) { proposal, root in
            try await DesktopPeerAcceptanceResult(receipt: operation(proposal, root), appliedNow: false)
        }.receipt
    }

    public func withOwnerApplicationResult(deviceID: UUID, upload: DesktopPeerUpload,
        operation: @Sendable (DesktopPeerProposal, URL) async throws -> DesktopPeerAcceptanceResult) async throws -> DesktopPeerAcceptanceResult {
        let proposal = try await incomingProposal(deviceID: deviceID, upload: upload)
        guard ownerCanReview(deviceID: deviceID, projectID: upload.projectID) else { throw SyncError.revoked }
        guard let root = projects[upload.projectID]?.rootURL else { throw PairingError.invalidProject }
        sourceEpoch = UUID()
        changing = true
        defer { changing = false }
        let result = try await operation(proposal, root)
        let receipt = result.receipt
        guard receipt.proposalID == proposal.id, receipt.projectID == proposal.projectID else { throw SyncError.invalidSnapshot }
        try proposal.selection.validate(receipt.accepted)
        return result
    }

    private func ownerCanReview(deviceID: UUID, projectID: UUID) -> Bool {
        !changing && registry.enabled && projects[projectID] != nil && registry.devices.contains {
            $0.id == deviceID && !$0.revoked && $0.kind == .desktopPeer && $0.projects.contains(projectID)
        }
    }
    private func uploadSelection(deviceID: UUID, credential: String, projectID: UUID) throws -> CorpusSelection {
        let descriptor = try reconciliationDescriptor(deviceID: deviceID, credential: credential, projectID: projectID)
        return try descriptor.selection ?? CorpusSelection(folders: [descriptor.scope.folder], documents: [])
    }
}
