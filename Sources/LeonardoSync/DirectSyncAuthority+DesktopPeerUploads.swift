import Foundation

extension DirectSyncAuthority {
    /// An authenticated client may close only the exact proposal whose durable result it
    /// incorporated. Keep consent stable across storage awaits and retain the receipt.
    public func acknowledgeProposal(deviceID: UUID, credential: String, projectID: UUID,
                                    proposalID: UUID, proof: DesktopPeerReceiptAcknowledgement) async throws {
        let expectedView = try uploadView(deviceID: deviceID, credential: credential, projectID: projectID)
        guard let receipts, let uploads else { throw DirectAuthorityError.busy }
        changing = true
        defer { changing = false }
        guard let view = try await uploads.view(deviceID: deviceID, projectID: projectID,
                                                proposalID: proposalID, grantSelection: expectedView.grantSelection),
              view.acceptsResumeRequest(expectedView) else { throw SyncError.outsideScope }
        guard let receipt = try await receipts.load(deviceID: deviceID, projectID: projectID,
                                                    proposalID: proposalID, selection: view.selection),
              receipt.projectID == projectID, receipt.proposalID == proposalID else {
            throw SyncError.invalidSnapshot
        }
        let compatibleReceipt = try Self.receipt(receipt, for: view)
        try view.selection.validate(compatibleReceipt.accepted)
        guard try DesktopPeerReceiptAcknowledgement(receipt: compatibleReceipt) == proof else {
            throw SyncError.invalidSnapshot
        }
        try await uploads.acknowledge(deviceID: deviceID, projectID: projectID,
                                      proposalID: proposalID, view: view)
    }

    /// Historical accepted result; authorization is rechecked after suspended storage reads.
    public func proposalReceipt(deviceID: UUID, credential: String, projectID: UUID,
                                proposalID: UUID) async throws -> DesktopPeerProposalReceipt? {
        let expectedView = try uploadView(deviceID: deviceID, credential: credential, projectID: projectID)
        guard let receipts else { throw DirectAuthorityError.busy }
        // A client checks for an accepted result before beginning an upload. The persisted
        // view is authoritative after an update; a new proposal still needs no upload slot.
        let persistedView = try await uploads?.view(deviceID: deviceID, projectID: projectID,
            proposalID: proposalID, grantSelection: expectedView.grantSelection)
        if let persistedView, !persistedView.acceptsResumeRequest(expectedView) { throw SyncError.outsideScope }
        let lookupView = persistedView ?? expectedView
        let receipt = try await receipts.load(deviceID: deviceID, projectID: projectID,
                                              proposalID: proposalID, selection: lookupView.selection)
        guard try uploadView(deviceID: deviceID, credential: credential, projectID: projectID) == expectedView else {
            throw SyncError.outsideScope
        }
        if let persistedView {
            guard let uploads,
                  try await uploads.view(deviceID: deviceID, projectID: projectID,
                    proposalID: proposalID, grantSelection: expectedView.grantSelection) == persistedView else {
                throw SyncError.outsideScope
            }
        }
        if let receipt {
            guard receipt.projectID == projectID, receipt.proposalID == proposalID else { throw SyncError.invalidSnapshot }
            return try Self.receipt(receipt, for: lookupView)
        }
        return receipt
    }

    public func beginUpload(deviceID: UUID, credential: String,
                            upload: DesktopPeerUpload) async throws -> DesktopPeerUploadProgress {
        let view = try uploadView(deviceID: deviceID, credential: credential, projectID: upload.projectID)
        guard let uploads else { throw DirectAuthorityError.busy }
        let count = try await uploads.begin(deviceID: deviceID, upload: upload, view: view)
        guard try uploadView(deviceID: deviceID, credential: credential, projectID: upload.projectID) == view else {
            throw SyncError.outsideScope
        }
        return DesktopPeerUploadProgress(proposalID: upload.proposalID, receivedBytes: count)
    }

    public func appendUpload(deviceID: UUID, credential: String,
                             chunk: DesktopPeerUploadChunk) async throws -> DesktopPeerUploadProgress {
        let view = try uploadView(deviceID: deviceID, credential: credential, projectID: chunk.upload.projectID)
        guard let uploads else { throw DirectAuthorityError.busy }
        let count = try await uploads.append(deviceID: deviceID, upload: chunk.upload, offset: chunk.offset,
                                             bytes: chunk.bytes, view: view)
        guard try uploadView(deviceID: deviceID, credential: credential, projectID: chunk.upload.projectID) == view else {
            throw SyncError.outsideScope
        }
        return DesktopPeerUploadProgress(proposalID: chunk.upload.proposalID, receivedBytes: count)
    }

    public func submitUpload(deviceID: UUID, credential: String,
                             upload: DesktopPeerUpload) async throws -> DesktopPeerUploadProgress {
        let view = try uploadView(deviceID: deviceID, credential: credential, projectID: upload.projectID)
        guard let uploads else { throw DirectAuthorityError.busy }
        try await uploads.submit(deviceID: deviceID, upload: upload, view: view)
        guard try uploadView(deviceID: deviceID, credential: credential, projectID: upload.projectID) == view else {
            throw SyncError.outsideScope
        }
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
                let grantSelection = try descriptor.selection ?? CorpusSelection(folders: [descriptor.scope.folder], documents: [])
                if let pending = try await uploads.pending(deviceID: device.id, projectID: projectID,
                                                            grantSelection: grantSelection),
                   ownerCanReview(deviceID: device.id, projectID: projectID) {
                    if let receipts, try await receipts.contains(deviceID: device.id, projectID: projectID,
                        proposalID: pending.upload.proposalID, selection: pending.view.selection) { continue }
                    guard ownerCanReview(deviceID: device.id, projectID: projectID) else { continue }
                    result.append(DesktopPeerIncomingProposal(deviceID: device.id, deviceName: device.name,
                        upload: pending.upload, view: pending.view))
                }
            }
        }
        return result.filter { ownerCanReview(deviceID: $0.deviceID, projectID: $0.upload.projectID) }
    }

    public func incomingProposal(deviceID: UUID, upload: DesktopPeerUpload) async throws -> DesktopPeerProposal {
        guard ownerCanReview(deviceID: deviceID, projectID: upload.projectID),
              let descriptor = projects[upload.projectID]?.descriptor, let uploads else { throw SyncError.revoked }
        let grantSelection = try descriptor.selection ?? CorpusSelection(folders: [descriptor.scope.folder], documents: [])
        guard let pending = try await uploads.pending(deviceID: deviceID, projectID: upload.projectID,
            grantSelection: grantSelection), pending.upload == upload else { throw SyncError.invalidSnapshot }
        let proposal = try await uploads.finish(deviceID: deviceID, upload: upload, view: pending.view)
        guard ownerCanReview(deviceID: deviceID, projectID: upload.projectID) else { throw SyncError.revoked }
        return proposal
    }

    public func reviewIncomingProposal(deviceID: UUID, upload: DesktopPeerUpload) async throws -> DesktopPeerProposalReview {
        let proposal = try await incomingProposal(deviceID: deviceID, upload: upload)
        guard let source = projects[upload.projectID], ownerCanReview(deviceID: deviceID, projectID: upload.projectID) else { throw SyncError.revoked }
        let descriptor = source.descriptor
        let grantSelection = try descriptor.selection ?? CorpusSelection(folders: [descriptor.scope.folder], documents: [])
        guard let uploads,
              let pending = try await uploads.pending(deviceID: deviceID, projectID: upload.projectID,
                grantSelection: grantSelection), pending.upload == upload else { throw SyncError.invalidSnapshot }
        let epoch = sourceEpoch
        let captured: CorpusSnapshot
        if let filtered = source.snapshotExcludingExtensions {
            captured = try await filtered(pending.view.excludedExtensions)
        } else {
            captured = try await source.snapshot()
        }
        let snapshot = Self.filter(captured, to: pending.view)
        guard sourceEpoch == epoch else { throw ReconciliationError.staleComparison }
        guard ownerCanReview(deviceID: deviceID, projectID: upload.projectID) else { throw SyncError.revoked }
        return try DesktopPeerProposalReview(proposal: proposal, source: snapshot, view: pending.view)
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
        view: DesktopPeerUploadView? = nil,
        operation: @Sendable (DesktopPeerProposal, URL) async throws -> DesktopPeerAcceptanceResult) async throws -> DesktopPeerAcceptanceResult {
        let proposal = try await incomingProposal(deviceID: deviceID, upload: upload)
        if let view {
            guard let descriptor = projects[upload.projectID]?.descriptor, let uploads else { throw SyncError.revoked }
            let grantSelection = try descriptor.selection ?? CorpusSelection(folders: [descriptor.scope.folder], documents: [])
            guard let pending = try await uploads.pending(deviceID: deviceID, projectID: upload.projectID,
                grantSelection: grantSelection), pending.upload == upload, pending.view == view else {
                throw ReconciliationError.staleComparison
            }
        }
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
    private func uploadView(deviceID: UUID, credential: String, projectID: UUID) throws -> DesktopPeerUploadView {
        let descriptor = try reconciliationDescriptor(deviceID: deviceID, credential: credential, projectID: projectID)
        let grantSelection = try descriptor.selection ?? CorpusSelection(folders: [descriptor.scope.folder], documents: [])
        guard let compatible = Self.legacyCompatibleDescriptor(descriptor) else { throw SyncError.outsideScope }
        let selection = try compatible.selection ?? CorpusSelection(folders: [compatible.scope.folder], documents: [])
        return DesktopPeerUploadView(grantSelection: grantSelection, selection: selection,
                                     supportsLeonardoFormats: false)
    }

    private static func filterLeonardoFiles(_ snapshot: CorpusSnapshot) -> CorpusSnapshot {
        let files = snapshot.files.filter { !DirectReadCapability.excludesLegacyFormat($0.path) }
        guard files.count != snapshot.files.count else { return snapshot }
        return CorpusSnapshot(revision: CorpusRevision.make(files: files), files: files)
    }

    private static func filter(_ snapshot: CorpusSnapshot, to view: DesktopPeerUploadView) -> CorpusSnapshot {
        let files = snapshot.files.filter { view.selection.contains($0.path) &&
            !view.excludedExtensions.contains(($0.path as NSString).pathExtension.lowercased()) }
        return CorpusSnapshot(revision: CorpusRevision.make(files: files), files: files)
    }

    private static func receipt(_ receipt: DesktopPeerProposalReceipt,
                                for view: DesktopPeerUploadView) throws -> DesktopPeerProposalReceipt {
        let accepted = filterLeonardoFiles(receipt.accepted)
        return try DesktopPeerProposalReceipt(proposalID: receipt.proposalID, projectID: receipt.projectID,
                                              accepted: accepted)
    }
}
