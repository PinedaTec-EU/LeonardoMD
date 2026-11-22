import AppKit
import CryptoKit
import Darwin
import Foundation
import LeonardoCore
import LeonardoSync
import UniformTypeIdentifiers

extension AppSession {
    var guidedSigningLocation: String? {
        (documentSourceURL ?? documentURL)?.standardizedFileURL.resolvingSymlinksInPath().path
    }

    var isGuidedSigningDocument: Bool {
        if let document = leonardoDocument,
           document.metadata.formatVersion >= LeonardoFormat.signingVersion,
           document.metadata.document.signing != nil {
            return true
        }
        // Keep a bound sidecar visible if the mutable header was removed or
        // changed. This fail-closed path lets the user create a fresh revision
        // instead of silently starting a second unsigned workflow.
        return guidedSigningSession?.documentLocation == guidedSigningLocation
            || guidedSigningRecoveryBlocked
    }

    /// A correction is available only when the old protected record contains
    /// a trusted sealed snapshot. Ambiguous or unsealed history must remain a
    /// restoration-only state; presenting a button that cannot safely act is
    /// worse than hiding the action.
    var guidedSigningCanStartRevision: Bool {
        guard !guidedSigningRecoveryBlocked,
              let current = guidedSigningSession,
              current.documentLocation == guidedSigningLocation else { return false }
        return current.snapshot != nil
    }

    /// The toolbar can be rendered before the protected sidecar has finished
    /// loading. Derive the pending state from the v2 header in that interval
    /// instead of briefly presenting a completed-signatures label.
    var guidedSigningHasPendingPositions: Bool {
        if let current = guidedSigningSession { return current.canSign }
        guard let document = leonardoDocument,
              document.metadata.formatVersion >= LeonardoFormat.signingVersion,
              let declaration = document.metadata.document.signing else { return false }
        return !declaration.positions.isEmpty
    }

    /// Signing itself additionally needs a loaded trust registry and a clean,
    /// active session. The toolbar still opens the inspector for blocked
    /// states so the user can see the status and correction action.
    var guidedSigningWorkflowOperable: Bool {
        guidedSigningHasPendingPositions
            && guidedSigningReady
            && !guidedSigningLoading
            && guidedSigningError == nil
            && !externalConflict
            && guidedSigningTrustStore != nil
            && guidedSigningSession?.state == .active
    }

    /// External reload/synchronization must not replace a sealed document in
    /// memory. A correction has to go through the explicit new-revision path,
    /// so callers keep the last trusted bytes and surface a conflict instead.
    @discardableResult
    func rejectGuidedSigningContentChange(_ replacement: String) -> Bool {
        guard replacement != content, guidedSigningContentLocked else { return false }
        externalConflict = true
        if guidedSigningSession?.snapshot != nil {
            guidedSigningSnapshotChanged = true
            guidedSigningVerification = [:]
        }
        saveStatus = "External conflict · signing review protected"
        guidedSigningError = L10n.text(
            "The signed document changed outside this review. Create a new revision before continuing."
        )
        return true
    }

    func refreshGuidedSigningTrust() async throws {
        guidedSigningTrustStore = try await guidedSigningCredentialStore.trustStore()
    }

    /// Refreshes the target list for the requested signer position. The
    /// inspector owns selection, so it must not depend on the session's last
    /// Core `currentPositionID` when a different signer is selected.
    func refreshGuidedSigningTargets(for positionID: String? = nil) {
        guard let current = guidedSigningSession,
              let positionID = positionID ?? current.currentPositionID,
              let progress = current.positions[positionID],
              progress.state == .reviewing || progress.state == .readyToSign,
              let document = leonardoDocument else {
            guidedSigningTargets = []
            return
        }
        guidedSigningTargets = (try? current.targets(for: positionID, document: document)) ?? []
    }

    func guidedSigningContext(for target: LeonardoSigningLocationTarget) -> String {
        guard let document = leonardoDocument else { return "" }
        let body = document.body
        guard let index = body.index(body.startIndex, offsetBy: target.sourceOffset,
                                     limitedBy: body.endIndex) else { return "" }
        let start = body.index(index, offsetBy: -120, limitedBy: body.startIndex) ?? body.startIndex
        let end = body.index(index, offsetBy: 160, limitedBy: body.endIndex) ?? body.endIndex
        return body[start..<end].trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func reportGuidedSigningActionFailure(_ error: Error) {
        switch error as? LeonardoSigningError {
        case .profileReused:
            guidedSigningActionProblem = L10n.text("Choose a different profile for this signer.")
        case .identityDocumentReused:
            guidedSigningActionProblem = L10n.text("This identity document is already assigned to another signer.")
        case .credentialReused:
            guidedSigningActionProblem = L10n.text("Choose a different personal credential for this signer.")
        case .invalidIdentity, .invalidProfile:
            guidedSigningActionProblem = L10n.text("Check the signer’s full name and identity document.")
        case .invalidCredential:
            guidedSigningActionProblem = L10n.text("The credential could not be unlocked. Check the password and try again.")
        case .unmappedSigningLocation:
            guidedSigningActionProblem = L10n.text("A rubric in the document does not match an exact location in the source. Check how the rubric field is written.")
        case .remoteImagesNotSealable:
            guidedSigningActionProblem = L10n.text("Replace online images with local files before signing.")
        case .requiredDataMissing(let fieldIDs):
            let names = fieldIDs.map { leonardoDocument?.metadata.fields[$0]?.label ?? $0 }
            guidedSigningActionProblem = L10n.format("Complete the required fields before signing: %@.", names.joined(separator: ", "))
        case .requiredDataInvalid(let fieldIDs):
            let names = fieldIDs.map { leonardoDocument?.metadata.fields[$0]?.label ?? $0 }
            guidedSigningActionProblem = L10n.format("Correct the required fields before signing: %@.", names.joined(separator: ", "))
        default:
            guidedSigningError = error.localizedDescription
        }
    }

    func currentDocument() throws -> LeonardoDocument {
        guard let document = leonardoDocument else { throw LeonardoSigningError.integrityFailure }
        return document
    }

    func loadGuidedSigningPersistenceBaseline(
        for current: LeonardoGuidedSigningSession,
        expectedLocation: String,
        expectedContent: String
    ) async throws -> LeonardoGuidedSigningSession? {
        let baseline = try await guidedSigningStore.session(id: current.id)
        guard guidedSigningViewStateMatches(
            expectedLocation: expectedLocation,
            expectedContent: expectedContent,
            expectedSession: current
        ) else { throw LeonardoSigningError.integrityFailure }
        if let baseline {
            guard baseline.documentLocation == expectedLocation,
                  baseline == current else {
                throw LeonardoSigningError.staleStorage
            }
        }
        return baseline
    }

    func persistInvalidatedGuidedSigningSessionIfNeeded(
        _ current: LeonardoGuidedSigningSession,
        replacing baseline: LeonardoGuidedSigningSession?,
        expectedSession: LeonardoGuidedSigningSession
    ) async {
        let expectedLocation = guidedSigningLocation
        let expectedContent = content
        guard current.state == .invalidated,
              let expectedLocation,
              guidedSigningViewStateMatches(
                  expectedLocation: expectedLocation,
                  expectedContent: expectedContent,
                  expectedSession: expectedSession
              ) else { return }
        do {
            try await guidedSigningStore.saveSession(current, replacing: baseline)
            guard guidedSigningLocation == expectedLocation,
                  content == expectedContent,
                  guidedSigningSession == expectedSession else { return }
            guidedSigningSession = current
        } catch {
            // The previous CAS-confirmed state remains visible and the UI
            // stays blocked by the current integrity error.
        }
    }

    enum GuidedSigningSavedSourceCheck {
        case ready
        case needsSave
        case externalChange
        case stateChanged
    }

    func guidedSigningExchangeSourceIsSaved(
        location: String,
        content: String,
        session: LeonardoGuidedSigningSession,
        snapshot: DocumentSnapshot?
    ) async -> Bool {
        guidedSigningActionProblem = nil
        guard guidedSigningConflictAllowsProgress() else { return false }
        switch await guidedSigningSavedSourceCheck(
            expectedLocation: location,
            expectedContent: content,
            expectedSession: session,
            expectedSnapshot: snapshot
        ) {
        case .ready:
            return guidedSigningConflictAllowsProgress()
        case .needsSave:
            guidedSigningActionProblem = L10n.text("Save the document before exchanging a signing copy.")
        case .externalChange:
            externalConflict = true
            saveStatus = "External conflict · signing review protected"
            _ = guidedSigningConflictAllowsProgress()
        case .stateChanged:
            guidedSigningActionProblem = L10n.text("The document moved or changed while exchanging a signing copy. Reload it before continuing.")
        }
        return false
    }

    /// Verifies the coordinated source before the first seal or an exchange.
    /// A clean buffer is not enough: the saved bytes, document identity,
    /// and package container (when applicable) must still be the same source
    /// represented by the open session.
    func guidedSigningSavedSourceCheck(
        expectedLocation: String,
        expectedContent: String,
        expectedSession: LeonardoGuidedSigningSession,
        expectedSnapshot: DocumentSnapshot?
    ) async -> GuidedSigningSavedSourceCheck {
        guard !stopped, !isClosing, guidedSigningViewStateMatches(
            expectedLocation: expectedLocation,
            expectedContent: expectedContent,
            expectedSession: expectedSession
        ) else { return .stateChanged }
        guard let expectedSnapshot,
              let currentSnapshot = snapshot,
              currentSnapshot == expectedSnapshot,
              !isDirty else { return .needsSave }
        if packageWorkspace?.hasSourceChanged() == true { return .externalChange }
        guard let authoritative = try? await documents.read(expectedSnapshot.url) else {
            return .externalChange
        }
        guard !stopped, !isClosing, snapshot == expectedSnapshot, guidedSigningViewStateMatches(
            expectedLocation: expectedLocation,
            expectedContent: expectedContent,
            expectedSession: expectedSession
        ) else { return .stateChanged }
        guard let savedDocument = try? LeonardoFormatParser.parse(authoritative.content),
              savedDocument.metadata.formatVersion >= LeonardoFormat.signingVersion,
              savedDocument.metadata.document.id == expectedSession.documentID,
              savedDocument.metadata.document.revision == expectedSession.initialRevision,
              savedDocument.metadata.document.signing == expectedSession.declaration,
              authoritative.content == expectedContent,
              authoritative.fingerprint == expectedSnapshot.fingerprint,
              packageWorkspace?.hasSourceChanged() != true else {
            return .externalChange
        }
        return .ready
    }

    struct GuidedSigningRevisionSource {
        let document: LeonardoDocument
        let resources: [LeonardoSigningResource]
        let recovered: Bool
    }

    /// Builds a correction from the current bytes only when they still match
    /// the sealed snapshot. A changed/removed header, body, or local resource
    /// instead uses the verified trusted source and leaves the current path in
    /// external conflict so Save Copy is required before any new proof.
    func guidedSigningRevisionSource(
        for previous: LeonardoGuidedSigningSession,
        current: LeonardoDocument
    ) async throws -> GuidedSigningRevisionSource {
        guard let snapshot = previous.snapshot else {
            guard current.metadata.formatVersion >= LeonardoFormat.signingVersion,
                  current.metadata.document.id == previous.documentID,
                  current.metadata.document.revision == previous.initialRevision,
                  current.metadata.document.signing == previous.declaration else {
                throw LeonardoSigningError.integrityFailure
            }
            return GuidedSigningRevisionSource(
                document: current,
                resources: try guidedSigningResources(),
                recovered: false
            )
        }
        if current.metadata.formatVersion >= LeonardoFormat.signingVersion,
           current.metadata.document.id == previous.documentID,
           current.metadata.document.revision == previous.initialRevision,
           current.metadata.document.signing == previous.declaration,
           let resources = try? guidedSigningResources(),
           snapshot.matches(document: current, resources: resources) {
            return GuidedSigningRevisionSource(document: current, resources: resources, recovered: false)
        }
        guard let trusted = try? LeonardoFormatParser.parse(snapshot.source),
              trusted.metadata.formatVersion >= LeonardoFormat.signingVersion,
              trusted.metadata.document.id == previous.documentID,
              trusted.metadata.document.revision == previous.initialRevision,
              trusted.metadata.document.signing == previous.declaration else {
            throw LeonardoSigningError.integrityFailure
        }
        let resources = try guidedSigningResources(for: snapshot.source)
        guard snapshot.matches(document: trusted, resources: resources) else {
            throw LeonardoSigningError.integrityFailure
        }
        if previous.positions.values.contains(where: { $0.signature != nil }) {
            guard let trustStore = try? await guidedSigningCredentialStore.trustStore() else {
                throw LeonardoSigningError.trustStoreRequired
            }
            let verification = previous.signatureVerification(
                document: trusted,
                resources: resources,
                trustStore: trustStore
            )
            guard !verification.isEmpty,
                  verification.values.allSatisfy({ $0 == .valid }) else {
                throw LeonardoSigningError.integrityFailure
            }
        }
        return GuidedSigningRevisionSource(document: trusted, resources: resources, recovered: true)
    }

    func guidedSigningRevisionViewStateMatches(
        expectedLocation: String,
        expectedContent: String,
        expectedSession: LeonardoGuidedSigningSession
    ) -> Bool {
        guidedSigningLocation == expectedLocation
            && content == expectedContent
            && guidedSigningSession == expectedSession
    }

    func guidedSigningViewStateMatches(
        expectedLocation: String,
        expectedContent: String,
        expectedSession: LeonardoGuidedSigningSession?
    ) -> Bool {
        guard guidedSigningLocation == expectedLocation,
              content == expectedContent,
              guidedSigningSession == expectedSession else { return false }
        guard let expectedSession else { return true }
        guard let document = leonardoDocument,
              document.metadata.document.id == expectedSession.documentID,
              document.metadata.document.signing == expectedSession.declaration,
              document.metadata.document.revision == expectedSession.initialRevision,
              document.metadata.formatVersion >= LeonardoFormat.signingVersion else { return false }
        return true
    }

    func guidedSigningResourceURLs(in document: LeonardoDocument) throws -> [(reference: String, url: URL)] {
        guard let documentURL else { return [] }
        let references = try LeonardoLocalImagePolicy.signingReferences(in: document)
        guard !references.isEmpty else { return [] }
        let base = documentURL.deletingLastPathComponent().standardizedFileURL
        var roots = [base]
        if let packageRoot = packageWorkspace?.directoryURL { roots.append(packageRoot.standardizedFileURL) }
        if let projectURL { roots.append(projectURL.standardizedFileURL) }
        let rootPaths = roots.map { $0.resolvingSymlinksInPath().path }
        return try references.map { reference in
            guard let parsed = URLComponents(string: reference), !parsed.path.isEmpty else {
                throw LeonardoSigningError.invalidResourceReference(reference)
            }
            let candidate: URL
            if parsed.scheme?.lowercased() == "file" {
                guard let url = parsed.url else { throw LeonardoSigningError.invalidResourceReference(reference) }
                candidate = url
            } else if parsed.path.hasPrefix("/") {
                candidate = URL(fileURLWithPath: parsed.path)
            } else {
                candidate = base.appendingPathComponent(parsed.path)
            }
            let resolved = candidate.standardizedFileURL.resolvingSymlinksInPath()
            guard rootPaths.contains(where: { resolved.path == $0 || resolved.path.hasPrefix($0 + "/") }),
                  LeonardoLocalImagePolicy.extensions.contains(resolved.pathExtension.lowercased()) else {
                throw LeonardoSigningError.invalidResourceReference(reference)
            }
            return (reference, resolved)
        }
    }

    func reviewedSigningImagesMatch(
        document: LeonardoDocument,
        files: [(reference: String, url: URL)],
        resources: [LeonardoSigningResource]
    ) async throws -> Bool {
        let embedded = try LeonardoLocalImagePolicy.hasEmbeddedSigningImages(in: document)
        guard !files.isEmpty || embedded else { return true }
        var expected: [URL: Data] = [:]
        for (file, resource) in zip(files, resources) {
            let digest = Data(SHA256.hash(data: resource.bytes))
            if let previous = expected.updateValue(digest, forKey: file.url), previous != digest {
                return false
            }
        }
        return await renderer.hasReviewedSigningImages(expected, includesEmbeddedImages: embedded)
    }

    func guidedSigningResources(for source: String? = nil) throws -> [LeonardoSigningResource] {
        let document = try LeonardoFormatParser.parse(source ?? content)
        return try readGuidedSigningResources(guidedSigningResourceURLs(in: document))
    }

    func readGuidedSigningResources(
        _ files: [(reference: String, url: URL)]
    ) throws -> [LeonardoSigningResource] {
        try files.map { reference, resolved in
            let values = try resolved.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard values.isRegularFile == true,
                  let size = values.fileSize,
                  size <= LeonardoSigningSnapshot.maximumResourceBytes else {
                throw LeonardoSigningError.resourceTooLarge(reference)
            }
            let bytes = try Data(contentsOf: resolved)
            guard bytes.count <= LeonardoSigningSnapshot.maximumResourceBytes else {
                throw LeonardoSigningError.resourceTooLarge(reference)
            }
            return LeonardoSigningResource(reference: reference, bytes: bytes)
        }
    }
}
