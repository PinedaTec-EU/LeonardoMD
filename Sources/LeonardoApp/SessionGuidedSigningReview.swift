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
                switch await guidedSigningSavedSourceCheck(
                    expectedLocation: expectedLocation,
                    expectedContent: expectedContent,
                    expectedSession: viewBaseline,
                    expectedSnapshot: expectedSnapshot
                ) {
                case .ready:
                    break
                case .needsSave:
                    guidedSigningActionProblem = L10n.text(
                        "Save the document before confirming the first signing location."
                    )
                    return
                case .externalChange:
                    externalConflict = true
                    saveStatus = "External conflict · signing review protected"
                    guidedSigningActionProblem = L10n.text(
                        "The saved signing document changed outside LeonardoMD. Reload it or save a copy before confirming."
                    )
                    return
                case .stateChanged:
                    guidedSigningError = L10n.text(
                        "The document moved or changed while confirming this location. Reload it before continuing."
                    )
                    return
                }
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

    func signGuidedPosition(positionID: String, password: String) async {
        guard var current = guidedSigningSession,
              let assignment = current.positions[positionID]?.assignment,
              let document = leonardoDocument,
              let expectedLocation = guidedSigningLocation,
              guidedSigningConflictAllowsProgress() else { return }
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
            guard guidedSigningConflictAllowsProgress() else { return }
            let keyPair = try await guidedSigningCredentialStore.keyPair(
                credentialID: assignment.credentialID, password: password)
            guard guidedSigningConflictAllowsProgress() else { return }
            guard guidedSigningViewStateMatches(
                expectedLocation: expectedLocation,
                expectedContent: expectedContent,
                expectedSession: viewBaseline
            ) else { throw LeonardoSigningError.integrityFailure }
            let trustStore = try await guidedSigningCredentialStore.trustStore()
            guard guidedSigningConflictAllowsProgress() else { return }
            guard guidedSigningViewStateMatches(
                expectedLocation: expectedLocation,
                expectedContent: expectedContent,
                expectedSession: viewBaseline
            ) else { throw LeonardoSigningError.integrityFailure }
            guard guidedSigningConflictAllowsProgress() else { return }
            _ = try current.sign(positionID: positionID, keyPair: keyPair, document: document,
                                  resources: try guidedSigningResources(), trustStore: trustStore, at: Date())
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
}
