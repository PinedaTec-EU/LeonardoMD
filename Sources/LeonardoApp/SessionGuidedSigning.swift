import AppKit
import CryptoKit
import Darwin
import Foundation
import LeonardoCore
import LeonardoSync
import UniformTypeIdentifiers

extension AppSession {
    private var guidedSigningLocation: String? {
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
            && guidedSigningTrustStore != nil
            && guidedSigningSession?.state == .active
    }

    /// The first confirmed location seals data, assignments, header and
    /// resources. A correction is an explicit new revision, never an inline
    /// edit that silently keeps old signatures.
    var guidedSigningContentLocked: Bool {
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
                // revision to select. Keep a single bound record visible only
                // to explain the block; never choose among historical
                // records by updatedAt or path alone.
                if storedForLocation.count == 1, let stored = storedForLocation.first {
                    expectedSession = stored
                    guidedSigningSession = stored
                    guidedSigningError = L10n.text("This file has signing progress, but its signing header changed. Create a new revision before continuing.")
                } else {
                    expectedSession = nil
                    guidedSigningSession = nil
                    guidedSigningTargets = []
                    if !storedForLocation.isEmpty {
                        guidedSigningError = L10n.text("This file has signing history, but its current signing identity is unavailable. Restore the exact signing header before continuing.")
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
                guidedSigningError = L10n.text("The document has no stable signing identity or revision. Create a new revision before continuing.")
                return
            }
            let exactSessions = storedForLocation.filter {
                $0.documentID == documentID && $0.initialRevision == revision
            }
            guard exactSessions.count <= 1 else {
                expectedSession = nil
                guidedSigningSession = nil
                guidedSigningTargets = []
                guidedSigningError = L10n.text("More than one signing session matches this document revision. Reload it or create a new revision before continuing.")
                return
            }

            if exactSessions.count == 1, let stored = exactSessions.first {
                guard stored.declaration == declaration else {
                    expectedSession = stored
                    guidedSigningSession = stored
                    guidedSigningError = L10n.text("The document identity or signer assignments changed. Create a new revision before continuing.")
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

    /// External reload/synchronization must not replace a sealed document in
    /// memory. A correction has to go through the explicit new-revision path,
    /// so callers keep the last trusted bytes and surface a conflict instead.
    @discardableResult
    func rejectGuidedSigningContentChange(_ replacement: String) -> Bool {
        guard replacement != content, guidedSigningContentLocked else { return false }
        externalConflict = true
        saveStatus = "External conflict · signing review protected"
        guidedSigningError = L10n.text(
            "The signed document changed outside this review. Create a new revision before continuing."
        )
        return true
    }

    func refreshGuidedSigningTrust() async throws {
        guidedSigningTrustStore = try await guidedSigningCredentialStore.trustStore()
    }

    /// Exports an explicit offline signing exchange. The source document is
    /// never changed and the package contains only public trust records and
    /// the current sidecar progress; local paths and private keys stay local.
    func exportGuidedSigningExchange() {
        guard let document = leonardoDocument,
              let current = guidedSigningSession,
              let expectedLocation = guidedSigningLocation else { return }
        let expectedContent = content
        do {
            let exchange = try LeonardoSigningExchange(
                document: document,
                resources: try guidedSigningResources(),
                session: current,
                trustedCredentials: guidedSigningTrustStore?.allCredentials ?? [],
                at: Date()
            )
            let data = try LeonardoSigningExchange.encoded(exchange)
            let panel = NSSavePanel()
            panel.title = L10n.text("Export signing copy")
            panel.nameFieldStringValue = documentURL?.deletingPathExtension().lastPathComponent
                .appending("-signing-copy.json") ?? "Leonardo-signing-copy.json"
            panel.allowedContentTypes = [.json]
            presentFilePanel(panel) { [weak self] destination in
                Task {
                    await self?.writeGuidedSigningExchange(
                        data,
                        to: destination,
                        expectedLocation: expectedLocation,
                        expectedContent: expectedContent,
                        sessionID: current.id
                    )
                }
            }
        } catch {
            guidedSigningError = String(describing: error)
        }
    }

    /// Opens a signed-copy exchange and merges it only when the local source,
    /// snapshot, assignments and signature-chain prefix still match. Unknown
    /// public keys are shown with fingerprints and must be checked through a
    /// separate channel before they are stored in the public-only trust area.
    func importGuidedSigningExchange() {
        guard documentURL != nil else { return }
        let panel = NSOpenPanel()
        panel.title = L10n.text("Import signed copy")
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        presentFilePanel(panel) { [weak self] source in
            Task { await self?.readGuidedSigningExchange(from: source) }
        }
    }

    private func writeGuidedSigningExchange(
        _ data: Data,
        to destination: URL,
        expectedLocation: String,
        expectedContent: String,
        sessionID: UUID
    ) async {
        guard data.count <= LeonardoSigningExchange.maximumEnvelopeBytes,
              guidedSigningLocation == expectedLocation,
              content == expectedContent,
              guidedSigningSession?.id == sessionID,
              !stopped else { return }
        do {
            try InstancePathOwnership.shared.claim(destination)
            try Self.writeSigningExchangeAtomically(data, to: destination)
            saveStatus = L10n.text("Signing copy exported")
        } catch {
            guidedSigningError = String(describing: error)
        }
    }

    private func readGuidedSigningExchange(from source: URL) async {
        let expectedLocation = guidedSigningLocation
        let expectedContent = content
        do {
            let values = try source.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard values.isRegularFile == true,
                  let fileSize = values.fileSize,
                  fileSize <= LeonardoSigningExchange.maximumEnvelopeBytes else {
                throw LeonardoSigningError.storageFailure
            }
            let data = try Data(contentsOf: source, options: [.mappedIfSafe])
            guard data.count <= LeonardoSigningExchange.maximumEnvelopeBytes else {
                throw LeonardoSigningError.storageFailure
            }
            let exchange = try LeonardoSigningExchange.decoded(data)
            try await importGuidedSigningExchange(
                exchange,
                expectedLocation: expectedLocation,
                expectedContent: expectedContent
            )
        } catch {
            guidedSigningError = String(describing: error)
        }
    }

    private func importGuidedSigningExchange(
        _ exchange: LeonardoSigningExchange,
        expectedLocation: String?,
        expectedContent: String
    ) async throws {
        let expectedSession = guidedSigningSession
        guard let expectedLocation,
              guidedSigningViewStateMatches(
                  expectedLocation: expectedLocation,
                  expectedContent: expectedContent,
                  expectedSession: expectedSession
              ),
              let document = leonardoDocument else {
            throw LeonardoSigningError.integrityFailure
        }
        let localResources = try guidedSigningResources()
        let localTrust = try await guidedSigningCredentialStore.trustStore()
        guard guidedSigningViewStateMatches(
            expectedLocation: expectedLocation,
            expectedContent: expectedContent,
            expectedSession: expectedSession
        ) else { throw LeonardoSigningError.integrityFailure }
        let unknown = exchange.trustedCredentials.filter { credential in
            localTrust.credential(id: credential.id) != credential
        }
        let effectiveTrust: LeonardoSigningTrustRegistry
        if unknown.isEmpty {
            effectiveTrust = localTrust
        } else {
            guard confirmImportedPublicKeys(unknown) else {
                throw LeonardoSigningError.trustStoreRequired
            }
            guard guidedSigningViewStateMatches(
                expectedLocation: expectedLocation,
                expectedContent: expectedContent,
                expectedSession: expectedSession
            ) else { throw LeonardoSigningError.integrityFailure }
            effectiveTrust = try LeonardoSigningTrustRegistry(
                credentials: localTrust.allCredentials + unknown
            )
        }
        try exchange.validate(against: document, resources: localResources, trustStore: effectiveTrust)
        let localSessions = try await guidedSigningStore.sessions()
            .filter { $0.documentLocation == expectedLocation }
        guard guidedSigningViewStateMatches(
            expectedLocation: expectedLocation,
            expectedContent: expectedContent,
            expectedSession: expectedSession
        ) else { throw LeonardoSigningError.integrityFailure }
        // A deliberate correction preserves the old sidecar session at this
        // path. Only sessions for this exact document identity and semantic
        // revision can participate in the import CAS; older revisions remain
        // audit history and must not block a valid current copy.
        let currentRevisionSessions = localSessions.filter {
            $0.documentID == exchange.documentID
                && $0.initialRevision == exchange.documentRevision
        }
        guard currentRevisionSessions.count <= 1 else {
            // Multiple sessions for one exact revision are a fork, even if
            // one happens to be pristine. Never choose between them.
            throw LeonardoSigningError.staleStorage
        }
        let local = currentRevisionSessions.first { $0.id == exchange.session.id }
        let pristineReplacement = local == nil && currentRevisionSessions.count == 1
            ? currentRevisionSessions.first(where: { $0.isPristine })
            : nil
        guard local != nil || currentRevisionSessions.isEmpty || pristineReplacement != nil else {
            // A different local session means this file already has progress
            // from another signing copy for this revision. Never overwrite or
            // merge that fork, while historical revisions remain untouched.
            throw LeonardoSigningError.staleStorage
        }
        guard localSessions.isEmpty || !currentRevisionSessions.isEmpty else {
            // There is local signing history, but no sidecar for this exact
            // source revision. Do not make import the back door around the
            // same exact path/ID/revision binding used by preparation.
            throw LeonardoSigningError.staleStorage
        }
        let localBaseline = local ?? pristineReplacement
        guard expectedSession == localBaseline else {
            throw LeonardoSigningError.integrityFailure
        }
        let rebound = try exchange.reboundSession(
            onto: local,
            documentLocation: expectedLocation
        )
        // Persist accepted public records only after the detached proof has
        // passed validation. These records never contain private key bytes.
        for credential in unknown {
            guard guidedSigningViewStateMatches(
                expectedLocation: expectedLocation,
                expectedContent: expectedContent,
                expectedSession: expectedSession
            ) else { throw LeonardoSigningError.integrityFailure }
            try await guidedSigningCredentialStore.trustPublicCredential(credential)
        }
        guard guidedSigningViewStateMatches(
            expectedLocation: expectedLocation,
            expectedContent: expectedContent,
            expectedSession: expectedSession
        ) else { throw LeonardoSigningError.integrityFailure }
        if let pristineReplacement {
            try await guidedSigningStore.replacePristineSession(
                id: pristineReplacement.id,
                baseline: pristineReplacement,
                with: rebound
            )
        } else {
            try await guidedSigningStore.saveSession(rebound, replacing: local)
        }
        guard guidedSigningViewStateMatches(
            expectedLocation: expectedLocation,
            expectedContent: expectedContent,
            expectedSession: expectedSession
        ) else { throw LeonardoSigningError.integrityFailure }
        guidedSigningSession = rebound
        let committedTrust = try await guidedSigningCredentialStore.trustStore()
        guard guidedSigningLocation == expectedLocation, content == expectedContent,
              guidedSigningSession == rebound else {
            throw LeonardoSigningError.integrityFailure
        }
        guidedSigningTrustStore = committedTrust
        guidedSigningVerification = rebound.signatureVerification(
            document: document,
            resources: localResources,
            trustStore: committedTrust
        )
        refreshGuidedSigningTargets()
        guidedSigningError = nil
        guidedSigningStatus = L10n.text("Signed copy imported after local integrity and trust checks.")
    }

    @MainActor
    private func confirmImportedPublicKeys(_ credentials: [LeonardoSigningCredential]) -> Bool {
        let fields = credentials.map { credential -> (LeonardoSigningCredential, NSTextField) in
            let field = NSTextField(string: "")
            field.placeholderString = L10n.text("Enter fingerprint received separately")
            field.translatesAutoresizingMaskIntoConstraints = false
            return (credential, field)
        }
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        for (credential, field) in fields {
            let label = NSTextField(labelWithString: "\(credential.id)\n\(Self.publicFingerprint(credential))")
            label.font = .monospacedSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
            stack.addArrangedSubview(label)
            stack.addArrangedSubview(field)
        }
        stack.frame = NSRect(x: 0, y: 0, width: 430, height: CGFloat(fields.count * 78))
        let alert = NSAlert()
        alert.messageText = L10n.text("Verify public signing keys")
        alert.informativeText = L10n.text("Compare every fingerprint through a separate trusted channel. The exchange file is not itself a trust anchor.")
        alert.accessoryView = stack
        alert.addButton(withTitle: L10n.text("Trust and import"))
        alert.addButton(withTitle: L10n.text("Cancel"))
        guard alert.runModal() == .alertFirstButtonReturn else { return false }
        return fields.allSatisfy { credential, field in
            Self.normalizedFingerprint(field.stringValue) == Self.normalizedFingerprint(Self.publicFingerprint(credential))
        }
    }

    private static func publicFingerprint(_ credential: LeonardoSigningCredential) -> String {
        SHA256.hash(data: credential.publicKey).map { String(format: "%02x", $0) }
            .joined(separator: ":")
    }

    private static func normalizedFingerprint(_ value: String) -> String {
        value.filter(\.isHexDigit).lowercased()
    }

    private static func writeSigningExchangeAtomically(_ data: Data, to destination: URL) throws {
        let directory = destination.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let temporary = directory.appendingPathComponent(".\(destination.lastPathComponent).\(UUID().uuidString).tmp")
        defer { try? FileManager.default.removeItem(at: temporary) }
        guard FileManager.default.createFile(
            atPath: temporary.path,
            contents: nil,
            attributes: [.posixPermissions: NSNumber(value: Int16(0o600))]
        ) else { throw LeonardoSigningError.storageFailure }
        do {
            let handle = try FileHandle(forWritingTo: temporary)
            try handle.write(contentsOf: data)
            try handle.synchronize()
            try handle.close()
            guard Darwin.rename(temporary.path, destination.path) == 0 else {
                throw LeonardoSigningError.storageFailure
            }
        } catch let error as LeonardoSigningError {
            throw error
        } catch {
            throw LeonardoSigningError.storageFailure
        }
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

    private func reportGuidedSigningActionFailure(_ error: Error) {
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

    func assignGuidedSigner(
        positionID: String,
        profile: LeonardoSignerProfile,
        credential: LeonardoSigningCredential,
        saveOptions: LeonardoProfileSaveOptions
    ) async {
        guard let current = guidedSigningSession, let expectedLocation = guidedSigningLocation else { return }
        let expectedContent = content
        guidedSigningActionProblem = nil
        var baseline: LeonardoGuidedSigningSession?
        do {
            baseline = try await loadGuidedSigningPersistenceBaseline(
                for: current,
                expectedLocation: expectedLocation,
                expectedContent: expectedContent
            )
            guard guidedSigningViewStateMatches(
                expectedLocation: expectedLocation,
                expectedContent: expectedContent,
                expectedSession: current
            ) else {
                throw LeonardoSigningError.integrityFailure
            }
            let authorization = try LeonardoSigningAuthorization(
                positionID: positionID,
                profileID: profile.id,
                credentialID: credential.id,
                confirmedAt: Date(),
                explicitlyConfirmed: true
            )
            var updated = current
            try updated.assign(positionID: positionID, profile: profile, credential: credential,
                               authorization: authorization, at: Date())
            if saveOptions.saveIdentityDetails || saveOptions.saveRubric {
                try await guidedSigningStore.saveProfile(profile, options: saveOptions)
                guard guidedSigningViewStateMatches(
                    expectedLocation: expectedLocation,
                    expectedContent: expectedContent,
                    expectedSession: current
                ) else { throw LeonardoSigningError.integrityFailure }
                guidedSigningProfiles = try await guidedSigningStore.profiles()
            }
            guard guidedSigningViewStateMatches(
                expectedLocation: expectedLocation,
                expectedContent: expectedContent,
                expectedSession: current
            ) else {
                throw LeonardoSigningError.integrityFailure
            }
            try await guidedSigningStore.saveSession(updated, replacing: baseline)
            guard guidedSigningViewStateMatches(
                expectedLocation: expectedLocation,
                expectedContent: expectedContent,
                expectedSession: current
            ) else {
                guidedSigningError = L10n.text("The document moved or changed while assigning this signer. Reload it before continuing.")
                return
            }
            guidedSigningSession = updated
            guidedSigningStatus = L10n.text("Signer assigned. Review the exact field occurrences before confirming.")
            guidedSigningError = nil
        } catch {
            reportGuidedSigningActionFailure(error)
        }
    }

    func beginGuidedPosition(_ positionID: String) async {
        guard var current = guidedSigningSession, let document = leonardoDocument,
              let expectedLocation = guidedSigningLocation else { return }
        let viewBaseline = current
        let expectedContent = content
        var baseline: LeonardoGuidedSigningSession?
        var baselineLoaded = false
        do {
            baseline = try await loadGuidedSigningPersistenceBaseline(
                for: current,
                expectedLocation: expectedLocation,
                expectedContent: expectedContent
            )
            baselineLoaded = true
            let targets = try current.begin(positionID: positionID, document: document,
                                            resources: try guidedSigningResources())
            guard guidedSigningViewStateMatches(
                expectedLocation: expectedLocation,
                expectedContent: expectedContent,
                expectedSession: viewBaseline
            ) else {
                throw LeonardoSigningError.integrityFailure
            }
            try await guidedSigningStore.saveSession(current, replacing: baseline)
            guard guidedSigningViewStateMatches(
                expectedLocation: expectedLocation,
                expectedContent: expectedContent,
                expectedSession: viewBaseline
            ) else {
                guidedSigningError = L10n.text("The document moved or changed while beginning the review. Reload it before continuing.")
                return
            }
            guidedSigningSession = current
            guidedSigningTargets = targets
            guidedSigningStatus = L10n.text("Read each exact occurrence, then confirm it.")
            guidedSigningError = nil
        } catch {
            if baselineLoaded {
                await persistInvalidatedGuidedSigningSessionIfNeeded(
                    current, replacing: baseline, expectedSession: viewBaseline
                )
            }
            reportGuidedSigningActionFailure(error)
        }
    }

    func confirmGuidedLocation(
        target: LeonardoSigningLocationTarget,
        rubric: LeonardoRubric,
        reuse: LeonardoRubricReuse,
        reuseConfirmed: Bool,
        contextRead: Bool
    ) async {
        guard var current = guidedSigningSession, let document = leonardoDocument,
              let expectedLocation = guidedSigningLocation else { return }
        let viewBaseline = current
        let expectedContent = content
        var baseline: LeonardoGuidedSigningSession?
        var baselineLoaded = false
        guidedSigningActionProblem = nil
        do {
            baseline = try await loadGuidedSigningPersistenceBaseline(
                for: current,
                expectedLocation: expectedLocation,
                expectedContent: expectedContent
            )
            baselineLoaded = true
            let profileRubric = current.positions[target.positionID]?.assignment?.profileRubric
            try current.confirmLocation(
                positionID: target.positionID,
                fieldID: target.fieldID,
                occurrence: target.occurrence,
                document: document,
                resources: try guidedSigningResources(),
                contextRead: contextRead,
                rubric: rubric,
                reuse: reuse,
                profileRubric: profileRubric,
                reuseConfirmed: reuseConfirmed,
                at: Date()
            )
            guard guidedSigningViewStateMatches(
                expectedLocation: expectedLocation,
                expectedContent: expectedContent,
                expectedSession: viewBaseline
            ) else {
                throw LeonardoSigningError.integrityFailure
            }
            try await guidedSigningStore.saveSession(current, replacing: baseline)
            guard guidedSigningViewStateMatches(
                expectedLocation: expectedLocation,
                expectedContent: expectedContent,
                expectedSession: viewBaseline
            ) else {
                guidedSigningError = L10n.text("The document moved or changed while confirming this location. Reload it before continuing.")
                return
            }
            guidedSigningSession = current
            refreshGuidedSigningTargets()
            guidedSigningStatus = L10n.text("Location confirmed. Continue in source order.")
            guidedSigningError = nil
        } catch {
            if baselineLoaded {
                await persistInvalidatedGuidedSigningSessionIfNeeded(
                    current, replacing: baseline, expectedSession: viewBaseline
                )
            }
            reportGuidedSigningActionFailure(error)
        }
    }

    func pauseGuidedPosition(positionID: String) async {
        guard var current = guidedSigningSession,
              let expectedLocation = guidedSigningLocation else { return }
        let viewBaseline = current
        let expectedContent = content
        var baseline: LeonardoGuidedSigningSession?
        var baselineLoaded = false
        do {
            baseline = try await loadGuidedSigningPersistenceBaseline(
                for: current,
                expectedLocation: expectedLocation,
                expectedContent: expectedContent
            )
            baselineLoaded = true
            try current.pause(positionID: positionID, at: Date())
            guard guidedSigningViewStateMatches(
                expectedLocation: expectedLocation,
                expectedContent: expectedContent,
                expectedSession: viewBaseline
            ) else {
                throw LeonardoSigningError.integrityFailure
            }
            try await guidedSigningStore.saveSession(current, replacing: baseline)
            guard guidedSigningViewStateMatches(
                expectedLocation: expectedLocation,
                expectedContent: expectedContent,
                expectedSession: viewBaseline
            ) else {
                guidedSigningError = L10n.text("The document moved or changed while pausing. Reload it before continuing.")
                return
            }
            guidedSigningSession = current
            guidedSigningTargets = []
            guidedSigningStatus = L10n.text("Signing paused. The sealed review can be resumed later.")
            guidedSigningError = nil
        } catch {
            if baselineLoaded {
                await persistInvalidatedGuidedSigningSessionIfNeeded(
                    current, replacing: baseline, expectedSession: viewBaseline
                )
            }
            guidedSigningError = String(describing: error)
        }
    }

    func resumeGuidedPosition(positionID: String) async {
        guard var current = guidedSigningSession,
              let expectedLocation = guidedSigningLocation else { return }
        let viewBaseline = current
        let expectedContent = content
        var baseline: LeonardoGuidedSigningSession?
        var baselineLoaded = false
        do {
            baseline = try await loadGuidedSigningPersistenceBaseline(
                for: current,
                expectedLocation: expectedLocation,
                expectedContent: expectedContent
            )
            baselineLoaded = true
            try current.resume(positionID: positionID, at: Date())
            let targets = try current.begin(positionID: positionID, document: try currentDocument(),
                                            resources: try guidedSigningResources())
            guard guidedSigningViewStateMatches(
                expectedLocation: expectedLocation,
                expectedContent: expectedContent,
                expectedSession: viewBaseline
            ) else {
                throw LeonardoSigningError.integrityFailure
            }
            try await guidedSigningStore.saveSession(current, replacing: baseline)
            guard guidedSigningViewStateMatches(
                expectedLocation: expectedLocation,
                expectedContent: expectedContent,
                expectedSession: viewBaseline
            ) else {
                guidedSigningError = L10n.text("The document moved or changed while resuming. Reload it before continuing.")
                return
            }
            guidedSigningSession = current
            guidedSigningTargets = targets
            guidedSigningStatus = L10n.text("Signing resumed. Continue with the next exact occurrence.")
            guidedSigningError = nil
        } catch {
            if baselineLoaded {
                await persistInvalidatedGuidedSigningSessionIfNeeded(
                    current, replacing: baseline, expectedSession: viewBaseline
                )
            }
            guidedSigningError = String(describing: error)
        }
    }

    func signGuidedPosition(positionID: String, password: String) async {
        guard var current = guidedSigningSession,
              let assignment = current.positions[positionID]?.assignment,
              let document = leonardoDocument,
              let expectedLocation = guidedSigningLocation else { return }
        let viewBaseline = current
        let expectedContent = content
        guidedSigningActionProblem = nil
        var baseline: LeonardoGuidedSigningSession?
        var baselineLoaded = false
        do {
            baseline = try await loadGuidedSigningPersistenceBaseline(
                for: current,
                expectedLocation: expectedLocation,
                expectedContent: expectedContent
            )
            baselineLoaded = true
            let keyPair = try await guidedSigningCredentialStore.keyPair(
                credentialID: assignment.credentialID, password: password)
            guard guidedSigningViewStateMatches(
                expectedLocation: expectedLocation,
                expectedContent: expectedContent,
                expectedSession: viewBaseline
            ) else { throw LeonardoSigningError.integrityFailure }
            let trustStore = try await guidedSigningCredentialStore.trustStore()
            guard guidedSigningViewStateMatches(
                expectedLocation: expectedLocation,
                expectedContent: expectedContent,
                expectedSession: viewBaseline
            ) else { throw LeonardoSigningError.integrityFailure }
            _ = try current.sign(positionID: positionID, keyPair: keyPair, document: document,
                                  resources: try guidedSigningResources(), trustStore: trustStore, at: Date())
            guard guidedSigningViewStateMatches(
                expectedLocation: expectedLocation,
                expectedContent: expectedContent,
                expectedSession: viewBaseline
            ) else {
                throw LeonardoSigningError.integrityFailure
            }
            try await guidedSigningStore.saveSession(current, replacing: baseline)
            guard guidedSigningViewStateMatches(
                expectedLocation: expectedLocation,
                expectedContent: expectedContent,
                expectedSession: viewBaseline
            ) else {
                guidedSigningError = L10n.text("The document moved or changed while signing. Reload it before continuing.")
                return
            }
            guidedSigningSession = current
            guidedSigningTrustStore = trustStore
            guidedSigningVerification = current.signatureVerification(document: document,
                                                                       resources: try guidedSigningResources(),
                                                                       trustStore: trustStore)
            guidedSigningTargets = []
            guidedSigningStatus = current.state == .complete
                ? L10n.text("All signer positions are signed and verified locally.")
                : L10n.text("Signature stored. The next pending signer may continue.")
            guidedSigningError = nil
        } catch {
            if baselineLoaded {
                await persistInvalidatedGuidedSigningSessionIfNeeded(
                    current, replacing: baseline, expectedSession: viewBaseline
                )
            }
            reportGuidedSigningActionFailure(error)
        }
    }

    /// Corrections are explicit and advance the semantic revision. The old
    /// sidecar session remains an audit record; the fresh one starts empty.
    func startGuidedSigningRevision() async {
        guard let previous = guidedSigningSession, let document = leonardoDocument,
              let expectedLocation = guidedSigningLocation else { return }
        let expectedContent = content
        var revised = document
        revised.metadata.document.revision = (revised.metadata.document.revision ?? 0) + 1
        do {
            let replacement = try LeonardoFormatParser.serialize(revised)
            guidedSigningRevisionEditing = true
            guard editDocument(expected: expectedContent, replacement: replacement) else {
                guidedSigningRevisionEditing = false
                guidedSigningError = L10n.text("The new revision could not be opened for editing.")
                return
            }
            guard guidedSigningLocation == expectedLocation,
                  content == replacement,
                  guidedSigningSession == previous else {
                guidedSigningRevisionEditing = false
                guidedSigningError = L10n.text("The document moved or changed while creating the new revision. Reload it before continuing.")
                return
            }
            let fresh = try previous.correctedSession(document: revised,
                                                       resources: try guidedSigningResources(), at: Date(),
                                                       documentLocation: expectedLocation)
            guidedSigningRevisionEditing = false
            guard guidedSigningLocation == expectedLocation,
                  content == replacement,
                  guidedSigningSession == previous else {
                guidedSigningError = L10n.text("The document moved or changed while creating the new revision. Reload it before continuing.")
                return
            }
            // The correction is a new sidecar revision. Preserve the old
            // session as audit history and require the new ID to be absent.
            try await guidedSigningStore.saveSession(fresh, replacing: nil)
            guard guidedSigningLocation == expectedLocation,
                  content == replacement,
                  guidedSigningSession == previous else {
                guidedSigningError = L10n.text("The document moved while saving the new revision. Reload it before continuing.")
                return
            }
            guidedSigningSession = fresh
            refreshGuidedSigningTargets()
            guidedSigningStatus = L10n.text("New revision ready. Review and assign every signer again.")
            guidedSigningError = nil
        } catch {
            guidedSigningRevisionEditing = false
            guidedSigningError = String(describing: error)
        }
    }

    private func currentDocument() throws -> LeonardoDocument {
        guard let document = leonardoDocument else { throw LeonardoSigningError.integrityFailure }
        return document
    }

    private func loadGuidedSigningPersistenceBaseline(
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

    private func persistInvalidatedGuidedSigningSessionIfNeeded(
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

    private func guidedSigningViewStateMatches(
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

    private func guidedSigningResources() throws -> [LeonardoSigningResource] {
        guard let documentURL else { return [] }
        let references = LeonardoLocalImagePolicy.localReferences(in: content)
        guard !references.isEmpty else { return [] }
        let base = documentURL.deletingLastPathComponent().standardizedFileURL
        var roots = [base]
        if let packageRoot = packageWorkspace?.directoryURL { roots.append(packageRoot.standardizedFileURL) }
        if let projectURL { roots.append(projectURL.standardizedFileURL) }
        let rootPaths = roots.map { $0.resolvingSymlinksInPath().path }
        return try references.map { reference in
            let decoded = reference.removingPercentEncoding ?? reference
            let rawURL = URL(string: reference)
            let candidate: URL
            if rawURL?.scheme?.lowercased() == "file", let rawURL {
                candidate = rawURL
            } else if decoded.hasPrefix("/") {
                candidate = URL(fileURLWithPath: decoded)
            } else {
                candidate = base.appendingPathComponent(decoded)
            }
            let resolved = candidate.standardizedFileURL.resolvingSymlinksInPath()
            guard rootPaths.contains(where: { resolved.path == $0 || resolved.path.hasPrefix($0 + "/") }),
                  LeonardoLocalImagePolicy.extensions.contains(resolved.pathExtension.lowercased()) else {
                throw LeonardoSigningError.invalidResourceReference(reference)
            }
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
