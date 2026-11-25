import AppKit
import CryptoKit
import Darwin
import Foundation
import LeonardoCore
import LeonardoSync
import UniformTypeIdentifiers

extension AppSession {
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
            if credential.certificateChain != nil {
                try await guidedSigningCredentialStore.trustPublicCredential(credential)
                guidedSigningTrustStore = try await guidedSigningCredentialStore.trustStore()
                guard guidedSigningViewStateMatches(expectedLocation: expectedLocation,
                                                     expectedContent: expectedContent,
                                                     expectedSession: current) else {
                    throw LeonardoSigningError.integrityFailure
                }
            }
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
              let expectedLocation = guidedSigningLocation,
              guidedSigningConflictAllowsProgress() else { return }
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
            guard guidedSigningConflictAllowsProgress() else { return }
            let targets = try current.begin(positionID: positionID, document: document,
                                            resources: try guidedSigningResources())
            guard guidedSigningViewStateMatches(
                expectedLocation: expectedLocation,
                expectedContent: expectedContent,
                expectedSession: viewBaseline
            ) else {
                throw LeonardoSigningError.integrityFailure
            }
            guard guidedSigningConflictAllowsProgress() else { return }
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
            guidedSigningActionProblem = nil
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
        contextRead: Bool,
        renderedPlanMatches: ([String: Int], String) async -> Bool
    ) async {
        guard let initialSession = guidedSigningSession,
              let expectedLocation = guidedSigningLocation,
              guidedSigningConflictAllowsProgress() else { return }
        let initialSeal = initialSession.snapshot == nil
        if initialSeal {
            // The renderer owns native form edits while Preview is active.
            // Flush them before taking the source identity used by the first
            // proof; otherwise a later discard could reopen older bytes.
            guard await flushPreviewEdits() else {
                guidedSigningActionProblem = L10n.text("Could not apply preview edits")
                return
            }
            guard guidedSigningLocation == expectedLocation,
                  guidedSigningSession == initialSession else {
                guidedSigningError = L10n.text("The document moved or changed while confirming this location. Reload it before continuing.")
                return
            }
        }
        guard var current = guidedSigningSession,
              let document = leonardoDocument else { return }
        let viewBaseline = current
        let expectedContent = content
        let expectedSnapshot = snapshot
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
            guard guidedSigningConflictAllowsProgress() else { return }
            if initialSeal {
                guard await guidedSigningSourceCanCommit(location: expectedLocation, content: expectedContent,
                                                          session: viewBaseline, snapshot: expectedSnapshot) else { return }
            }
            let imageFiles = try guidedSigningResourceURLs(in: document)
            let resources = try Self.readGuidedSigningResources(imageFiles)
            if current.snapshot?.matches(document: document, resources: resources) != false {
                guard try current.targets(for: target.positionID, document: document).contains(target) else {
                    guidedSigningActionProblem = L10n.text(
                        "The field context changed. Review this occurrence again before confirming."
                    )
                    refreshGuidedSigningTargets(for: target.positionID)
                    return
                }
                let imagesMatch = try await reviewedSigningImagesMatch(
                    document: document, files: imageFiles, resources: resources
                )
                guard guidedSigningViewStateMatches(
                    expectedLocation: expectedLocation,
                    expectedContent: expectedContent,
                    expectedSession: viewBaseline
                ) else { return }
                guard imagesMatch else {
                    guidedSigningActionProblem = L10n.text(
                        "An image changed or could not be displayed. Review the updated preview before confirming."
                    )
                    renderer.reloadSigningImagePreview()
                    return
                }
            }
            if initialSeal {
                let targets = try current.declaration.positions.flatMap { position in
                    try current.targets(for: position.id, document: document)
                }
                let counts = Dictionary(grouping: targets, by: \.fieldID).mapValues(\.count)
                let planMatches = await renderedPlanMatches(counts, expectedContent)
                guard guidedSigningViewStateMatches(
                    expectedLocation: expectedLocation, expectedContent: expectedContent, expectedSession: viewBaseline
                ) else { return }
                guard planMatches else {
                    guidedSigningActionProblem = L10n.text(
                        "The rendered document does not show every required signing occurrence. Show the missing fields before confirming."
                    )
                    return
                }
            }
            guard await guidedSigningSourceCanCommit(location: expectedLocation, content: expectedContent,
                                                      session: viewBaseline, snapshot: expectedSnapshot) else { return }
            guard (try? guidedSigningResources()) == resources else {
                if viewBaseline.snapshot != nil {
                    markGuidedSigningSnapshotChanged()
                } else {
                    guidedSigningActionProblem = L10n.text(
                        "An image changed or could not be displayed. Review the updated preview before confirming."
                    )
                    renderer.reloadSigningImagePreview()
                }
                return
            }
            let profileRubric = current.positions[target.positionID]?.assignment?.profileRubric
            try current.confirmLocation(
                positionID: target.positionID,
                fieldID: target.fieldID,
                occurrence: target.occurrence,
                document: document,
                resources: resources,
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
            guard guidedSigningConflictAllowsProgress() else { return }
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
            guard await guidedSigningSourceCanCommit(location: expectedLocation, content: expectedContent,
                                                      session: current, snapshot: expectedSnapshot) else { return }
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

    private func guidedSigningSourceCanCommit(
        location: String,
        content: String,
        session: LeonardoGuidedSigningSession,
        snapshot: DocumentSnapshot?
    ) async -> Bool {
        guard guidedSigningConflictAllowsProgress() else { return false }
        let result = await guidedSigningSavedSourceCheck(
            expectedLocation: location,
            expectedContent: content,
            expectedSession: session,
            expectedSnapshot: snapshot
        )
        guard guidedSigningViewStateMatches(expectedLocation: location, expectedContent: content,
                                            expectedSession: session) else { return false }
        switch result {
        case .ready:
            return guidedSigningConflictAllowsProgress()
        case .needsSave:
            guidedSigningActionProblem = L10n.text("Save the document before confirming the first signing location.")
        case .externalChange:
            externalConflict = true
            saveStatus = "External conflict · signing review protected"
            if session.snapshot == nil {
                guidedSigningActionProblem = L10n.text(
                    "The saved signing document changed outside LeonardoMD. Reload it or save a copy before confirming."
                )
            } else {
                markGuidedSigningSnapshotChanged()
            }
        case .stateChanged:
            break
        }
        return false
    }

    func pauseGuidedPosition(positionID: String) async {
        guard var current = guidedSigningSession,
              let expectedLocation = guidedSigningLocation,
              guidedSigningConflictAllowsProgress() else { return }
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
            guard guidedSigningConflictAllowsProgress() else { return }
            try current.pause(positionID: positionID, at: Date())
            guard guidedSigningViewStateMatches(
                expectedLocation: expectedLocation,
                expectedContent: expectedContent,
                expectedSession: viewBaseline
            ) else {
                throw LeonardoSigningError.integrityFailure
            }
            guard guidedSigningConflictAllowsProgress() else { return }
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
              let expectedLocation = guidedSigningLocation,
              guidedSigningConflictAllowsProgress() else { return }
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
            guard guidedSigningConflictAllowsProgress() else { return }
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
            guard guidedSigningConflictAllowsProgress() else { return }
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
            guidedSigningActionProblem = nil
        } catch {
            if baselineLoaded {
                await persistInvalidatedGuidedSigningSessionIfNeeded(
                    current, replacing: baseline, expectedSession: viewBaseline
                )
            }
            reportGuidedSigningActionFailure(error)
        }
    }

    func signGuidedPosition(
        positionID: String,
        password: String,
        certificate: GuidedSigningCertificate? = nil,
        unlockKey: ((String, String) async throws -> LeonardoSigningKeyPair)? = nil
    ) async {
        guard var current = guidedSigningSession,
              let assignment = current.positions[positionID]?.assignment,
              let document = leonardoDocument,
              let expectedLocation = guidedSigningLocation,
              guidedSigningConflictAllowsProgress() else { return }
        let viewBaseline = current
        let expectedContent = content
        let expectedSnapshot = snapshot
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
            guard guidedSigningConflictAllowsProgress() else { return }
            let keyPair: LeonardoSigningKeyPair?
            if let certificate {
                guard certificate.id == assignment.credentialID else { throw LeonardoSigningError.credentialMismatch }
                keyPair = nil
            } else if let unlockKey {
                keyPair = try await unlockKey(assignment.credentialID, password)
            } else {
                keyPair = try await guidedSigningCredentialStore.keyPair(
                    credentialID: assignment.credentialID, password: password)
            }
            guard guidedSigningConflictAllowsProgress() else { return }
            guard guidedSigningViewStateMatches(
                expectedLocation: expectedLocation,
                expectedContent: expectedContent,
                expectedSession: viewBaseline
            ) else { throw LeonardoSigningError.integrityFailure }
            let trustStore = try await guidedSigningCredentialStore.trustStore()
            guard await guidedSigningSourceCanCommit(location: expectedLocation, content: expectedContent,
                                                      session: viewBaseline, snapshot: expectedSnapshot) else { return }
            let resources = try guidedSigningResources()
            if let certificate {
                guard resources.allSatisfy({ LeonardoLocalImagePolicy.portableSigningImagePath($0.reference)?.hasPrefix("assets/") == true }) else {
                    guidedSigningActionProblem = L10n.text("Place referenced images under assets/ before signing this Leonardo document.")
                    return
                }
                _ = try current.signWithCertificate(positionID: positionID, identity: certificate.identity,
                                                    document: document, resources: resources,
                                                    trustStore: trustStore, at: Date())
            } else if let keyPair {
                _ = try current.sign(positionID: positionID, keyPair: keyPair, document: document,
                                     resources: resources, trustStore: trustStore, at: Date())
            }
            guard guidedSigningViewStateMatches(
                expectedLocation: expectedLocation,
                expectedContent: expectedContent,
                expectedSession: viewBaseline
            ) else {
                throw LeonardoSigningError.integrityFailure
            }
            guard guidedSigningConflictAllowsProgress() else { return }
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
            guard await guidedSigningSourceCanCommit(location: expectedLocation, content: expectedContent,
                                                      session: current, snapshot: expectedSnapshot) else { return }
            guidedSigningTrustStore = trustStore
            guidedSigningVerification = current.signatureVerification(document: document,
                                                                       resources: try guidedSigningResources(),
                                                                       trustStore: trustStore)
            if guidedSigningVerification.values.contains(.modifiedSnapshot) {
                markGuidedSigningSnapshotChanged()
                return
            }
            guidedSigningTargets = []
            if current.state == .complete {
                let verified = guidedSigningVerification.count == current.declaration.positions.count
                    && guidedSigningVerification.values.allSatisfy { $0 == .valid }
                guidedSigningStatus = verified ? L10n.text("All signer positions are signed and verified locally.") : nil
            } else {
                guidedSigningStatus = L10n.text("Signature stored. The next pending signer may continue.")
            }
            guidedSigningError = nil
        } catch {
            if baselineLoaded {
                await persistInvalidatedGuidedSigningSessionIfNeeded(
                    current, replacing: baseline, expectedSession: viewBaseline
                )
            }
            if certificate != nil, current.state != .invalidated {
                guidedSigningActionProblem = L10n.text("Certificate signing did not finish. Check the certificate and try again.")
            } else {
                reportGuidedSigningActionFailure(error)
            }
        }
    }
}
