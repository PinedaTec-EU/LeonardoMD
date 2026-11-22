import AppKit
import CryptoKit
import Darwin
import Foundation
import LeonardoCore
import LeonardoSync
import UniformTypeIdentifiers

extension AppSession {
    func guidedSigningConflictAllowsProgress() -> Bool {
        guard !externalConflict else {
            guidedSigningActionProblem = L10n.text(
                "The file changed outside LeonardoMD. Reload it or save your edits as a copy?"
            )
            return false
        }
        return true
    }

    /// The first confirmed location seals data, assignments, header and
    /// resources. A correction is an explicit new revision, never an inline
    /// edit that silently keeps old signatures.
    var guidedSigningContentLocked: Bool {
        // The correction path briefly opens the editor for one exact,
        // precomputed replacement. No await occurs while this flag is true;
        // ordinary editor actions cannot observe an open window.
        if guidedSigningRevisionEditing { return false }
        if guidedSigningRecoveryBlocked { return true }
        if let document = leonardoDocument,
           document.metadata.formatVersion >= LeonardoFormat.signingVersion,
           document.metadata.document.signing != nil,
           !guidedSigningReady || guidedSigningLoading || guidedSigningError != nil {
            return true
        }
        // A failed exact-sidecar lookup can leave no session in memory (for
        // example after a removed header with multiple historical revisions).
        // The error itself is the in-memory bound marker; keep editing and
        // field-fill blocked until the exact source is restored or corrected.
        if guidedSigningSession == nil, guidedSigningError != nil, !guidedSigningReady {
            return true
        }
        guard guidedSigningSession?.documentLocation == guidedSigningLocation,
              !guidedSigningRevisionEditing,
              let current = guidedSigningSession else { return false }
        guard let document = leonardoDocument,
              document.metadata.document.id == current.documentID,
              document.metadata.document.revision == current.initialRevision,
              document.metadata.document.signing == current.declaration,
              document.metadata.formatVersion >= LeonardoFormat.signingVersion else {
            return true
        }
        return current.snapshot != nil
    }

    var guidedSigningPositionLabel: String {
        guard let id = guidedSigningSession?.currentPositionID,
              let position = guidedSigningSession?.declaration.positions.first(where: { $0.id == id }) else {
            return L10n.text("No signer selected")
        }
        return position.label
    }

    private struct GuidedSigningRecoverySource {
        let session: LeonardoGuidedSigningSession
        let document: LeonardoDocument
        let resources: [LeonardoSigningResource]
    }

    /// Select recovery history only by the strongest identity available in
    /// the mutable source. An exact ID/revision is required when present;
    /// otherwise a single record for the coordinated location is the only
    /// admissible candidate. The sealed snapshot and all referenced resource
    /// bytes are verified before the candidate is exposed to the UI.
    private func trustedGuidedSigningRecoverySource(
        document: LeonardoDocument?,
        sessions: [LeonardoGuidedSigningSession]
    ) async -> GuidedSigningRecoverySource? {
        let documentID = document?.metadata.document.id?.trimmingCharacters(in: .whitespacesAndNewlines)
        let revision = document?.metadata.document.revision
        var candidates = sessions
        if let documentID, !documentID.isEmpty {
            candidates = candidates.filter { $0.documentID == documentID }
        }
        if let revision {
            candidates = candidates.filter { $0.initialRevision == revision }
        }
        guard candidates.count == 1, let candidate = candidates.first,
              let snapshot = candidate.snapshot else { return nil }
        guard let trustedDocument = try? LeonardoFormatParser.parse(snapshot.source),
              trustedDocument.metadata.formatVersion >= LeonardoFormat.signingVersion,
              trustedDocument.metadata.document.id == candidate.documentID,
              trustedDocument.metadata.document.revision == candidate.initialRevision,
              trustedDocument.metadata.document.signing == candidate.declaration,
              let resources = try? guidedSigningResources(for: snapshot.source),
              snapshot.matches(document: trustedDocument, resources: resources) else {
            return nil
        }
        if candidate.positions.values.contains(where: { $0.signature != nil }) {
            guard let trustStore = try? await guidedSigningCredentialStore.trustStore() else {
                return nil
            }
            let verification = candidate.signatureVerification(
                document: trustedDocument,
                resources: resources,
                trustStore: trustStore
            )
            guard !verification.isEmpty,
                  verification.values.allSatisfy({ $0 == .valid }) else { return nil }
        }
        return GuidedSigningRecoverySource(
            session: candidate,
            document: trustedDocument,
            resources: resources
        )
    }

    func guidedSigningRecoveryBlockedMessage() -> String {
        L10n.text(
            "The trusted signing snapshot could not be recovered safely. Restore the original signing header and resources before continuing."
        )
    }

    private func guidedSigningRecoveryAvailableMessage() -> String {
        L10n.text(
            "The signing header changed. A trusted sealed snapshot was recovered. Start a new revision, then save a copy before signing."
        )
    }

    func prepareGuidedSigning() async {
        let expectedLocation = guidedSigningLocation
        guard let expectedLocation else { return }
        let expectedContent = content
        var expectedSession = guidedSigningSession
        let preparationToken = UUID()
        guidedSigningPreparationToken = preparationToken
        func isCurrentPreparation() -> Bool {
            guidedSigningPreparationToken == preparationToken
                && guidedSigningLocation == expectedLocation
                && content == expectedContent
                && guidedSigningSession == expectedSession
        }
        guidedSigningLoading = true
        guidedSigningReady = false
        guidedSigningRecoveryBlocked = false
        guidedSigningError = nil
        guidedSigningActionProblem = nil
        defer {
            if isCurrentPreparation() {
                guidedSigningLoading = false
                if guidedSigningError == nil { guidedSigningReady = true }
            }
        }
        do {
            let profiles = try await guidedSigningStore.profiles()
            guard isCurrentPreparation() else { return }
            guidedSigningProfiles = profiles
            let credentialIDs = try await guidedSigningCredentialStore.credentialIDs()
            guard isCurrentPreparation() else { return }
            guidedSigningCredentialIDs = credentialIDs
            let storedForLocation = try await guidedSigningStore.sessions()
                .filter { $0.documentLocation == expectedLocation }
            guard isCurrentPreparation() else { return }

            guard let document = leonardoDocument,
                  document.metadata.formatVersion >= LeonardoFormat.signingVersion,
                  let declaration = document.metadata.document.signing else {
                // Without the mutable declaration there is no exact current
                // revision to select. Recover only one record whose sealed
                // snapshot and resources can be verified; never choose among
                // historical records by updatedAt or path alone.
                if let recovery = await trustedGuidedSigningRecoverySource(
                    document: leonardoDocument, sessions: storedForLocation
                ) {
                    expectedSession = recovery.session
                    guidedSigningSession = recovery.session
                    externalConflict = true
                    saveStatus = "External conflict · signing review protected"
                    guidedSigningTrustStore = try await guidedSigningCredentialStore.trustStore()
                    guard isCurrentPreparation() else { return }
                    guidedSigningTargets = []
                    guidedSigningVerification = [:]
                    guidedSigningError = guidedSigningRecoveryAvailableMessage()
                } else {
                    expectedSession = nil
                    guidedSigningSession = nil
                    guidedSigningTargets = []
                    if !storedForLocation.isEmpty {
                        guidedSigningRecoveryBlocked = true
                        guidedSigningVerification = [:]
                        guidedSigningTrustStore = nil
                        guidedSigningError = guidedSigningRecoveryBlockedMessage()
                    }
                }
                return
            }

            guard let documentID = document.metadata.document.id,
                  let revision = document.metadata.document.revision,
                  !documentID.isEmpty,
                  revision >= 1 else {
                expectedSession = nil
                guidedSigningSession = nil
                guidedSigningTargets = []
                guidedSigningRecoveryBlocked = !storedForLocation.isEmpty
                if !storedForLocation.isEmpty { guidedSigningVerification = [:]; guidedSigningTrustStore = nil }
                guidedSigningError = storedForLocation.isEmpty
                    ? L10n.text("The document has no stable signing identity or revision. Create a new revision before continuing.")
                    : guidedSigningRecoveryBlockedMessage()
                return
            }
            let exactSessions = storedForLocation.filter {
                $0.documentID == documentID && $0.initialRevision == revision
            }
            guard exactSessions.count <= 1 else {
                expectedSession = nil
                guidedSigningSession = nil
                guidedSigningTargets = []
                guidedSigningRecoveryBlocked = true
                guidedSigningVerification = [:]
                guidedSigningTrustStore = nil
                guidedSigningError = L10n.text("More than one signing session matches this document revision. Reload it or create a new revision before continuing.")
                return
            }

            if exactSessions.count == 1, let stored = exactSessions.first {
                guard stored.declaration == declaration else {
                    if let recovery = await trustedGuidedSigningRecoverySource(
                        document: document, sessions: exactSessions
                    ) {
                        expectedSession = recovery.session
                        guidedSigningSession = recovery.session
                        externalConflict = true
                        saveStatus = "External conflict · signing review protected"
                        guidedSigningTrustStore = try await guidedSigningCredentialStore.trustStore()
                        guard isCurrentPreparation() else { return }
                        guidedSigningTargets = []
                        guidedSigningVerification = [:]
                        guidedSigningError = guidedSigningRecoveryAvailableMessage()
                    } else {
                        expectedSession = nil
                        guidedSigningSession = nil
                        guidedSigningTargets = []
                        guidedSigningRecoveryBlocked = true
                        guidedSigningVerification = [:]
                        guidedSigningTrustStore = nil
                        guidedSigningError = guidedSigningRecoveryBlockedMessage()
                    }
                    return
                }
                // The sidecar is authoritative. This also adopts progress
                // committed by another app instance instead of retaining a
                // stale in-memory copy after a reload.
                expectedSession = stored
                guidedSigningSession = stored
            } else if !storedForLocation.isEmpty {
                // A sidecar for another document revision is audit history,
                // not a candidate for the current mutable source. Do not
                // create a second workflow that could later be mistaken for
                // the original one.
                expectedSession = nil
                guidedSigningSession = nil
                guidedSigningTargets = []
                guidedSigningRecoveryBlocked = true
                guidedSigningVerification = [:]
                guidedSigningTrustStore = nil
                guidedSigningError = L10n.text("Protected signing progress belongs to another document revision. Reopen that revision or create an explicit new revision before continuing.")
                return
            } else if guidedSigningSession != nil {
                expectedSession = nil
                guidedSigningSession = nil
                guidedSigningError = L10n.text("Protected signing progress is missing. Reload the document before continuing.")
                return
            } else {
                let created = try LeonardoGuidedSigningSession(
                    document: document, at: Date(), documentLocation: expectedLocation)
                guard isCurrentPreparation() else { return }
                try await guidedSigningStore.saveSession(created, replacing: nil)
                guard isCurrentPreparation() else { return }
                expectedSession = created
                guidedSigningSession = created
            }
            let trustStore = try await guidedSigningCredentialStore.trustStore()
            guard isCurrentPreparation() else { return }
            if let current = guidedSigningSession {
                try LeonardoGuidedSigningSession.validate(declaration: current.declaration, document: document)
                guidedSigningVerification = current.signatureVerification(
                    document: document,
                    resources: try guidedSigningResources(),
                    trustStore: trustStore
                )
            } else {
                guidedSigningVerification = [:]
            }
            guidedSigningTrustStore = trustStore
            refreshGuidedSigningTargets()
        } catch {
            guard isCurrentPreparation() else { return }
            guidedSigningError = String(describing: error)
        }
    }

    /// Loading the protected sidecar is part of document lifecycle, not an
    /// inspector-only side effect. The inspector can therefore be closed while
    /// the tab still remains fail-closed after a reopen or external reload.
    func prepareGuidedSigningIfNeeded() async {
        guard guidedSigningLocation != nil else { return }
        if !isGuidedSigningDocument {
            let expectedLocation = guidedSigningLocation
            let expectedContent = content
            do {
                guard let location = guidedSigningLocation,
                      try await guidedSigningStore.hasSession(documentLocation: location) else { return }
                guard guidedSigningLocation == expectedLocation, content == expectedContent else { return }
            } catch {
                guard guidedSigningLocation == expectedLocation, content == expectedContent else { return }
                guidedSigningError = String(describing: error)
                guidedSigningReady = false
                return
            }
        }
        await prepareGuidedSigning()
    }
}
